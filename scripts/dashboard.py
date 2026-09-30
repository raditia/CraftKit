#!/usr/bin/env python3
"""Live agent tree for Claude Code and Codex sessions. `dashboard.py <n|session-id>` opens pinned to that session; arrows or 1-9 switch, a follows the newest, esc or q quits."""
import collections, glob, json, os, re, select, shutil, signal, sys, termios, time, tty, unicodedata

DIR = os.path.expanduser("~/.craftkit/agent-tree/events")
C = {"opus": 209, "agent": 111, "ok": 114, "dim": 244, "warn": 179, "main": 183}
SPIN = "◐◓◑◒"
ANSI = re.compile(r"\x1b\[[0-9;]*m")
CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")
QUIET = 1800  # idle seconds before a running box is labelled quiet: one long tool call looks exactly like this
ACTIVE = 1800  # a session with no event for this long leaves the strip; numbers are positions in it, pins are by session id
HOLD = 5  # seconds the followed session must be quiet before follow mode moves to a newer one
ESC_WAIT = 0.25  # an arrow key's bytes can arrive this far apart over ssh or a loaded tmux
HIDE = 86400  # a box older than this is a subagent whose stop and session end both never fired; craftkit-statusline.js uses the same

def c(key, s): return f"\x1b[38;5;{C[key]}m{s}\x1b[0m"
def bold(s): return f"\x1b[1m{s}\x1b[0m"
def cw(ch): return 2 if unicodedata.east_asian_width(ch) in "WF" else 1
def vlen(s): return sum(cw(ch) for ch in ANSI.sub("", s))
def pad(s, w): return s + " " * max(0, w - vlen(s))
def cut(s, w):
    """Shortens to `w` terminal cells, counting a wide (CJK) character as two, so a project name cannot wrap a line."""
    if vlen(s) <= w: return s
    out, used = [], 0
    for ch in s:
        if used + cw(ch) > w - 1: break
        out.append(ch); used += cw(ch)
    return "".join(out) + "…"
def dur(sec): return f"{int(sec)//60}m{int(sec)%60:02d}s" if sec >= 60 else f"{int(sec)}s"
def clean(v): return CONTROL.sub(" ", v) if isinstance(v, str) else v

def fit(line, cols):
    """Truncates to `cols` visible characters without splitting a color code, so no line wraps and breaks the in-place redraw."""
    out, seen, i = [], 0, 0
    while i < len(line) and seen < cols:
        m = ANSI.match(line, i)
        if m:
            out.append(m.group()); i = m.end()
        else:
            if seen + cw(line[i]) > cols: break
            out.append(line[i]); seen += cw(line[i]); i += 1
    return "".join(out) + "\x1b[0m"

def box(title, lines, w, color):
    edge = lambda l, r: c(color, l + "─" * (w - 2) + r)
    out = [edge("╭", "╮"), c(color, "│") + pad(" " + bold(title), w - 2) + c(color, "│")]
    out += [c(color, "│") + pad(" " + l, w - 2) + c(color, "│") for l in lines]
    return out + [edge("╰", "╯")]

def side_by_side(boxes):
    h = max(len(b) for b in boxes)
    w = [vlen(b[0]) for b in boxes]
    return ["  ".join(b[i] if i < len(b) else " " * w[j] for j, b in enumerate(boxes)) for i in range(h)]

STATES = {}

def load(path):
    """Folds only bytes appended since the last frame into that session's state. One state per log, so switching between concurrent sessions never re-reads a file from the start."""
    s = STATES.setdefault(path, {"pos": 0, "recent": collections.deque(maxlen=10), "agents": {}, "main_tool": None, "count": 0, "src": "claude", "model": None})
    try:
        if os.path.getsize(path) < s["pos"]:
            del STATES[path]
            return load(path)
        with open(path, "rb") as f:
            f.seek(s["pos"])
            chunk = f.read()
    except OSError:
        return s
    end = chunk.rfind(b"\n") + 1
    s["pos"] += end
    for line in chunk[:end].decode(errors="replace").splitlines():
        try: e = json.loads(line)
        except ValueError: continue
        if not isinstance(e, dict): continue
        e = {k: clean(v) for k, v in e.items()}
        if not isinstance(e.get("ts"), (int, float)): e["ts"] = None
        if e.get("aid") is not None: e["aid"] = str(e["aid"])
        s["count"] += 1
        s["src"] = e.get("src") or s["src"]
        s["model"] = e.get("model") or s["model"]
        aid, ev = e.get("aid"), e.get("e")
        if not aid:
            s["recent"].append(e)
            if ev == "PostToolUse": s["main_tool"] = e
            continue
        # Only a real start makes an agent: Claude Code's internal helpers fire SubagentStop alone.
        if ev == "SubagentStart":
            s["agents"][aid] = {"type": e.get("type") or "agent", "start": e.get("ts"), "end": None, "tools": 0, "last": "", "model": e.get("model")}
        a = s["agents"].get(aid)
        if a is None: continue
        s["recent"].append(e)
        if ev == "SubagentStop": a["end"] = e.get("ts") or time.time()
        elif ev == "PostToolUse":
            a["tools"] += 1
            a["last"] = str(e.get("tool")) + (f' {e["what"]}' if e.get("what") else "")
    return s

def mtime(path):
    try: return os.path.getmtime(path)
    except OSError: return 0

def live_agents(sid, now, count_only=False):
    """The logger keeps one file per running subagent and deletes it on SubagentStop, so a box exists exactly while its file does."""
    d = f"{DIR}/{sid}.agents"
    try: names = os.listdir(d)
    except OSError: return {}
    out = {}
    for n in names:
        m = mtime(f"{d}/{n}")
        if now - m >= HIDE: continue
        if count_only: out[n] = None; continue
        try:
            with open(f"{d}/{n}") as f: out[n] = (clean(f.read(40)) or "agent", m)
        except OSError: pass
    return out

def sid_of(path): return os.path.basename(path)[:-6]

USAGE = {}
PROJECTS = os.path.expanduser("~/.claude/projects")

def human(n): return f"{n / 1e6:.1f}M" if n >= 999_950 else f"{n / 1e3:.1f}k" if n >= 1e3 else str(n)

def agent_usage(sid, aid, src="claude"):
    """Model and tokens of one Claude subagent, from its own transcript (<project>/<session>/subagents/agent-<id>.jsonl).
    Read incrementally like the event log; a reply streamed over several lines shares one message id and counts once."""
    u = USAGE.setdefault((sid, aid), {"path": None, "pos": 0, "seen": set(), "total": 0, "out": 0, "model": None, "retry": 0})
    if not u["path"]:
        # Codex keeps no Claude transcript, and a missing one is looked for again at most every 5s,
        # so a dashboard left open does not glob for every agent on every frame.
        if src == "codex" or time.time() < u["retry"]: return u
        hits = glob.glob(f"{PROJECTS}/*/{glob.escape(sid)}/subagents/agent-{glob.escape(aid)}.jsonl")
        if not hits:
            u["retry"] = time.time() + 5
            return u
        u["path"] = hits[0]
    try:
        with open(u["path"], "rb") as f:
            f.seek(u["pos"]); chunk = f.read()
    except OSError:
        return u
    end = chunk.rfind(b"\n") + 1
    u["pos"] += end
    for line in chunk[:end].splitlines():
        # Tool results and prompts can be large; only replies carry usage, so skip the rest unparsed.
        if b'"assistant"' not in line: continue
        try: e = json.loads(line)
        except (ValueError, RecursionError): continue
        m = e.get("message") if isinstance(e, dict) and e.get("type") == "assistant" else None
        if not isinstance(m, dict): continue
        mid = m.get("id")
        if isinstance(mid, str) and mid:
            if mid in u["seen"]: continue
            u["seen"].add(mid)
        if isinstance(m.get("model"), str): u["model"] = clean(m["model"])
        t = m.get("usage") if isinstance(m.get("usage"), dict) else {}
        n = lambda k: t.get(k) if isinstance(t.get(k), int) else 0
        u["out"] += n("output_tokens")
        u["total"] += n("input_tokens") + n("cache_creation_input_tokens") + n("cache_read_input_tokens") + n("output_tokens")
    return u
def ended(path): return os.path.exists(f"{DIR}/{sid_of(path)}.ended")

META = {}

def meta(path):
    """Start time, tool and project from a session's first log line. Rows need only this plus mtime, so a session you are not viewing is never folded. Cached per inode, and only once the line is complete, so a recreated or half-written log is read again."""
    try: ino = os.stat(path).st_ino
    except OSError: ino = None
    hit = META.get(path)
    if hit and hit[0] == ino: return hit[1]
    first, line = {}, b""
    try:
        with open(path, "rb") as f: line = f.readline()
        first = json.loads(line or b"{}")
    except (OSError, ValueError): pass
    if not isinstance(first, dict): first = {}
    ts = first.get("ts") if isinstance(first.get("ts"), (int, float)) else None
    proj = first.get("proj")
    value = (ts or mtime(path), "Codex" if first.get("src") == "codex" else "Claude", clean(proj) if isinstance(proj, str) and proj else "?")
    if ts and line.endswith(b"\n"): META[path] = (ino, value)
    return value

def sessions(now):
    """Active, not-ended sessions in start order (ties broken by path), the same list in every window."""
    live = [p for p in glob.glob(f"{DIR}/*.jsonl") if now - mtime(p) < ACTIVE and not ended(p)]
    return sorted(live, key=lambda p: (meta(p)[0], p))

def resolve(target, now):
    """A strip number, or a session id prefix, to one log path; None when it names nothing or is ambiguous."""
    if target.isdigit():
        order = sessions(now)
        n = int(target)
        return order[n - 1] if 1 <= n <= len(order) else None
    hits = [p for p in glob.glob(f"{DIR}/*.jsonl") if sid_of(p).startswith(target)]
    return hits[0] if len(hits) == 1 else None

VIEW = {"pinned": None, "follow": None, "path": None, "order": []}

def selected(order, now):
    """Pinned wins. Otherwise follow the newest session, but hold the current one until it has been quiet HOLD seconds, so two busy sessions do not flip the view every frame."""
    if VIEW["pinned"] and not os.path.exists(VIEW["pinned"]): VIEW["pinned"] = None
    if VIEW["pinned"]: return VIEW["pinned"]
    newest = max(order, key=mtime) if order else None
    f = VIEW["follow"]
    if f not in order or (newest and newest != f and now - mtime(f) > HOLD): VIEW["follow"] = newest
    return VIEW["follow"]

def strip(order, path, now, rows):
    """One row per session, windowed around the selection so the strip never takes more than a quarter of the screen."""
    extra = (path not in order) + 1
    cap = max(1, rows // 4 - extra)
    idx = order.index(path) if path in order else 0
    lo = max(0, min(idx - cap // 2, len(order) - cap))
    lines = []
    def row(label, p, mark):
        _, src, proj = meta(p)
        n_run = len(live_agents(sid_of(p), now, count_only=True))
        state = "ended" if ended(p) else (f"{n_run} running" if n_run else "idle")
        text = f"{'▸' if mark else ' '} {label:>2} {'●' if n_run else '○'} {src:<6} {cut(proj, 22):<22} {sid_of(p)[:6]:<6}  {state:<10} {age(p, now)}"
        return bold(text) if mark else c("dim", text)
    win = order[lo:lo + cap]
    for i, p in enumerate(win, lo + 1):
        lines.append(row(str(i), p, p == path))
    if path not in order: lines.append(row("·", path, True))
    hidden = len(order) - len(win)
    hint = "←/→ or 1-9 switch · a follow newest" + (f" · +{hidden} more" if hidden else "")
    if len(order) > 1 or path not in order: lines.append(c("dim", "  " + hint))
    return lines

def age(p, now):
    quiet_for = now - mtime(p)
    return "live" if quiet_for < 5 else f"{dur(quiet_for)} ago"

def render(frame):
    size = shutil.get_terminal_size((100, 40))
    cols, rows = size.columns or 100, size.lines or 40
    now = time.time()
    order = sessions(now)
    VIEW["order"] = order
    path = selected(order, now)
    if not path:
        logs = sorted(glob.glob(f"{DIR}/*.jsonl"), key=mtime)
        if not logs: return [c("dim", "waiting for a Claude Code or Codex session…")]
        path = logs[-1]
    VIEW["path"] = path
    sid = sid_of(path)
    state = load(path)
    agents, recent = state["agents"], state["recent"]
    try:
        with open(f"{DIR}/{sid}.status.json") as f: st = json.load(f)
        if not isinstance(st, dict): st = {}
    except (OSError, ValueError): st = {}
    live = live_agents(sid, now)
    running = [dict(agents.get(aid) or {"type": t, "start": None, "end": None, "tools": 0, "last": "", "model": None}, seen=seen, aid=aid) for aid, (t, seen) in live.items()]
    done = sum(1 for a in agents.values() if a["end"])
    spent = sum(agent_usage(sid, aid, state["src"])["total"] for aid in set(agents) | set(live))
    used = f" · subagents used {human(spent)} tokens" if spent else ""

    tool = "Codex" if state["src"] == "codex" else "Claude Code"
    model = clean((st.get("model") or {}).get("display_name")) or state["model"] or "?"
    effort = clean((st.get("effort") or {}).get("level")) or "-"
    try: ctx = int((st.get("context_window") or {}).get("used_percentage") or 0)
    except (TypeError, ValueError): ctx = 0
    try: cost = float((st.get("cost") or {}).get("total_cost_usd") or 0)
    except (TypeError, ValueError): cost = 0.0
    ctx = min(max(ctx, 0), 100)
    bar = "█" * (ctx // 10) + "░" * (10 - ctx // 10)
    usage = f"effort {c('opus', effort)}   ctx {c('opus', bar)} {ctx}%   ${cost:.2f}" if st else c("dim", "effort / ctx / cost come from the CraftKit status line")

    mode = "pinned" if VIEW["pinned"] else "following newest"
    status = "ended" if ended(path) else age(path, now)
    out = [bold(f"{tool.upper()} AGENT TREE") + c("dim", f"  ·  {meta(path)[2]}  ·  {sid[:6]}  ·  {status}  ·  {mode}")]
    out += strip(order, path, now, rows) + [""]
    main_w = max(20, min(cols, 60))
    main_tool = state["main_tool"]
    out += box(cut(f"{model} · main session", main_w - 4), [
        usage,
        c("dim", "last: " + cut(f'{main_tool.get("tool")} {main_tool.get("what") or ""}', main_w - 12)) if main_tool else c("dim", "idle"),
    ], main_w, "opus")

    out.append(c("dim", "      │"))
    if running:
        out.append(c("dim", f"      ├─ {len(running)} subagent(s) running · {done} done{used}"))
        shown = sorted(running, key=lambda a: a["start"] or now)[:6]
        bw = 30
        per_row = max(1, (cols + 2) // (bw + 2))
        boxes = []
        for a in shown:
            elapsed = max(0, now - a["start"]) if isinstance(a["start"], (int, float)) else 0
            idle = now - a["seen"]
            state_label = c("dim", f"◌ quiet {dur(idle)}") if idle > QUIET else c("warn", SPIN[frame % 4] + " running")
            u = agent_usage(sid, a["aid"], state["src"])
            amodel = (u["model"] or a.get("model") or "").replace("claude-", "") or "model ?"
            spend = f"{human(u['total'])} tok · {human(u['out'])} out" if u["total"] else "tokens n/a"
            boxes.append(box(cut(str(a["type"]), bw - 4), [
                f'{state_label}  {c("dim", dur(elapsed))}',
                c("agent", cut(amodel, bw - 4)),
                c("dim", cut(spend, bw - 4)),
                f"{a['tools']} tool call(s)",
                c("dim", cut(a["last"] or "starting…", bw - 4)),
            ], bw, "agent"))
        for i in range(0, len(boxes), per_row):
            out += side_by_side(boxes[i:i + per_row])
        if len(running) > len(shown): out.append(c("dim", f"  … {len(running) - len(shown)} more running"))
    else:
        out.append(c("dim", f"      └─ no subagents running · {done} done{used}"))

    log = []
    names = {aid: a["type"] for aid, a in agents.items()}
    for e in recent:
        who = str(names.get(e.get("aid"), "main")) if e.get("aid") else "main"
        ev = e.get("e") or "event"
        what = {"SubagentStart": c("agent", "started"), "SubagentStop": c("ok", "finished")}.get(ev) \
            or f'{e.get("tool") or ev} ' + c("dim", e.get("what") or "")
        log.append(f'{c("dim", str(e.get("t", "")))}  {pad(c("main" if who == "main" else "agent", cut(who, 14)), 15)} {what}')
    foot = ["", c("dim", f'{state["count"]} events  ·  esc / q to close')]
    # A frame taller than the window scrolls it, pushing the header off the top on every redraw.
    # The oldest log lines go first, then whatever still overflows; rows - 1 because the newline
    # after the bottom row would scroll too.
    room = rows - 1 - len(out) - len(foot) - 2
    log = ["", c("dim", "── session log " + "─" * max(0, min(cols, 90) - 15))] + log[-room:] if room > 0 else []
    return [fit(l, cols) for l in (out + log + foot)[: rows - 1]]

PENDING = bytearray()

def read_key(seconds):
    """Waits up to `seconds` for a key and names it: quit, left, right, follow, a digit, or None. Bytes read together (key repeat) are kept for the next call, so no press is dropped. Arrows arrive as Esc [ C/D; only an Esc with nothing after it within ESC_WAIT quits."""
    fd = sys.stdin.fileno()
    end = time.time() + seconds
    while True:
        if not PENDING:
            left = end - time.time()
            if left <= 0 or not select.select([fd], [], [], left)[0]: return None
            chunk = os.read(fd, 32)
            if not chunk: return "quit"
            PENDING.extend(chunk)
        key = bytes(PENDING[:1]); del PENDING[:1]
        if key == b"\x1b":
            if not PENDING and select.select([fd], [], [], ESC_WAIT)[0]: PENDING.extend(os.read(fd, 32))
            if not PENDING: return "quit"
            if PENDING[:1] in (b"[", b"O"):
                # A whole sequence up to its final byte, so Ctrl+Right (Esc [1;5C) or F5 (Esc [15~)
                # never leaves a stray digit that would pin a session.
                i = 1
                while True:
                    while i < len(PENDING) and 0x20 <= PENDING[i] <= 0x3f: i += 1
                    # The final byte can arrive in a later read; parsing early would leak it as a key.
                    if i < len(PENDING) or not select.select([fd], [], [], ESC_WAIT)[0]: break
                    PENDING.extend(os.read(fd, 32))
                seq = bytes(PENDING[1:i + 1]); del PENDING[:i + 1]
                if seq == b"C": return "right"
                if seq == b"D": return "left"
        elif key in (b"q", b"Q"): return "quit"
        elif key in (b"a", b"A"): return "follow"
        elif key.isdigit() and key != b"0": return int(key)

def apply_key(key):
    """Every switch pins, so the view stops moving once you pick a session; only `a` unpins."""
    order, current = VIEW["order"], VIEW["path"]
    if key == "follow": VIEW["pinned"] = None
    elif not order: return
    elif key in ("left", "right"):
        step = 1 if key == "right" else -1
        i = order.index(current) + step if current in order else (0 if step == 1 else -1)
        VIEW["pinned"] = order[i % len(order)]
    elif isinstance(key, int) and key <= len(order): VIEW["pinned"] = order[key - 1]

def main():
    args = sys.argv[1:]
    if args[:1] == ["--resolve"]:
        p = resolve(args[1], time.time()) if len(args) > 1 else None
        if p: print(sid_of(p))
        sys.exit(0 if p else 1)
    if args:
        VIEW["pinned"] = resolve(args[0], time.time())
        if not VIEW["pinned"]:
            sys.exit(f"no session {args[0]!r}; run without an argument to see the numbered strip")
    if not (sys.stdout.isatty() and sys.stdin.isatty()):
        sys.stdout.write("\n".join(render(0)) + "\n")
        return
    # A kill sends SIGTERM and a closed window sends SIGHUP; both must still restore the terminal.
    signal.signal(signal.SIGTERM, signal.default_int_handler)
    signal.signal(signal.SIGHUP, signal.default_int_handler)
    saved = termios.tcgetattr(sys.stdin)
    sys.stdout.write("\x1b[?1049h\x1b[?25l")
    try:
        tty.setcbreak(sys.stdin)
        frame = 0
        while True:
            lines = render(frame)
            sys.stdout.write("\x1b[H" + "".join(l + "\x1b[K\n" for l in lines) + "\x1b[J")
            sys.stdout.flush()
            frame += 1
            key = read_key(1)
            if key == "quit": break
            apply_key(key)
    except KeyboardInterrupt:
        pass
    finally:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, saved)
        sys.stdout.write("\x1b[?25h\x1b[?1049l")
        sys.stdout.flush()

if __name__ == "__main__":
    main()

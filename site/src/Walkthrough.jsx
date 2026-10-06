import { useState } from 'react';
import { ArrowDown, Code, User, UsersThree, CheckCircle, ChatCircleText } from '@phosphor-icons/react';
import { repoFile } from './repo.js';

const stages = [
  { name: 'Understand', tone: 'context', title: 'Start with the project context.', body: 'The main agent reads your conventions and detects the platform before making changes.' },
  { name: 'Build', tone: 'build', title: 'Build first. Pass the fast checks.', body: 'One agent implements the saved-items screen, including loading and empty states. Type or build checks and lint pass before review.' },
  { name: 'Validate', tone: 'validate', title: 'Parallel reviews. One coordinated result.', body: 'After selecting specialists, the main agent writes tests while subagents review without editing. It then combines the findings, makes fixes, and runs the tests.' },
  { name: 'Hand back', tone: 'handoff', title: 'A checked result, ready for you.', body: 'You get a summary of changes, check results, and any remaining findings. Reviews that could not run are reported as coverage gaps.' },
];
const owners = { you: { name: 'You', icon: User }, main: { name: 'Main agent', icon: Code }, checks: { name: 'Project checks', icon: CheckCircle } };
function Task({ owner = 'main', children }) {
  const OwnerIcon = owners[owner].icon;
  return <div className="flow-task"><span className="task-owner"><OwnerIcon size={14}/>{owners[owner].name}</span><strong>{children}</strong></div>;
}
function Connector(){return <ArrowDown className="flow-connector" size={17} aria-hidden="true"/>;}

export function Walkthrough() {
  const [step, setStep] = useState(2);
  const current = stages[step];
  return <section className="walkthrough-section" id="example" aria-labelledby="example-heading"><div className="container">
    <div className="walkthrough-heading"><div><span className="eyebrow">FOLLOW ONE REQUEST</span><h2 id="example-heading">From “build this” to a checked result.</h2></div><p>One request. Four stages.</p></div>
    <div className="example-prompt"><div><ChatCircleText size={20}/><span>YOUR REQUEST</span></div><p>“Add a page where I can see my saved items. Show a loading state while they’re being fetched, and a helpful message when I haven’t saved anything yet.”</p></div>
    <div className="flow-legend" aria-label="Stage legend"><span className="legend-label">STAGES</span>{stages.map((stage, i) => <span key={stage.tone} className={`legend-item ${stage.tone}`}><i aria-hidden="true"/>{i+1}. {stage.name}</span>)}<span className="legend-parallel"><UsersThree size={17}/> Parallel subagents</span></div>
    <div className="flow-board" aria-label="Build workflow, from left to right. Choose a stage for details.">
      {stages.map((stage, index) => <section key={stage.tone} className={`flow-stage ${stage.tone} ${step === index ? 'selected' : ''}`} aria-labelledby={`stage-${index}`}>
        <button className="flow-stage-title" id={`stage-${index}`} aria-pressed={step === index} aria-controls="stage-explanation" onClick={() => setStep(index)}><span className="stage-number">0{index+1}</span><span>{stage.name}</span></button>
        <div className="flow-stage-tasks">
          {index === 0 && <><Task owner="you">Describe the feature</Task><Connector/><Task>Read project context</Task><Connector/><Task>Detect the platform</Task></>}
          {index === 1 && <><Task>Scaffold the screen</Task><Connector/><Task>Implement the feature</Task><Connector/><Task owner="checks">Type / build + lint</Task></>}
          {index === 2 && <><Task>Select specialists</Task><Connector/><div className="parallel-zone"><div className="parallel-label"><UsersThree size={17}/><span>RUN IN PARALLEL</span></div><div className="parallel-branches"><div><Task>Write tests</Task></div><div className="review-branch"><span className="task-owner"><UsersThree size={14}/>Review subagents</span><div className="review-task">Frontend</div><div className="review-task">Accessibility</div><div className="review-task">Patterns</div><div className="review-task">Simplicity</div><span className="review-mode">Read-only reviews</span></div></div></div><Connector/><Task>Combine findings + fix</Task><Connector/><Task owner="checks">Run tests</Task></>}
          {index === 3 && <><Task>Summarize changes</Task><Connector/><Task owner="checks">Report check results</Task><Connector/><Task owner="you">Inspect the result</Task></>}
        </div>
      </section>)}
    </div>
    <div className="stage-explanation" id="stage-explanation" aria-live="polite" aria-atomic="true"><div><span className="eyebrow">STAGE 0{step+1}</span><h3>{current.title}</h3></div><p>{current.body}</p></div>
    <div className="walkthrough-footer"><span>Illustrative workflow. Specialists adapt to the change and your project.</span><a href={repoFile('commands/parallel-build.md')} target="_blank" rel="noreferrer">Read the actual workflow</a></div>
  </div></section>;
}

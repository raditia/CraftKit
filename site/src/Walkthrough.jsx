import { useState } from 'react';
import { ChatCircleText } from '@phosphor-icons/react';
import buildDiagram from '../../docs/diagrams/parallel-build.svg';
import { repoFile } from './repo.js';

const stages = [
  { name: 'Understand', tone: 'context', title: 'Start with the project context.', body: 'The main agent reads your conventions and detects the platform before making changes.' },
  { name: 'Build', tone: 'build', title: 'Build first. Pass the fast checks.', body: 'One agent implements the saved-items screen, including loading and empty states. Type or build checks and lint pass before review.' },
  { name: 'Validate', tone: 'validate', title: 'Parallel reviews. One coordinated result.', body: 'After selecting specialists, the main agent writes tests while subagents review without editing. It then combines the findings, makes fixes, and runs the tests.' },
  { name: 'Hand back', tone: 'handoff', title: 'A checked result, ready for you.', body: 'You get a summary of changes, check results, and any remaining findings. Reviews that could not run are reported as coverage gaps.' },
];
export function Walkthrough() {
  const [step, setStep] = useState(2);
  const current = stages[step];
  return <section className="walkthrough-section" id="example" aria-labelledby="example-heading"><div className="container">
    <div className="walkthrough-heading"><div><span className="eyebrow">FOLLOW ONE REQUEST</span><h2 id="example-heading">From “build this” to a checked result.</h2></div><p>One request. Four stages.</p></div>
    <div className="example-prompt"><div><ChatCircleText size={20}/><span>YOUR REQUEST</span></div><p>“Add a page where I can see my saved items. Show a loading state while they’re being fetched, and a helpful message when I haven’t saved anything yet.”</p></div>
    <div className="diagram-viewport" role="region" aria-label="Build workflow diagram; scroll horizontally on narrow screens" tabIndex={0}>
      <img src={buildDiagram} width="960" height="600" alt="Context and implementation lead to fast checks. A failed check blocks review. When checks pass, specialists review alongside test authoring. The main agent combines findings, fixes errors and runs tests before reporting." loading="lazy"/>
    </div>
    <div className="stage-picker" role="group" aria-label="Choose a stage for details">
      {stages.map((stage, index) => <button key={stage.tone} className="stage-choice" type="button" aria-pressed={step === index} aria-controls="stage-explanation" onClick={() => setStep(index)}><span>0{index+1}</span> {stage.name}</button>)}
    </div>
    <div className="stage-explanation" id="stage-explanation" aria-live="polite" aria-atomic="true"><div><span className="eyebrow">STAGE 0{step+1}</span><h3>{current.title}</h3></div><p>{current.body}</p></div>
    <div className="walkthrough-footer"><span>Illustrative workflow. Specialists adapt to the change and your project.</span><a href={repoFile('commands/parallel-build.md')} target="_blank" rel="noreferrer">Read the actual workflow</a></div>
  </div></section>;
}

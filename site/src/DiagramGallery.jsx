import { DIAGRAMS, repoFile } from './repo.js';

const diagrams = Object.entries(import.meta.glob('../../docs/diagrams/*.svg', {
  eager: true,
  query: '?url',
  import: 'default',
})).sort().map(([path, src]) => {
  const slug = path.split('/').pop().slice(0, -4);
  return { slug, src, ...DIAGRAMS[slug] };
});

export function DiagramGallery() {
  return <section className="gallery-section" id="diagrams" aria-labelledby="diagrams-heading">
    <div className="container">
      <span className="eyebrow">ARCHITECTURE AND WORKFLOWS</span>
      <h2 id="diagrams-heading">Diagram gallery</h2>
      <p className="gallery-intro">Explore all {diagrams.length} diagrams. Open a row to see the full figure; on small screens, swipe across it to see every step.</p>
      <div className="gallery-list">
        {diagrams.map(({ slug, src, name, description, width, height }, index) => <details className="gallery-item" id={`diagram-${slug}`} key={slug} open={index === 0}>
          <summary><span className="gallery-name">{name}</span></summary>
          <figure>
            <div className="diagram-viewport" role="region" aria-label={`${name} diagram; scroll horizontally on narrow screens`} tabIndex={0}>
              <img src={src} width={width} height={height} style={{ minWidth: width }} alt={description} loading="lazy"/>
            </div>
            <figcaption>
              <a href={src} target="_blank" rel="noreferrer" aria-label={`Open full size: ${name} (opens in a new tab)`}>Open full size</a>
              <a href={repoFile(`docs/diagrams/${slug}.html`)} target="_blank" rel="noreferrer" aria-label={`View source: ${name} (opens in a new tab)`}>View source</a>
            </figcaption>
          </figure>
        </details>)}
      </div>
    </div>
  </section>;
}

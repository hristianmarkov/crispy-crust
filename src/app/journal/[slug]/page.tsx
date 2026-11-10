import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowUpRight, ChevronRight, Download } from "lucide-react";
import { guides } from "@/data/guides";
import { InlineText } from "@/components/guide-content";
import { RiseCalculator } from "@/components/tools-calculators";
import { siteUrl } from "@/lib/site";
import { relatedGuides, sectionId, topicForGuide } from "@/lib/journal";

export function generateStaticParams() { return guides.map((guide) => ({ slug: guide.slug })); }
export const dynamicParams = false;

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params;
  const guide = guides.find((item) => item.slug === slug);
  if (!guide) return {};
  const image = `/journal/${slug}/opengraph-image`;
  const title = guide.seoTitle ?? guide.title;
  return { title, description: guide.description, alternates: { canonical: `/journal/${slug}` }, authors: [{ name: "Crispy Crust", url: `${siteUrl}/about` }], openGraph: { type: "article", title, description: guide.description, url: `/journal/${slug}`, publishedTime: guide.publishedAt ?? "2026-11-10", modifiedTime: guide.updatedAt ?? "2026-11-10", authors: [`${siteUrl}/about`], images: [{ url: image, width: 1200, height: 630, alt: guide.title }] }, twitter: { card: "summary_large_image", title, description: guide.description, images: [{ url: image, alt: guide.title }] } };
}

export default async function Article({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const guide = guides.find((item) => item.slug === slug);
  if (!guide) notFound();
  const topic = topicForGuide(guide);
  const related = relatedGuides(guide);
  const sources = guide.sources ?? [];
  const published = guide.publishedAt ?? "2026-11-10";
  const updated = guide.updatedAt ?? published;
  const headings = guide.blocks?.flatMap((block) => block.type === "heading" && block.level !== 3 ? [{ text: block.text, id: block.id }] : []) ?? guide.sections.map((section) => ({ text: section.heading, id: sectionId(section.heading) }));
  const data = { "@context": "https://schema.org", "@graph": [
    { "@type": "Article", "@id": `${siteUrl}/journal/${slug}#article`, headline: guide.title, description: guide.description, author: { "@type": "Organization", name: "Crispy Crust", url: `${siteUrl}/about` }, publisher: { "@type": "Organization", name: "Crispy Crust", url: siteUrl, logo: { "@type": "ImageObject", url: `${siteUrl}/brand/mark.svg` } }, mainEntityOfPage: `${siteUrl}/journal/${slug}`, image: `${siteUrl}/journal/${slug}/opengraph-image`, datePublished: published, dateModified: updated, inLanguage: "en-GB", articleSection: topic?.name, citation: sources.map((source) => source.url) },
    { "@type": "BreadcrumbList", itemListElement: [ { "@type": "ListItem", position: 1, name: "Home", item: `${siteUrl}/` }, { "@type": "ListItem", position: 2, name: "The Baker’s Journal", item: `${siteUrl}/journal` }, ...(topic ? [{ "@type": "ListItem", position: 3, name: topic.name, item: `${siteUrl}/journal/topics/${topic.slug}` }] : []), { "@type": "ListItem", position: topic ? 4 : 3, name: guide.title, item: `${siteUrl}/journal/${slug}` } ] },
  ] };
  const isRecipe = [33, 41, 44, 45, 47, 50].includes(guide.number ?? 0);
  return (
    <main id="main"><article className="article-page journal-article">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(data).replace(/</g, "\\u003c") }} />
      <nav className="breadcrumbs" aria-label="Breadcrumb"><Link href="/">Home</Link><ChevronRight size={11} aria-hidden="true" /><Link href="/journal">The Baker’s Journal</Link>{topic && <><ChevronRight size={11} aria-hidden="true" /><Link href={`/journal/topics/${topic.slug}`}>{topic.name}</Link></>}</nav>
      <header><span className="eyebrow">{(topic?.name ?? guide.eyebrow).toUpperCase()}</span><h1>{guide.title}</h1><div className="article-byline"><span>By <Link href="/about">Crispy Crust</Link></span><span>{guide.readTime}</span><span>Published <time dateTime={published}>{new Date(`${published.slice(0, 10)}T12:00:00Z`).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" })}</time></span></div></header>
      <p className="article-intro"><InlineText text={guide.intro} sourceCount={sources.length} /></p>
      {isRecipe && <aside className="article-evidence-note"><strong>A note on this recipe</strong><p>This guide adapts the published method linked in the sources. Crispy Crust has not independently bake-tested this adaptation. Times are estimates; follow the visible readiness and doneness cues.</p></aside>}
      {guide.downloads?.length ? <section className="article-downloads" aria-labelledby="downloads-heading"><h2 id="downloads-heading">Your free worksheets.</h2><p>No email needed. Choose your paper size, or use the accessible HTML version.</p><div>{guide.downloads.map((download) => <a href={download.url} key={download.url}><Download size={17} aria-hidden="true" />{download.label}</a>)}</div></section> : null}
      {headings.length > 0 && <nav className="article-toc" aria-label="In this guide"><strong>IN THIS GUIDE</strong><ol>{headings.map((heading, index) => <li key={`${heading.id}-${index}`}><a href={`#${heading.id}`}>{heading.text}</a></li>)}</ol></nav>}
      <div className="article-body">
        {guide.blocks ? guide.blocks.map((block, index) => {
          if (block.type === "heading") return block.level === 3 ? <h3 key={index} id={block.id}><InlineText text={block.text} /></h3> : <h2 key={index} id={block.id}><InlineText text={block.text} /></h2>;
          if (block.type === "paragraph") return <p key={index}><InlineText text={block.text} sourceCount={sources.length} /></p>;
          if (block.type === "list") { const List = block.ordered ? "ol" : "ul"; return <List key={index}>{block.items.map((item, itemIndex) => <li key={itemIndex}><InlineText text={item} sourceCount={sources.length} /></li>)}</List>; }
          return <div key={index} className="article-table-scroll" tabIndex={0} role="region" aria-label={block.caption ?? "Guide data table"}><table>{block.caption && <caption>{block.caption}</caption>}<thead><tr>{block.headers.map((header, cell) => <th scope="col" key={cell}><InlineText text={header} sourceCount={sources.length} /></th>)}</tr></thead><tbody>{block.rows.map((row, rowIndex) => <tr key={rowIndex}>{row.map((cell, cellIndex) => cellIndex === 0 ? <th scope="row" key={cellIndex}><InlineText text={cell} sourceCount={sources.length} /></th> : <td key={cellIndex}><InlineText text={cell} sourceCount={sources.length} /></td>)}</tr>)}</tbody></table></div>;
        }) : guide.sections.map((section) => <section key={section.heading} id={sectionId(section.heading)}><h2>{section.heading}</h2>{section.paragraphs.map((paragraph) => <p key={paragraph}><InlineText text={paragraph} sourceCount={sources.length} /></p>)}{section.bullets && <ul>{section.bullets.map((bullet) => <li key={bullet}>{bullet}</li>)}</ul>}</section>)}
        {guide.number === 16 && <section className="embedded-rise-calculator" aria-labelledby="rise-tool-heading"><h2 id="rise-tool-heading">Find your container’s target mark.</h2><RiseCalculator /></section>}
        {topic && <aside className="article-next-step"><span className="eyebrow">PUT IT INTO PRACTICE</span><h2>{topic.toolName}.</h2><p>Use the {topic.name.toLowerCase()} tool alongside the method and conditions in this guide.</p><Link href={topic.tool}>Open the free tool <ArrowUpRight size={17} aria-hidden="true" /></Link>{related[0] && <p>For the next step, read <Link href={`/journal/${related[0].slug}`}>{related[0].title.toLowerCase()}</Link>.</p>}</aside>}
      </div>
      {guide.faqs.length > 0 && <section className="article-faq" id="quick-answers"><h2>A few quick answers.</h2>{guide.faqs.map((faq) => <div key={faq.question}><h3>{faq.question}</h3><p><InlineText text={faq.answer} sourceCount={sources.length} /></p></div>)}</section>}
      {sources.length > 0 && <section className="article-sources" id="sources" aria-labelledby="sources-heading"><h2 id="sources-heading">Sources & further reading.</h2><p>Published methods and guidance used for this article. Kitchen examples are illustrative unless explicitly documented.</p><ol>{sources.map((source, index) => <li key={`${source.url}-${index}`} id={`source-${index + 1}`}><a href={source.url}>{source.label}</a></li>)}</ol></section>}
      <p className="article-editorial">Crispy Crust is an upcoming sourdough baking app. <Link href="/about#editorial">Read our editorial approach</Link>.{updated !== published && <> Updated <time dateTime={updated}>{updated.slice(0, 10)}</time>.</>}</p>
      <aside className="article-related"><span className="eyebrow">A LITTLE MORE KNOW-HOW</span>{related.map((item) => <Link key={item.slug} href={`/journal/${item.slug}`}>{item.title}<span aria-hidden="true">↗</span></Link>)}{topic && <Link href={`/journal/topics/${topic.slug}`}>Explore all {topic.name.toLowerCase()} guides <span aria-hidden="true">↗</span></Link>}</aside>
    </article></main>
  );
}

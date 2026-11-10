import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowUpRight, ChevronRight } from "lucide-react";
import { guides } from "@/data/guides";
import { journalTopics, topicForGuide } from "@/lib/journal";
import { siteUrl } from "@/lib/site";

export const dynamicParams = false;
export function generateStaticParams() { return journalTopics.map((topic) => ({ topic: topic.slug })); }
export async function generateMetadata({ params }: { params: Promise<{ topic: string }> }): Promise<Metadata> {
  const { topic: slug } = await params;
  const topic = journalTopics.find((item) => item.slug === slug);
  if (!topic) return {};
  const title = `Sourdough ${topic.name} Guides`;
  return { title, description: topic.description, alternates: { canonical: `/journal/topics/${slug}` }, openGraph: { title, description: topic.description, url: `/journal/topics/${slug}`, images: ["/images/social-card.jpg"] }, twitter: { card: "summary_large_image", title, description: topic.description, images: ["/images/social-card.jpg"] } };
}

export default async function TopicPage({ params }: { params: Promise<{ topic: string }> }) {
  const { topic: slug } = await params;
  const topic = journalTopics.find((item) => item.slug === slug);
  if (!topic) notFound();
  const entries = guides.filter((guide) => topicForGuide(guide)?.slug === slug);
  const data = { "@context": "https://schema.org", "@graph": [{ "@type": "CollectionPage", name: `Sourdough ${topic.name} Guides`, description: topic.description, url: `${siteUrl}/journal/topics/${slug}`, mainEntity: { "@type": "ItemList", numberOfItems: entries.length, itemListElement: entries.map((guide, index) => ({ "@type": "ListItem", position: index + 1, url: `${siteUrl}/journal/${guide.slug}`, name: guide.title })) } }, { "@type": "BreadcrumbList", itemListElement: [{ "@type": "ListItem", position: 1, name: "Home", item: `${siteUrl}/` }, { "@type": "ListItem", position: 2, name: "The Baker’s Journal", item: `${siteUrl}/journal` }, { "@type": "ListItem", position: 3, name: topic.name, item: `${siteUrl}/journal/topics/${slug}` }] }] };
  return <main id="main" className="journal-page section journal-topic-page"><script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(data).replace(/</g, "\\u003c") }} /><nav className="breadcrumbs" aria-label="Breadcrumb"><Link href="/journal">The Baker’s Journal</Link><ChevronRight size={11} aria-hidden="true" /><span aria-current="page">{topic.name}</span></nav><div className="journal-page-heading"><span className="eyebrow">THE BAKER’S JOURNAL / {entries.length} GUIDES</span><h1>Sourdough {topic.name.toLowerCase()}.</h1><p>{topic.description}</p></div><Link className="journal-tools-banner" href={topic.tool}><div><span className="eyebrow">PUT THE KNOW-HOW TO WORK</span><h2>{topic.toolName}.</h2><p>A free tool to keep the maths beside the method.</p></div><ArrowUpRight size={25} aria-hidden="true" /></Link><div className="guide-library-grid">{entries.map((guide) => <article className="library-guide" key={guide.slug}><div className="article-meta"><span>{guide.eyebrow}</span><span>{guide.readTime}</span></div><h2><Link href={`/journal/${guide.slug}`}>{guide.title}<ArrowUpRight size={18} aria-hidden="true" /></Link></h2><p>{guide.description}</p></article>)}</div><section className="journal-other-topics"><h2>Keep exploring.</h2><nav aria-label="Other journal topics">{journalTopics.filter((item) => item.slug !== slug).map((item) => <Link href={`/journal/topics/${item.slug}`} key={item.slug}>{item.name} ↗</Link>)}</nav></section></main>;
}

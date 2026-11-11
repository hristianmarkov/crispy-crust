import type { Metadata } from "next";
import Link from "next/link";
import { ArrowUpRight, BookOpen, Calculator } from "lucide-react";
import { guides } from "@/data/guides";
import { JournalSearch } from "@/components/journal-search";
import { AppStatusLink } from "@/components/site-interactions";
import { journalTopics, topicForGuide } from "@/lib/journal";

const title = "Sourdough Guides, Schedules & Baking Advice";
const description = "Practical sourdough answers on starter care, fermentation, baking schedules and troubleshooting. Explore the Baker’s Journal, free worksheets and worked examples.";
export const metadata: Metadata = { title, description, alternates: { canonical: "/journal" }, openGraph: { title, description, url: "/journal", images: ["/images/social-card.jpg"] }, twitter: { card: "summary_large_image", title, description, images: ["/images/social-card.jpg"] } };

export default function Journal() {
  return (
    <main id="main" className="journal-page section">
      <div className="journal-page-heading"><span className="eyebrow">A FEW CRUMBS OF WISDOM</span><h1>The Baker’s Journal.</h1><p>Clear sourdough answers, from your next starter feed to the loaf you want on Sunday. A little know-how for a better next bake.</p></div>
      <div className="journal-start"><BookOpen size={26} strokeWidth={1.2} aria-hidden="true" /><div><h2>New to the jar?</h2><p>Start with <Link href="/journal/when-is-sourdough-starter-ready">starter readiness</Link>, learn <Link href="/journal/feed-sourdough-starter">how to feed it</Link>, then <Link href="/journal/sourdough-baking-schedule">plan your first bake</Link>.</p></div></div>
      <section className="journal-topic-section" aria-labelledby="topic-heading"><div className="library-heading"><div><span className="eyebrow">FOLLOW YOUR CURIOSITY</span><h2 id="topic-heading">A place to begin.</h2></div></div><div className="journal-topic-grid">{journalTopics.map((topic) => <Link className="journal-topic-card" href={`/journal/topics/${topic.slug}`} key={topic.slug}><span className="topic-count">{guides.filter((guide) => topicForGuide(guide)?.slug === topic.slug).length} guides</span><h3>{topic.name}<ArrowUpRight size={18} aria-hidden="true" /></h3><p>{topic.description}</p></Link>)}</div></section>
      <Link href="/tools" className="journal-tools-banner"><Calculator size={30} strokeWidth={1.2} aria-hidden="true" /><div><h2>A little help with the numbers.</h2><p>Feeding weights, dough hydration, rise targets and a schedule for your day. Static worked examples, without an email gate.</p></div><ArrowUpRight size={25} aria-hidden="true" /></Link>
      <JournalSearch entries={guides.map((guide) => ({ slug: guide.slug, title: guide.title, description: guide.description, category: topicForGuide(guide)?.name ?? "Fermentation", readTime: guide.readTime }))} />
      <div className="journal-newsletter"><div><h2>A little structure for your next loaf.</h2><p>Crispy Crust is an upcoming sourdough baking app. See its planned features and development status.</p></div><AppStatusLink>App in development <ArrowUpRight size={17} /></AppStatusLink></div>
    </main>
  );
}

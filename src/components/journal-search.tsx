"use client";

import Link from "next/link";
import { useState } from "react";
import { Search, ArrowUpRight } from "lucide-react";

interface JournalEntry {
  slug: string;
  title: string;
  description: string;
  category: string;
  readTime: string;
}

export function JournalSearch({ entries }: { entries: JournalEntry[] }) {
  const [query, setQuery] = useState("");
  const [category, setCategory] = useState("");
  const terms = query.toLowerCase().trim().split(/\s+/).filter(Boolean);
  const matching = entries.filter((entry) => (!category || entry.category === category) && terms.every((term) => `${entry.title} ${entry.description} ${entry.category}`.toLowerCase().includes(term)));
  const categories = [...new Set(entries.map((entry) => entry.category))];
  return (
    <section className="journal-library" aria-labelledby="library-heading">
      <div className="library-heading"><div><span className="eyebrow">FIND YOUR NEXT STEP</span><h2 id="library-heading">All the know-how.</h2></div><p>{entries.length} practical guides, one growing library.</p></div>
      <div className="journal-filters">
        <label className="journal-search"><Search size={20} aria-hidden="true" /><span className="sr-only">Search the journal</span><input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Try “starter”, “sticky dough” or “weekend”…" /></label>
        <label className="journal-category"><span className="sr-only">Filter by topic</span><select value={category} onChange={(event) => setCategory(event.target.value)}><option value="">Every topic</option>{categories.map((name) => <option key={name}>{name}</option>)}</select></label>
      </div>
      <p className="journal-result-count" role="status" aria-live="polite">{matching.length} {matching.length === 1 ? "guide" : "guides"}{query ? ` matching “${query}”` : " to explore"}</p>
      <div className="guide-library-grid">{matching.map((entry) => <article key={entry.slug} className="library-guide"><div className="article-meta"><span>{entry.category}</span><span>{entry.readTime}</span></div><h3><Link href={`/journal/${entry.slug}`}>{entry.title}<ArrowUpRight size={18} aria-hidden="true" /></Link></h3><p>{entry.description}</p></article>)}</div>
      {!matching.length && <div className="journal-empty"><h3>No guides for that search yet.</h3><p>Try a shorter phrase or choose another topic.</p><button type="button" onClick={() => { setQuery(""); setCategory(""); }}>Show all guides</button></div>}
    </section>
  );
}

import type { Metadata } from "next";
import Link from "next/link";
import { ArrowUpRight, BookOpen, Clock3, Leaf, Wheat } from "lucide-react";
import { guides } from "@/data/guides";
import { WaitlistButton } from "@/components/site-interactions";
export const metadata: Metadata = {
  title: "The Baker’s Journal — Sourdough Guides",
  description:
    "Practical sourdough guides on planning your bake, understanding your starter, and reading bulk fermentation. A little know-how for a better next loaf.",
  alternates: { canonical: "/journal" },
};
export default function Journal() {
  return (
    <main id="main" className="journal-page section">
      <div className="journal-page-heading">
        <span className="eyebrow">A FEW CRUMBS OF WISDOM</span>
        <h1>The Baker’s Journal.</h1>
        <p>
          Small lessons for a lifelong craft. Practical answers, thoughtful
          guidance, and a little confidence for your next loaf.
        </p>
      </div>
      <div className="article-grid">
        {guides.map((g, i) => (
          <Link
            className={`article-card article-card-${i}`}
            href={`/journal/${g.slug}`}
            key={g.slug}
          >
            <div className="article-art">
              <div className="journal-guide-icon">
                {i === 0 ? (
                  <Clock3 size={95} strokeWidth={0.7} />
                ) : i === 1 ? (
                  <Leaf size={95} strokeWidth={0.7} />
                ) : (
                  <Wheat size={95} strokeWidth={0.7} />
                )}
              </div>
              <span className="article-art-number">0{i + 1}</span>
              <span className="article-arrow">
                <ArrowUpRight size={20} />
              </span>
            </div>
            <div className="article-meta">
              {g.eyebrow}
              <span>{g.readTime}</span>
            </div>
            <h3>{g.title}</h3>
            <p>{g.description}</p>
          </Link>
        ))}
      </div>
      <div className="journal-newsletter">
        <div>
          <h2>A little structure for your next loaf.</h2>
          <p>
            Our sourdough companion is in the making. Get the first word when
            it’s ready.
          </p>
        </div>
        <WaitlistButton>
          Join the early birds <ArrowUpRight size={17} />
        </WaitlistButton>
      </div>
    </main>
  );
}

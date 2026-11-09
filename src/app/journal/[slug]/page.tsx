import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowRight, ChevronRight } from "lucide-react";
import { guides } from "@/data/guides";
import { siteUrl } from "@/lib/site";
export function generateStaticParams() {
  return guides.map((g) => ({ slug: g.slug }));
}
export const dynamicParams = false;
export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const g = guides.find((g) => g.slug === slug);
  if (!g) return {};
  return {
    title: g.title,
    description: g.description,
    alternates: { canonical: `/journal/${slug}` },
    openGraph: {
      type: "article",
      title: g.title,
      description: g.description,
      url: `/journal/${slug}`,
    },
  };
}
export default async function Article({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const g = guides.find((g) => g.slug === slug);
  if (!g) notFound();
  const data = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "Article",
        headline: g.title,
        description: g.description,
        author: { "@type": "Organization", name: "Crispy Crust" },
        publisher: { "@type": "Organization", name: "Crispy Crust" },
        mainEntityOfPage: `${siteUrl}/journal/${g.slug}`,
        image: `${siteUrl}/images/social-card.jpg`,
      },
      {
        "@type": "BreadcrumbList",
        itemListElement: [
          { "@type": "ListItem", position: 1, name: "Home", item: siteUrl },
          {
            "@type": "ListItem",
            position: 2,
            name: "The Baker’s Journal",
            item: `${siteUrl}/journal`,
          },
          {
            "@type": "ListItem",
            position: 3,
            name: g.title,
            item: `${siteUrl}/journal/${g.slug}`,
          },
        ],
      },
      {
        "@type": "FAQPage",
        mainEntity: g.faqs.map((f) => ({
          "@type": "Question",
          name: f.question,
          acceptedAnswer: { "@type": "Answer", text: f.answer },
        })),
      },
    ],
  };
  return (
    <main id="main">
      <article className="article-page">
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: JSON.stringify(data).replace(/</g, "\\u003c"),
          }}
        />
        <nav className="breadcrumbs" aria-label="Breadcrumb">
          <Link href="/">Home</Link>
          <ChevronRight size={11} />
          <Link href="/journal">The Baker’s Journal</Link>
        </nav>
        <header>
          <span className="eyebrow">{g.eyebrow.toUpperCase()}</span>
          <h1>{g.title}</h1>
          <div className="article-byline">
            <span>From the Crispy Crust kitchen</span>
            <span>{g.readTime}</span>
          </div>
        </header>
        <p className="article-intro">{g.intro}</p>
        <nav className="article-toc" aria-label="In this guide">
          <strong>IN THIS LITTLE GUIDE</strong>
          <ol>
            {g.sections.map((s, i) => (
              <li key={s.heading}>
                <a href={`#section-${i}`}>{s.heading}</a>
              </li>
            ))}
          </ol>
        </nav>
        <div className="article-body">
          {g.sections.map((s, i) => (
            <section key={s.heading} id={`section-${i}`}>
              <h2>{s.heading}</h2>
              {s.paragraphs.map((p) => (
                <p key={p}>{p}</p>
              ))}
              {s.bullets && (
                <ul>
                  {s.bullets.map((b) => (
                    <li key={b}>{b}</li>
                  ))}
                </ul>
              )}
            </section>
          ))}
        </div>
        <section className="article-faq">
          <h2>A few quick answers.</h2>
          {g.faqs.map((f) => (
            <div key={f.question}>
              <h3>{f.question}</h3>
              <p>{f.answer}</p>
            </div>
          ))}
        </section>
        <aside className="article-related">
          <span className="eyebrow">A LITTLE MORE KNOW-HOW</span>
          {guides
            .filter((item) => item.slug !== g.slug)
            .map((item) => (
              <Link key={item.slug} href={`/journal/${item.slug}`}>
                {item.title} <span aria-hidden="true">↗</span>
              </Link>
            ))}
          <Link href="/#features">Meet your upcoming sourdough sidekick ↗</Link>
        </aside>
      </article>
    </main>
  );
}

import type { Metadata } from "next";
import Link from "next/link";
import { tools } from "@/data/tools";
export const metadata: Metadata = {
  title: "Sourdough Formulas & Worked Examples",
  description:
    "Static explanations of starter feeding, hydration, dough rise, baking schedules and discard recipe quantities.",
  alternates: { canonical: "/tools" },
  openGraph: {
    title: "Sourdough Formulas & Worked Examples",
    description:
      "A little structure for your next loaf: starter weights, hydration, rise and a schedule that fits.",
    url: "/tools",
  },
  twitter: {
    card: "summary_large_image",
    title: "Sourdough Formulas & Worked Examples",
    description:
      "Understand feeding weights, hydration, rise and illustrative bake schedules.",
  },
};
export default function ToolsPage() {
  return (
    <main id="main" className="tools-page section">
      <header className="tools-heading">
        <span className="eyebrow">A LITTLE STRUCTURE</span>
        <h1>Good bread starts with a useful plan.</h1>
        <p>
          Static formulas and worked examples for your baking notes. Interactive baking tools belong in the upcoming mobile app.
        </p>
      </header>
      <div className="tools-directory">
        {tools.map((t) => (
          <Link
            key={t.slug}
            href={`/tools/${t.slug}`}
            className="tools-directory-card"
          >
            <span className="eyebrow">{t.eyebrow}</span>
            <h2>{t.title}</h2>
            <p>{t.description}</p>
            <span className="tools-link">Read the example →</span>
          </Link>
        ))}
      </div>
      <section className="tools-prose">
        <h2>Keep the recipe and the dough in the decision.</h2>
        <p>
          These examples explain arithmetic before display rounding. Fermentation is a living
          process: feeding ratios do not promise a peak time, and a schedule
          cannot decide whether dough is ready. Each explainer shows its formula, a
          worked example and the conditions to check.
        </p>
        <p>
          Read the <Link href="/journal">Baker’s Journal</Link> for the method
          behind each calculation. No personal calculation, schedule or baking record is entered or saved on this website.
        </p>
      </section>
    </main>
  );
}

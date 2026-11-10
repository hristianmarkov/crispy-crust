import type { Metadata } from "next";
import Link from "next/link";
import { tools } from "@/data/tools";
export const metadata: Metadata = {
  title: "Free Sourdough Calculators & Baking Tools",
  description:
    "Open sourdough tools for starter feeding, hydration, dough rise, baking schedules and choosing discard recipes by grams available.",
  alternates: { canonical: "/tools" },
  openGraph: {
    title: "Free Sourdough Calculators & Baking Tools",
    description:
      "A little structure for your next loaf: starter weights, hydration, rise and a schedule that fits.",
    url: "/tools",
  },
  twitter: {
    card: "summary_large_image",
    title: "Free Sourdough Calculators & Baking Tools",
    description:
      "Calculate feeding weights, hydration, rise and your bake schedule.",
  },
};
export default function ToolsPage() {
  return (
    <main id="main" className="tools-page section">
      <header className="tools-heading">
        <span className="eyebrow">A LITTLE STRUCTURE</span>
        <h1>Good bread starts with a useful plan.</h1>
        <p>
          Free sourdough calculators and practical tools. Get the weights, make
          a mark, and find the kitchen time your recipe needs.
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
            <span className="tools-link">Open tool →</span>
          </Link>
        ))}
      </div>
      <section className="tools-prose">
        <h2>Keep the recipe and the dough in the decision.</h2>
        <p>
          The arithmetic is exact before rounding. Fermentation is a living
          process: feeding ratios do not promise a peak time, and a schedule
          cannot decide whether dough is ready. Each tool shows its formula, a
          worked example and the conditions to check.
        </p>
        <p>
          Read the <Link href="/journal">Baker’s Journal</Link> for the method
          behind each calculation. Every tool works without an account, and
          print views keep your result close to the mixing bowl.
        </p>
      </section>
    </main>
  );
}

import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { tools } from "@/data/tools";
import { siteUrl } from "@/lib/site";
import {
  FeedingCalculator,
  HydrationCalculator,
  RiseCalculator,
  DiscardFinder,
} from "@/components/tools-calculators";
import { ScheduleCalculator } from "@/components/tools-schedule";
export const dynamicParams = false;
export function generateStaticParams() {
  return tools.map((t) => ({ slug: t.slug }));
}
export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const t = tools.find((t) => t.slug === slug);
  if (!t) return {};
  return {
    title: t.title,
    description: t.description,
    alternates: { canonical: `/tools/${slug}` },
    openGraph: {
      title: t.title,
      description: t.description,
      url: `/tools/${slug}`,
      images: [
        {
          url: "/images/social-card.jpg",
          width: 1200,
          height: 630,
          alt: "Crispy Crust sourdough tools",
        },
      ],
    },
    twitter: {
      card: "summary_large_image",
      title: t.title,
      description: t.description,
      images: ["/images/social-card.jpg"],
    },
  };
}
export default async function ToolPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const t = tools.find((t) => t.slug === slug);
  if (!t) notFound();
  const schema = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "WebApplication",
        "@id": `${siteUrl}/tools/${slug}#tool`,
        name: t.title,
        description: t.description,
        url: `${siteUrl}/tools/${slug}`,
        applicationCategory: "LifestyleApplication",
        operatingSystem: "Any",
        browserRequirements:
          "JavaScript enabled for interactive calculations; formula and examples available as HTML",
        isAccessibleForFree: true,
        publisher: {
          "@type": "Organization",
          name: "Crispy Crust",
          url: siteUrl,
        },
      },
      {
        "@type": "BreadcrumbList",
        itemListElement: [
          { "@type": "ListItem", position: 1, name: "Home", item: siteUrl },
          {
            "@type": "ListItem",
            position: 2,
            name: "Baking tools",
            item: `${siteUrl}/tools`,
          },
          {
            "@type": "ListItem",
            position: 3,
            name: t.title,
            item: `${siteUrl}/tools/${slug}`,
          },
        ],
      },
    ],
  };
  return (
    <main id="main" className="tools-page section">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(schema).replace(/</g, "\\u003c"),
        }}
      />
      <nav aria-label="Breadcrumb" className="tools-breadcrumb">
        <Link href="/">Home</Link>
        <span>/</span>
        <Link href="/tools">Baking tools</Link>
      </nav>
      <header className="tools-heading">
        <span className="eyebrow">{t.eyebrow}</span>
        <h1>{t.title}</h1>
        <p>{t.description}</p>
      </header>
      {slug === "starter-feeding-calculator" ? (
        <FeedingCalculator />
      ) : slug === "sourdough-hydration-calculator" ? (
        <HydrationCalculator />
      ) : slug === "sourdough-schedule-calculator" ? (
        <ScheduleCalculator />
      ) : slug === "sourdough-rise-calculator" ? (
        <RiseCalculator />
      ) : (
        <DiscardFinder />
      )}
      <noscript>
        <p className="tools-note">
          JavaScript is disabled. Use the formula and worked example below to
          calculate your own result. All recipe links and guidance remain
          available.
        </p>
      </noscript>
      <section className="tools-prose" aria-labelledby="formula">
        <h2 id="formula">The calculation</h2>
        <p className="tools-formula">{t.formula}</p>
        <h2>Worked example</h2>
        <p>{t.example}</p>
        <h2>What to check</h2>
        <p>{t.limit}</p>
      </section>
      {slug === "sourdough-rise-calculator" && (
        <section className="tools-prose">
          <h2>A reference chart has conditions</h2>
          <p>
            These three points reproduce Tom Cucuzza’s reference in{" "}
            <em>The Secret of Bulk Fermentation</em>, described in our{" "}
            <Link href="/journal/bulk-fermentation-chart">
              bulk fermentation chart guide
            </Link>
            . It uses a Tartine-style formula with 90% bread flour and 10% whole
            wheat in the flour blend, 75% water, 20% starter and 2% salt, bulk
            counted from starter addition, and a shaped cold proof of 12–16
            hours at about 3°C / 37°F. They are not universal shaping targets or
            measurements from Crispy Crust trials.
          </p>
          <div className="tools-table-wrap">
            <table className="tools-table">
              <caption>
                Conditional reference, with calculated marks from a 400 mL start
              </caption>
              <thead>
                <tr>
                  <th scope="col">Measured dough temperature</th>
                  <th scope="col">Reference rise</th>
                  <th scope="col">Calculated mark</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <th scope="row">27°C / 80°F</th>
                  <td>30%</td>
                  <td>520 mL</td>
                </tr>
                <tr>
                  <th scope="row">24°C / 75°F</th>
                  <td>50%</td>
                  <td>600 mL</td>
                </tr>
                <tr>
                  <th scope="row">21°C / 70°F</th>
                  <td>75%</td>
                  <td>700 mL</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p>
            The temperatures use the source’s rounded equivalents. Set this
            chart aside if the recipe, starter proportion, temperature history,
            baseline or final proof differs.{" "}
            <a href="https://thesourdoughjourney.com/tools/">
              Read The Sourdough Journey’s original tools and guides ↗
            </a>
            .
          </p>
        </section>
      )}
      <section className="tools-prose">
        <h2>Read the method</h2>
        <ul>
          {t.links.map((l) => (
            <li key={l.href}>
              <Link href={l.href}>{l.label} →</Link>
            </li>
          ))}
        </ul>
        <p className="tools-note">
          By Crispy Crust · Published 10 November 2026 ·{" "}
          <Link href="/about">How we write and review guides</Link>
        </p>
      </section>
      <aside className="tools-next">
        <h2>A little more know-how.</h2>
        <p>
          Keep your calculations alongside clear observations. The journal
          connects each number to a practical baking decision.
        </p>
        <Link className="tools-button" href="/journal">
          Explore the Baker’s Journal →
        </Link>
      </aside>
    </main>
  );
}

import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import {
  ArrowDown,
  ArrowRight,
  ArrowUpRight,
  Check,
  Clock3,
  Leaf,
  Play,
  ShieldCheck,
  Sparkles,
  Wheat,
} from "lucide-react";
import { RecipeLibrary, ScheduleExample } from "@/components/bake-story";
import { Phone } from "@/components/phone";
import {
  AppShowcase,
  Faq,
  WaitlistButton,
} from "@/components/site-interactions";
import { LaunchSection } from "@/components/footer";
import { guides } from "@/data/guides";
import { faqs } from "@/data/faqs";
import { siteUrl } from "@/lib/site";
export const metadata: Metadata = { alternates: { canonical: "/" } };
export default function Home() {
  const schema = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "Organization",
        "@id": siteUrl + "/#organization",
        name: "Crispy Crust",
        url: siteUrl,
        logo: siteUrl + "/brand/mark.svg",
      },
      {
        "@type": "WebSite",
        name: "Crispy Crust",
        url: siteUrl,
        publisher: { "@id": siteUrl + "/#organization" },
      },
      {
        "@type": "FAQPage",
        mainEntity: faqs.map((f) => ({
          "@type": "Question",
          name: f.question,
          acceptedAnswer: { "@type": "Answer", text: f.answer },
        })),
      },
    ],
  };
  return (
    <main id="main">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(schema).replace(/</g, "\\u003c"),
        }}
      />
      <section className="hero section">
        <div className="hero-copy">
          <div className="hero-eyebrow">
            <span className="tiny-dot" /> A LITTLE SOMETHING IS RISING
          </div>
          <h1>
            Good bread.
            <br />
            On <em>your</em> time.
          </h1>
          <p className="hero-description">
            Pick your bread. Tell us when you’re free.
            <br />
            Get a recipe-specific plan for mixing, folding,
            <br className="desktop-break" /> proofing and baking — built around
            your day.
          </p>
          <div className="hero-actions">
            <WaitlistButton>
              Join the early birds <ArrowUpRight size={18} />
            </WaitlistButton>
            <Link className="hero-secondary" href="#features">
              <span className="play-circle">
                <Play size={12} fill="currentColor" />
              </span>{" "}
              Take a little look
            </Link>
          </div>
          <div className="hero-availability">
            <span className="availability-icons">
              <svg
                width="15"
                height="18"
                viewBox="0 0 24 28"
                fill="currentColor"
                aria-hidden="true"
              >
                <path d="M16 4c1-1 1.7-2.6 1.5-4-1.5.1-3.2 1-4.2 2.2-.8 1-1.5 2.5-1.3 4C13.7 6.4 15.1 5.3 16 4ZM21 20c-.6 1.4-1 2-1.8 3.2-1.1 1.6-2.7 3.6-4.6 3.6-1.6 0-2-1-4.2-1-2.2 0-2.7 1-4.2 1-1.9 0-3.4-1.8-4.5-3.4C-1.5 18.7.2 11.4 3.6 8.8 5.5 7.4 8 7.2 10 8.1c1.4.6 2.4.6 3.8 0 1.8-.8 4.5-1 6.4.6-5.3 3-4.4 9.3.8 11.3Z" />
              </svg>
              <span>+</span>
              <svg
                width="19"
                height="19"
                viewBox="0 0 24 24"
                fill="currentColor"
                aria-hidden="true"
              >
                <path d="m6 4-2-3 .8-.5 2.1 3.1a11 11 0 0 1 10.2 0L19.2.5l.8.5-2 3c3.4 2.2 5 5.7 5 8H1c0-2.3 1.6-5.8 5-8Zm1 5a1 1 0 1 0 0-2 1 1 0 0 0 0 2Zm10 0a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z" />
              </svg>
            </span>{" "}
            In the making for iOS & Android
          </div>
          <div className="hero-note">
            <span className="note-line" />
            <span>
              A little less guesswork.
              <br />A lot more “I made that.”
            </span>
          </div>
        </div>
        <div className="hero-visual">
          <div className="hero-photo">
            <Image
              src="/images/sourdough.webp"
              alt="Golden sourdough loaf with leaf scoring, open crumb, and butter in the morning light"
              fill
              priority
              sizes="(max-width: 760px) 100vw, 50vw"
            />
            <div className="photo-grain" />
          </div>
          <div className="hero-seal">
            <span>BAKE A LITTLE</span>
            <Wheat size={34} strokeWidth={1.2} />
            <span>LIVE A LITTLE</span>
          </div>
          <Phone className="hero-phone" />
          <div className="hero-floating-note">
            <span className="floating-check">
              <Check size={16} />
            </span>
            <div>
              <strong>Room for real life.</strong>
              <span>And really good bread.</span>
            </div>
          </div>
          <div className="hero-photo-caption">
            YOUR KITCHEN. YOUR PACE. YOUR LOAF.
          </div>
        </div>
      </section>
      <div className="promise-strip">
        <span>
          <Leaf size={18} strokeWidth={1.5} /> Recipes for different flours
        </span>
        <i />
        <span>
          <Clock3 size={18} strokeWidth={1.5} /> Hands-on steps in your free
          time
        </span>
        <i />
        <span>
          <Wheat size={18} strokeWidth={1.5} /> Room for an overnight fridge
          proof
        </span>
      </div>
      <section className="intro-section section" id="how-it-works">
        <span className="eyebrow">A RECIPE IS ONLY HALF THE PLAN</span>
        <h2>
          Your bread. Your calendar.
          <br />
          <em>One workable plan.</em>
        </h2>
        <p>
          Choose what you want to bake, add the hours you’re available,
          <br className="desktop-break" /> and see exactly which steps need your
          hands.
        </p>
        <div className="pain-cards">
          <div className="pain-card">
            <span className="pain-icon">
              <Wheat />
            </span>
            <span className="pain-question">01 / CHOOSE YOUR RECIPE</span>
            <h3>Start with the bread you want.</h3>
            <p>
              A white sourdough, a wholemeal loaf or a tray of focaccia. Each
              recipe has its own formula, stages and timing guidance.
            </p>
          </div>
          <div className="pain-card">
            <span className="pain-icon">
              <Clock3 />
            </span>
            <span className="pain-question">02 / ADD YOUR AVAILABILITY</span>
            <h3>Tell us when you can be there.</h3>
            <p>
              Free before work and after 18:00? Mark those windows. The planner
              looks for a schedule that puts mixing, folds and shaping inside
              them.
            </p>
          </div>
          <div className="pain-card">
            <span className="pain-icon">
              <Sparkles />
            </span>
            <span className="pain-question">03 / ADJUST AS YOU BAKE</span>
            <h3>A late meeting shouldn’t ruin a loaf.</h3>
            <p>
              Update your availability and review the remaining steps. Where the
              recipe allows, a cold proof can move the bake to tomorrow.
            </p>
          </div>
        </div>
      </section>
      <RecipeLibrary />
      <ScheduleExample />
      <AppShowcase />
      <section className="philosophy">
        <div className="philosophy-photo">
          <Image
            src="/images/sourdough.webp"
            alt="The crisp golden crust of a homemade sourdough loaf"
            fill
            sizes="(max-width:760px) 100vw, 45vw"
          />
          <span className="photo-handwriting">
            The good things
            <br />
            take their time.
          </span>
        </div>
        <div className="philosophy-copy">
          <span className="eyebrow">A CALMER KIND OF BAKING</span>
          <h2>
            Life changes.
            <br />
            Your plan <em>can too.</em>
          </h2>
          <p>
            Your kitchen isn’t a lab. Some days are cooler. Some doughs are
            slower. Sometimes, life calls halfway through a fold.
          </p>
          <p>
            Need to leave before shaping? The planner helps you check whether a
            fridge pause fits your recipe and what it means for the next step.
            If the timing cannot work, you’ll see the conflict instead of an
            impossible plan.
          </p>
          <div className="philosophy-values">
            <span>
              <ShieldCheck size={18} /> Your bakes, private by default
            </span>
            <span>
              <Leaf size={18} /> Thoughtful about time & waste
            </span>
            <span>
              <Wheat size={18} /> For the first loaf & the fiftieth
            </span>
          </div>
        </div>
      </section>
      <section className="journal-section section">
        <div className="journal-heading">
          <div>
            <span className="eyebrow">A FEW CRUMBS OF WISDOM</span>
            <h2>
              A little know-how.
              <br />A better next loaf.
            </h2>
          </div>
          <Link className="text-link" href="/journal">
            The Baker’s Journal <ArrowUpRight size={18} />
          </Link>
        </div>
        <div className="article-grid">
          {guides.map((guide, i) => (
            <Link
              href={`/journal/${guide.slug}`}
              className={`article-card article-card-${i}`}
              key={guide.slug}
            >
              <div className="article-art">
                {i === 0 ? (
                  <div className="editorial-clock">
                    <span>12</span>
                    <span>3</span>
                    <span>6</span>
                    <span>9</span>
                    <i />
                    <b />
                    <em />
                  </div>
                ) : i === 1 ? (
                  <div className="editorial-starter">
                    <div className="jar-drawing">
                      <div />
                      <span>
                        your little
                        <br />
                        living thing
                      </span>
                      <i>✳</i>
                    </div>
                    <span className="editorial-spark">✧</span>
                  </div>
                ) : (
                  <div className="editorial-dough">
                    <div className="dough-bowl">
                      <i />
                      <i />
                      <i />
                    </div>
                    <span>
                      Follow the dough,
                      <br />
                      <em>not just the clock.</em>
                    </span>
                  </div>
                )}
                <span className="article-art-number">0{i + 1}</span>
                <span className="article-arrow">
                  <ArrowUpRight size={20} />
                </span>
              </div>
              <div className="article-meta">
                {guide.eyebrow}
                <span>{guide.readTime}</span>
              </div>
              <h3>{guide.title}</h3>
              <p>{guide.description}</p>
            </Link>
          ))}
        </div>
      </section>
      <Faq />
      <LaunchSection />
    </main>
  );
}

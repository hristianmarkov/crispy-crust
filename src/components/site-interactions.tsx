"use client";
import { FormEvent, useEffect, useRef, useState } from "react";
import {
  ArrowDown,
  ArrowRight,
  ArrowUpRight,
  Check,
  CheckCircle2,
  ChevronDown,
  Clock3,
  Leaf,
  Play,
  Wheat,
  X,
} from "lucide-react";
import { Phone, type Screen } from "./phone";
import { LogoMark } from "./brand";
import { faqs } from "@/data/faqs";

export function WaitlistButton({
  children,
  className = "button",
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <button
      className={className}
      onClick={() => window.dispatchEvent(new Event("open-waitlist"))}
    >
      {children}
    </button>
  );
}
export function WaitlistDialog() {
  const ref = useRef<HTMLDialogElement>(null);
  const [status, setStatus] = useState<
    "idle" | "loading" | "success" | "error"
  >("idle");
  const [error, setError] = useState("");
  useEffect(() => {
    const open = () => ref.current?.showModal();
    window.addEventListener("open-waitlist", open);
    return () => window.removeEventListener("open-waitlist", open);
  }, []);
  useEffect(() => {
    if (status === "success")
      ref.current?.querySelector<HTMLElement>("#waitlist-title")?.focus();
  }, [status]);
  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setStatus("loading");
    const form = new FormData(e.currentTarget);
    try {
      const res = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: form.get("email"),
          platform: form.get("platform"),
          website: form.get("website"),
        }),
      });
      const data = await res.json();
      if (!res.ok)
        throw new Error(
          data.error || "Something went wrong. Please try again.",
        );
      setStatus("success");
    } catch (err) {
      setStatus("error");
      setError(err instanceof Error ? err.message : "Please try again.");
    }
  }
  return (
    <dialog
      ref={ref}
      className="waitlist-dialog"
      aria-labelledby="waitlist-title"
      onClick={(e) => {
        if (e.target === e.currentTarget) ref.current?.close();
      }}
    >
      <button
        className="dialog-close"
        aria-label="Close early access form"
        onClick={() => ref.current?.close()}
      >
        <X size={21} />
      </button>
      {status === "success" ? (
        <div className="signup-success" role="status">
          <div className="success-mark">
            <Check size={30} />
          </div>
          <span className="eyebrow">GOOD THINGS TAKE A LITTLE TIME</span>
          <h2 id="waitlist-title" tabIndex={-1}>
            You’re on the list.
          </h2>
          <p>
            There’s a little more good bread in your future. Your interest is
            registered — we’ll be in touch when there’s launch news.
          </p>
          <button className="button" onClick={() => ref.current?.close()}>
            Back to the good stuff <ArrowRight size={16} />
          </button>
        </div>
      ) : (
        <>
          <div className="dialog-logo">
            <LogoMark />
          </div>
          <span className="eyebrow">A LITTLE SOMETHING IS RISING</span>
          <h2 id="waitlist-title">
            First in line.
            <br />
            Fresh from the oven.
          </h2>
          <p>
            Join the early birds for Crumb & Clock launch news. A calmer kind of
            baking is on its way.
          </p>
          <form onSubmit={submit}>
            <label htmlFor="signup-email">Your email address</label>
            <input
              id="signup-email"
              name="email"
              type="email"
              placeholder="you@yourkitchen.com"
              required
              maxLength={254}
              autoComplete="email"
            />
            <label htmlFor="signup-platform">What’s in your pocket?</label>
            <select id="signup-platform" name="platform" defaultValue="ios">
              <option value="ios">An iPhone</option>
              <option value="android">An Android phone</option>
              <option value="both">A bit of both</option>
            </select>
            <div className="honeypot" aria-hidden="true">
              <label htmlFor="signup-website">Leave this empty</label>
              <input
                id="signup-website"
                name="website"
                tabIndex={-1}
                autoComplete="off"
              />
            </div>
            <button
              disabled={status === "loading"}
              className="button signup-submit"
            >
              {status === "loading"
                ? "Saving your spot…"
                : "Save me a little spot"}{" "}
              <ArrowUpRight size={17} />
            </button>
            {status === "error" && (
              <p className="form-error" role="alert">
                {error}
              </p>
            )}
            <p className="form-privacy">
              Just launch news. No spam, no selling your details.
              <br />
              By joining, you agree to our <a href="/privacy">privacy notice</a>
              .
            </p>
          </form>
        </>
      )}
    </dialog>
  );
}
const screens: {
  id: Screen;
  label: string;
  number: string;
  title: string;
  body: string;
  points: string[];
}[] = [
  {
    id: "today",
    label: "A little daily clarity",
    number: "01",
    title: "Your next step.\nNot another rabbit hole.",
    body: "Less scrolling through recipes with flour-covered fingers. Open Today and see what needs you, what can wait, and what’s coming next.",
    points: [
      "One home for starters, timers, and bakes",
      "Clear steps for your first loaf or your fiftieth",
      "Helpful check-ins, without the constant noise",
    ],
  },
  {
    id: "starter",
    label: "A happier starter",
    number: "02",
    title: "Get to know\nyour little culture.",
    body: "Is it hungry? Has it peaked? Keep a simple record of feeds and rise, and start to recognise your own starter’s rhythm.",
    points: [
      "Track feeds, flour blends, and rise",
      "Care routines for the counter or the fridge",
      "Peak windows that explain their uncertainty",
    ],
  },
  {
    id: "planner",
    label: "Plans with breathing room",
    number: "03",
    title: "A loaf that fits\ninto your life.",
    body: "Start with when you want to slice. See the hands-on moments, make room for your plans, and adjust when the dough takes its time.",
    points: [
      "Plan forwards or backwards from serving time",
      "Separate hands-on time from waiting time",
      "Rework upcoming steps when life happens",
    ],
  },
  {
    id: "journal",
    label: "Your best loaf, again",
    number: "04",
    title: "Less “what did I do?”\nMore “let’s do that again.”",
    body: "That one beautiful loaf shouldn’t be a happy accident. Keep the formula, timings, photos, and tiny changes that made it yours.",
    points: [
      "A journal that brings your bake together",
      "Compare the details behind different results",
      "Bake again, with your own notes in hand",
    ],
  },
];
export function AppShowcase() {
  const [selected, setSelected] = useState<Screen>("today");
  function moveTab(e: React.KeyboardEvent<HTMLButtonElement>, index: number) {
    let next = index;
    if (e.key === "ArrowRight") next = (index + 1) % screens.length;
    else if (e.key === "ArrowLeft")
      next = (index + screens.length - 1) % screens.length;
    else if (e.key === "Home") next = 0;
    else if (e.key === "End") next = screens.length - 1;
    else return;
    e.preventDefault();
    setSelected(screens[next].id);
    document.getElementById(`tab-${screens[next].id}`)?.focus();
  }
  return (
    <section className="showcase section" id="features">
      <div className="section-title">
        <span className="eyebrow">
          A LITTLE STRUCTURE. A LOT OF POSSIBILITY.
        </span>
        <h2>
          From first feed
          <br />
          to the last lovely slice.
        </h2>
        <p>
          One thoughtful companion for all the things
          <br className="desktop-break" /> that go into a good loaf.
        </p>
      </div>
      <div className="showcase-tabs" role="tablist" aria-label="App features">
        {screens.map((s, i) => (
          <button
            key={s.id}
            role="tab"
            id={`tab-${s.id}`}
            aria-selected={selected === s.id}
            aria-controls={`feature-panel-${s.id}`}
            tabIndex={selected === s.id ? 0 : -1}
            onKeyDown={(e) => moveTab(e, i)}
            onClick={() => setSelected(s.id)}
          >
            <span>{s.number}</span>
            {s.label}
          </button>
        ))}
      </div>
      {screens.map((current) => (
        <div
          key={current.id}
          hidden={selected !== current.id}
          className={`feature-panel feature-${current.id}`}
          id={`feature-panel-${current.id}`}
          role="tabpanel"
          aria-labelledby={`tab-${current.id}`}
          tabIndex={0}
        >
          <div className="feature-copy">
            <div className="feature-number">
              {current.number} / THE GOOD STUFF
            </div>
            <h3>
              {current.title.split("\n").map((s, i) => (
                <span key={s}>
                  {i > 0 && <br />}
                  {s}
                </span>
              ))}
            </h3>
            <p>{current.body}</p>
            <ul>
              {current.points.map((p) => (
                <li key={p}>
                  <CheckCircle2 size={17} />
                  {p}
                </li>
              ))}
            </ul>
            <WaitlistButton className="text-link">
              That sounds like my kind of baking <ArrowUpRight size={17} />
            </WaitlistButton>
          </div>
          <div className="feature-phone-scene">
            <span className="scene-circle" />
            <span className="scene-star star-one">✳</span>
            <Phone screen={current.id} />
            <span className="scene-caption">
              A little peek at what’s coming.
            </span>
          </div>
        </div>
      ))}
      <p className="preview-note">
        App design previews. Features and screens may evolve before launch.
      </p>
    </section>
  );
}
export function Faq() {
  const [open, setOpen] = useState<number | null>(0);
  return (
    <section className="faq-section section" id="faq">
      <div className="faq-heading">
        <span className="eyebrow">A FEW THINGS YOU MIGHT BE WONDERING</span>
        <h2>
          Good questions.
          <br />
          Straight answers.
        </h2>
        <p>
          Because baking has enough
          <br />
          mysteries already.
        </p>
        <div className="faq-doodle">
          <Wheat size={57} strokeWidth={1} />
          <span>
            Let’s clear
            <br />
            things up.
          </span>
        </div>
      </div>
      <div className="faq-list">
        {faqs.map((faq, i) => (
          <div
            key={faq.question}
            className={`faq-item ${open === i ? "faq-open" : ""}`}
          >
            <h3>
              <button
                aria-expanded={open === i}
                aria-controls={`faq-answer-${i}`}
                onClick={() => setOpen(open === i ? null : i)}
              >
                {faq.question}
                <ChevronDown size={19} />
              </button>
            </h3>
            <div id={`faq-answer-${i}`} hidden={open !== i}>
              <p>{faq.answer}</p>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

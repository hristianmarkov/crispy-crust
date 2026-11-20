"use client";
import { useState } from "react";
import { ArrowUpRight, CheckCircle2, ChevronDown, Wheat } from "lucide-react";
import { Phone, type Screen } from "./phone";
import { faqs } from "@/data/faqs";

export function AppStatusLink({ children, className = "button" }: {
  children: React.ReactNode; className?: string;
}) {
  return <a className={className} href="/#app-status">{children}</a>;
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
    label: "Guided bake",
    number: "01",
    title: "Your next step.\nNot another rabbit hole.",
    body: "See the next task for your chosen recipe: mix for 15 minutes, return for a fold, or leave the dough to rise. Active steps and waiting stages are shown separately.",
    points: [
      "One home for starters, timers, and bakes",
      "Clear steps for your first loaf or your fiftieth",
      "Helpful check-ins, without the constant noise",
    ],
  },
  {
    id: "starter",
    label: "Starter care",
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
    label: "Your schedule",
    number: "03",
    title: "A loaf that fits\ninto your life.",
    body: "Free from 18:00 to 21:30, then again tomorrow morning? Add those windows. The planner checks whether your recipe can fit, including a fridge proof where suitable.",
    points: [
      "Select the hours you’re available each day",
      "Separate hands-on time from waiting time",
      "Review fridge options and timing conflicts",
    ],
  },
  {
    id: "journal",
    label: "Bake journal",
    number: "04",
    title: "Less “what did I do?”\nMore “let’s do that again.”",
    body: "Record the flour blend, hydration, kitchen temperature, actual proof time and a photo of the crumb. Next bake, compare what changed instead of starting from memory.",
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
          Your recipe, your available hours and your dough observations
          <br className="desktop-break" /> connected in one place.
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
            <AppStatusLink className="text-link">
              About the upcoming app <ArrowUpRight size={17} />
            </AppStatusLink>
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

"use client";
import { useState } from "react";
import { ArrowUpRight, Check, Clock3, Snowflake } from "lucide-react";
const recipes = [
  {
    name: "The everyday sourdough",
    flour: "Strong white flour",
    tag: "A classic place to start",
    detail:
      "Mix, fold, bulk ferment, shape and proof. Learn what ready dough looks like at each stage.",
    stages: ["Mix & folds", "Bulk rise", "Cold proof"],
  },
  {
    name: "A richer, wholemeal loaf",
    flour: "Wholemeal & white flour",
    tag: "Different flour. Its own plan.",
    detail:
      "A flour-specific formula with its own hydration and fermentation guidance, rather than the white-loaf timer copied over.",
    stages: ["Flour blend", "Dough checks", "Recipe-led timing"],
  },
  {
    name: "Rosemary focaccia",
    flour: "White flour · olive oil",
    tag: "A different kind of bake",
    detail:
      "Follow a focaccia workflow: build strength, let it rise in the tray, then dimple, top and bake. Choose a fridge rest where the recipe supports it.",
    stages: ["Fold", "Tray proof", "Dimple & bake"],
  },
];
export function RecipeLibrary() {
  return (
    <section className="recipe-section section" id="recipes">
      <div className="recipe-heading">
        <div>
          <span className="eyebrow">A RECIPE COLLECTION WITH REAL RANGE</span>
          <h2>
            One app.
            <br />
            <em>So many ways to bake.</em>
          </h2>
        </div>
        <p>
          A packed recipe library for different flours, loaf styles and
          focaccias. Each recipe brings its own ingredients, method and timing —
          so your plan starts with what’s actually in the bowl.
        </p>
      </div>
      <div className="recipe-grid">
        {recipes.map((r, i) => (
          <article className={`recipe-tile recipe-tile-${i}`} key={r.name}>
            <div className="recipe-tile-art" aria-hidden="true">
              {i === 2 ? (
                <div className="focaccia-art">
                  {Array.from({ length: 12 }, (_, n) => (
                    <i key={n} />
                  ))}
                </div>
              ) : (
                <div className={`loaf-art loaf-art-${i}`}>
                  <i />
                  <i />
                  <i />
                </div>
              )}
              <span>0{i + 1}</span>
            </div>
            <div className="recipe-tile-body">
              <span className="eyebrow">{r.flour}</span>
              <h3>{r.name}</h3>
              <strong>{r.tag}</strong>
              <p>{r.detail}</p>
              <div className="recipe-tags">
                {r.stages.map((x) => (
                  <span key={x}>{x}</span>
                ))}
              </div>
            </div>
          </article>
        ))}
      </div>
      <p className="section-footnote">
        Examples from the planned collection. Recipe timings depend on the
        formula, starter activity and dough temperature.
      </p>
    </section>
  );
}
const examples = [
  {
    label: "An evening to prep",
    window: "Friday 18:00–21:30 · Saturday 09:00–12:00",
    note: "The hands-on work stays in your evening. An overnight cold proof creates space before tomorrow’s bake.",
    steps: [
      [
        "FRI · 18:00",
        "Mix & start your folds",
        "Hands-on steps in your evening window",
      ],
      [
        "FRI · EVENING",
        "Check the dough, then shape",
        "Let fermentation readiness guide the hand-off",
      ],
      [
        "OVERNIGHT",
        "Cold proof in the fridge",
        "Waiting time — you don’t need to be there",
      ],
      [
        "SAT · MORNING",
        "Bake, cool, enjoy",
        "Allow time for the loaf to cool before slicing",
      ],
    ],
  },
  {
    label: "Out during the day",
    window: "Friday 07:00–08:00 & 18:00–21:30 · Saturday morning",
    note: "Mark the daytime as unavailable. The planner checks the recipe’s fermentation and cold-rest options; it won’t put a fold in the middle of your workday.",
    steps: [
      [
        "BEFORE WORK",
        "Refresh your starter",
        "Plan the feed around its usual activity",
      ],
      [
        "WHILE YOU’RE OUT",
        "No hands-on tasks",
        "Your unavailable hours stay visible",
      ],
      [
        "AFTER 18:00",
        "Mix, fold & check the rise",
        "The evening is your active baking window",
      ],
      [
        "NEXT MORNING",
        "Bake after a cold proof",
        "Choose a recipe that supports this schedule",
      ],
    ],
  },
  {
    label: "Plans have changed",
    window: "New constraint: no hands-on baking after 20:00",
    note: "If shaping needs longer than you have, review a recipe-supported fridge pause. Later steps move too; if no safe fit exists, choose a different start or bake day.",
    steps: [
      [
        "UPDATE",
        "Change your available hours",
        "Tell the planner when you now need to leave",
      ],
      [
        "REVIEW",
        "Check the current dough stage",
        "A fridge pause is an option, not an automatic fix",
      ],
      [
        "IF SUITABLE",
        "Refrigerate at the supported stage",
        "The recipe guides when to cool and resume",
      ],
      [
        "REPLAN",
        "See your revised next steps",
        "New times for shaping, proofing and baking",
      ],
    ],
  },
];
export function ScheduleExample() {
  const [selected, setSelected] = useState(0);
  const e = examples[selected];
  return (
    <section className="schedule-story section" id="your-schedule">
      <div className="schedule-story-copy">
        <span className="eyebrow">LET THE BAKE FIT YOUR DAY</span>
        <h2>
          Free at six?
          <br />
          <em>Start there.</em>
        </h2>
        <p>
          Select the times you’re available during the day. Crispy Crust uses
          those windows, your chosen recipe and its waiting stages to suggest a
          workable bake.
        </p>
        <p>
          Hands-on tasks need you. Fermentation and a fridge proof often don’t.
          See the difference before you commit to a plan.
        </p>
        <a className="text-link" href="#early-access">
          Get launch updates <ArrowUpRight size={17} />
        </a>
      </div>
      <div className="schedule-demo">
        <div className="demo-topline">
          <span>
            <Clock3 size={16} /> A COUNTRY SOURDOUGH EXAMPLE
          </span>
          <span>PLANNER PREVIEW</span>
        </div>
        <div
          className="scenario-buttons"
          role="group"
          aria-label="Example baking schedules"
        >
          {examples.map((x, i) => (
            <button
              key={x.label}
              aria-pressed={selected === i}
              onClick={() => setSelected(i)}
            >
              {x.label}
            </button>
          ))}
        </div>
        <div className="availability">
          <span>
            <Check size={15} /> YOUR AVAILABLE HOURS
          </span>
          <strong>{e.window}</strong>
        </div>
        <ol className="example-timeline">
          {e.steps.map(([time, title, body]) => (
            <li key={title}>
              <span className="timeline-node" />
              <div>
                <span>{time}</span>
                <h3>{title}</h3>
                <p>{body}</p>
              </div>
            </li>
          ))}
        </ol>
        <div className="fridge-note">
          <Snowflake size={20} />
          <p>{e.note}</p>
        </div>
        <p className="section-footnote">
          Illustrative flow, not a universal recipe. The planner checks whether
          the stages fit; temperature and dough observations still matter.
        </p>
      </div>
    </section>
  );
}

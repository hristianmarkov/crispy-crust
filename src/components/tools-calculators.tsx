"use client";

import { useState, type ReactNode } from "react";
import Link from "next/link";
import {
  starterFeed,
  doughHydration,
  doughRise,
} from "@/lib/baking-calculators";

const fmt = (n: number, digits = 1) =>
  new Intl.NumberFormat("en-GB", { maximumFractionDigits: digits }).format(n);
const complete = (tool: string) =>
  window.dispatchEvent(
    new CustomEvent("crispy:tool-completed", { detail: { tool } }),
  );
const value = (s: string) => (s.trim() === "" ? NaN : Number(s));

function NumberField({
  label,
  value: fieldValue,
  onChange,
  min = 0,
  suffix,
}: {
  label: string;
  value: string;
  onChange: (s: string) => void;
  min?: number;
  suffix?: string;
}) {
  return (
    <label className="tools-field">
      <span>
        {label}
        {suffix ? ` (${suffix})` : ""}
      </span>
      <input
        type="number"
        inputMode="decimal"
        min={min}
        max={10000000}
        step="any"
        value={fieldValue}
        onChange={(e) => onChange(e.target.value)}
        required
      />
    </label>
  );
}
function Result({ children }: { children: ReactNode }) {
  return (
    <div className="tools-result" aria-live="polite" aria-atomic="true">
      {children}
    </div>
  );
}
function ErrorMessage() {
  return (
    <p className="tools-error" role="status">
      Enter valid amounts in every field. Starting weights and flour must be
      greater than zero; other values may be zero.
    </p>
  );
}
function PrintButton() {
  return (
    <button
      className="tools-button tools-print"
      type="button"
      onClick={() => window.print()}
    >
      Print this result
    </button>
  );
}

export function FeedingCalculator() {
  const [mode, setMode] = useState<"target" | "retained">("target");
  const [target, setTarget] = useState("150"),
    [reserve, setReserve] = useState("25"),
    [retained, setRetained] = useState("20");
  const [starter, setStarter] = useState("1"),
    [flour, setFlour] = useState("2"),
    [water, setWater] = useState("2"),
    [hydration, setHydration] = useState("100");
  const result = starterFeed({
    mode,
    target: value(target),
    reserve: value(reserve),
    retained: value(retained),
    starterPart: value(starter),
    flourPart: value(flour),
    waterPart: value(water),
    seedHydration: value(hydration),
  });
  const preset = `${starter}:${flour}:${water}`;
  return (
    <div
      className="tools-calculator"
      onBlur={() => {
        if (result) complete("feeding");
      }}
    >
      <div className="tools-grid">
        <label className="tools-field">
          <span>Calculate from</span>
          <select
            value={mode}
            onChange={(e) => setMode(e.target.value as "target" | "retained")}
          >
            <option value="target">Starter needed for a bake + reserve</option>
            <option value="retained">Starter I am retaining</option>
          </select>
        </label>
        <label className="tools-field">
          <span>Ratio by weight (starter : flour : water)</span>
          <select
            value={
              ["1:1:1", "1:2:2", "1:5:5"].includes(preset) ? preset : "custom"
            }
            onChange={(e) => {
              if (e.target.value !== "custom") {
                const [s, f, w] = e.target.value.split(":");
                setStarter(s);
                setFlour(f);
                setWater(w);
              }
            }}
          >
            <option value="1:1:1">1 : 1 : 1</option>
            <option value="1:2:2">1 : 2 : 2</option>
            <option value="1:5:5">1 : 5 : 5</option>
            <option value="custom">Custom (edit parts below)</option>
          </select>
        </label>
        {mode === "target" ? (
          <>
            <NumberField
              label="Starter needed in recipe"
              value={target}
              onChange={setTarget}
              suffix="g"
            />
            <NumberField
              label="Starter to keep for next time"
              value={reserve}
              onChange={setReserve}
              suffix="g"
            />
          </>
        ) : (
          <NumberField
            label="Retained starter"
            value={retained}
            onChange={setRetained}
            suffix="g"
          />
        )}
        <NumberField
          label="Starter parts"
          value={starter}
          onChange={setStarter}
          min={0.01}
        />
        <NumberField
          label="Fresh flour parts"
          value={flour}
          onChange={setFlour}
          min={0.01}
        />
        <NumberField
          label="Fresh water parts"
          value={water}
          onChange={setWater}
        />
        <NumberField
          label="Retained starter hydration"
          value={hydration}
          onChange={setHydration}
          suffix="%"
        />
      </div>
      {result ? (
        <Result>
          <h2>Your feed by weight</h2>
          <dl className="tools-stats">
            <div>
              <dt>Retained starter</dt>
              <dd>{fmt(result.starter, 2)} g</dd>
            </div>
            <div>
              <dt>Add flour</dt>
              <dd>{fmt(result.flour, 2)} g</dd>
            </div>
            <div>
              <dt>Add water</dt>
              <dd>{fmt(result.water, 2)} g</dd>
            </div>
            <div>
              <dt>Total after feeding</dt>
              <dd>{fmt(result.total, 2)} g</dd>
            </div>
          </dl>
          <p>
            Fresh feed hydration: {fmt(result.freshHydration)}%. Final mixture
            hydration, including retained starter: {fmt(result.finalHydration)}
            %.
          </p>
          <p className="tools-note">
            Calculated before jar losses. Displayed weights are rounded to 0.01
            g; use the precision your scale supports and keep the proportions as
            close as practical. This ratio does not predict the peak time.
          </p>
        </Result>
      ) : (
        <ErrorMessage />
      )}
      <div className="tools-actions">
        <button
          type="button"
          className="tools-button"
          onClick={() => {
            setMode("target");
            setTarget("150");
            setReserve("25");
            setRetained("20");
            setStarter("1");
            setFlour("2");
            setWater("2");
            setHydration("100");
          }}
        >
          Reset example
        </button>
        <PrintButton />
      </div>
    </div>
  );
}

export function HydrationCalculator() {
  const [flour, setFlour] = useState("500"),
    [water, setWater] = useState("350"),
    [starter, setStarter] = useState("100"),
    [hydration, setHydration] = useState("100");
  const result = doughHydration(
    value(flour),
    value(water),
    value(starter),
    value(hydration),
  );
  return (
    <div
      className="tools-calculator"
      onBlur={() => {
        if (result) complete("hydration");
      }}
    >
      <div className="tools-grid">
        <NumberField
          label="Added flour"
          suffix="g"
          value={flour}
          onChange={setFlour}
          min={0.01}
        />
        <NumberField
          label="Added water"
          suffix="g"
          value={water}
          onChange={setWater}
        />
        <NumberField
          label="Starter used in dough"
          suffix="g"
          value={starter}
          onChange={setStarter}
        />
        <NumberField
          label="Starter hydration"
          suffix="%"
          value={hydration}
          onChange={setHydration}
        />
      </div>
      {result ? (
        <Result>
          <h2>{fmt(result.totalHydration)}% total dough hydration</h2>
          <dl className="tools-stats">
            <div>
              <dt>Added-water hydration</dt>
              <dd>{fmt(result.addedHydration)}%</dd>
            </div>
            <div>
              <dt>Flour in starter</dt>
              <dd>{fmt(result.starterFlour, 2)} g</dd>
            </div>
            <div>
              <dt>Water in starter</dt>
              <dd>{fmt(result.starterWater, 2)} g</dd>
            </div>
            <div>
              <dt>Total flour</dt>
              <dd>{fmt(result.totalFlour, 2)} g</dd>
            </div>
            <div>
              <dt>Total water</dt>
              <dd>{fmt(result.totalWater, 2)} g</dd>
            </div>
          </dl>
          <p>
            ({fmt(result.totalWater, 2)} g water ÷ {fmt(result.totalFlour, 2)} g
            flour) × 100 = {fmt(result.totalHydration)}%.
          </p>
          <p className="tools-note">
            Count only starter mixed into the dough, excluding your reserve.
            This calculator counts flour and water only; eggs, milk, fruit and
            other ingredients need their own recipe-specific accounting.
          </p>
        </Result>
      ) : (
        <ErrorMessage />
      )}
      <div className="tools-actions">
        <button
          type="button"
          className="tools-button"
          onClick={() => {
            setFlour("500");
            setWater("350");
            setStarter("100");
            setHydration("100");
          }}
        >
          Reset example
        </button>
        <PrintButton />
      </div>
    </div>
  );
}

export function RiseCalculator() {
  const [start, setStart] = useState("400"),
    [current, setCurrent] = useState("600"),
    [target, setTarget] = useState("50"),
    [unit, setUnit] = useState("mL");
  const result = doughRise(value(start), value(current), value(target));
  return (
    <div
      className="tools-calculator"
      onBlur={() => {
        if (result) complete("rise");
      }}
    >
      <div className="tools-grid">
        <label className="tools-field">
          <span>Reading units</span>
          <select value={unit} onChange={(e) => setUnit(e.target.value)}>
            <option value="mL">Volume (mL)</option>
            <option value="mm">Height (mm, straight-sided vessel only)</option>
            <option value="cm">Height (cm, straight-sided vessel only)</option>
          </select>
        </label>
        <NumberField
          label="Starting reading"
          value={start}
          onChange={setStart}
          suffix={unit}
          min={0.01}
        />
        <NumberField
          label="Current reading"
          value={current}
          onChange={setCurrent}
          suffix={unit}
          min={0.01}
        />
        <NumberField
          label="Recipe target rise"
          value={target}
          onChange={setTarget}
          suffix="%"
        />
      </div>
      {result ? (
        <Result>
          <h2>{fmt(result.percentage)}% measured rise</h2>
          <p>
            For your {fmt(value(target))}% target, mark{" "}
            <strong>
              {fmt(result.targetMark, 2)} {unit}
            </strong>{" "}
            on the container.
          </p>
          <p>
            ({fmt(value(current), 2)} − {fmt(value(start), 2)}) ÷{" "}
            {fmt(value(start), 2)} × 100 = {fmt(result.percentage)}%.
          </p>
          {result.percentage < 0 && (
            <p>
              The current reading is below the start. That records a net fall;
              it does not reveal a missed peak.
            </p>
          )}
          <p className="tools-note">
            This measures expansion from your chosen baseline. It does not
            decide when to shape. Use your recipe’s cues, the full dough and its
            measured temperature together.
          </p>
        </Result>
      ) : (
        <ErrorMessage />
      )}
      <div className="tools-actions">
        <button
          className="tools-button"
          type="button"
          onClick={() => {
            setStart("400");
            setCurrent("600");
            setTarget("50");
            setUnit("mL");
          }}
        >
          Reset example
        </button>
        <PrintButton />
      </div>
    </div>
  );
}

const discardRecipes = [
  {
    title: "100 g discard pancakes",
    grams: 100,
    type: "Skillet",
    planning: "Mix and cook",
    href: "https://www.marvellousmrsp.com/sourdough-discard-pancake-recipe/",
    source: "Marvellous Mrs P",
    guide: "/journal/sourdough-discard-recipes-by-amount",
  },
  {
    title: "Sourdough brownies",
    grams: 113,
    type: "Oven",
    planning: "Mix, bake and cool",
    href: "https://www.kingarthurbaking.com/recipes/super-fudgy-sourdough-brownies-recipe",
    source: "King Arthur Baking",
    guide: "/journal/sourdough-discard-recipes-by-amount",
  },
  {
    title: "Same-day discard pancakes",
    grams: 200,
    type: "Skillet",
    planning: "Mix and cook; no overnight rest",
    href: "https://www.thisjess.com/sourdough-discard-pancakes/",
    source: "This Jess Cooks",
    guide: "/journal/sourdough-discard-pancakes",
  },
  {
    title: "Rolled sourdough crackers",
    grams: 227,
    type: "Oven",
    planning: "Chill, roll, bake and cool",
    href: "https://www.kingarthurbaking.com/recipes/sourdough-crackers-recipe",
    source: "King Arthur Baking",
    guide: "/journal/sourdough-discard-crackers",
  },
  {
    title: "Discard focaccia",
    grams: 227,
    type: "Oven",
    planning: "Dough rises, bake and cool; includes commercial yeast",
    href: "https://www.kingarthurbaking.com/recipes/sourdough-discard-focaccia-recipe",
    source: "King Arthur Baking",
    guide: "/journal/sourdough-discard-recipes-by-amount",
  },
];
export function DiscardFinder() {
  const [grams, setGrams] = useState("227"),
    [type, setType] = useState("All");
  const amount = value(grams);
  const valid = Number.isFinite(amount) && amount >= 0 && amount <= 1e7;
  const filtered = discardRecipes.filter(
    (r) => r.grams <= amount && (type === "All" || r.type === type),
  );
  return (
    <div
      className="tools-calculator"
      onBlur={() => {
        if (valid) complete("discard");
      }}
    >
      <div className="tools-grid">
        <NumberField
          label="Usable discard on hand"
          suffix="g"
          value={grams}
          onChange={setGrams}
        />
        <label className="tools-field">
          <span>Equipment</span>
          <select value={type} onChange={(e) => setType(e.target.value)}>
            <option>All</option>
            <option>Skillet</option>
            <option>Oven</option>
          </select>
        </label>
      </div>
      <p className="tools-note">
        Choose discard from a healthy, established starter with a known storage
        history, matching the recipe’s hydration. Cook it fully; raw flour and
        discard are not ready to eat. Filtering does not verify a jar’s safety.
      </p>
      <div aria-live="polite" aria-atomic="true">
        <p className="tools-count">
          {valid
            ? `${filtered.length} published recipe${filtered.length === 1 ? "" : "s"} within your ${fmt(amount)} g`
            : "Enter a valid non-negative discard weight."}
        </p>
        {valid && filtered.length === 0 && (
          <p className="tools-result">
            This collection starts at 100 g. Choose another published
            small-batch recipe or wait for a suitable portion. Do not reduce
            only the discard in a larger formula.
          </p>
        )}
        {valid && (
          <div className="tools-recipe-grid">
            {filtered.map((r) => (
              <article className="tools-recipe-card" key={r.title}>
                <span className="eyebrow">
                  {r.grams} g · {r.type}
                </span>
                <h2>{r.title}</h2>
                <p>{r.planning}</p>
                <p>
                  Uses {r.grams} g; leaves {fmt(amount - r.grams)} g.
                </p>
                <a href={r.href}>Published recipe · {r.source} ↗</a>
                <Link href={r.guide}>Crispy Crust guide →</Link>
              </article>
            ))}
          </div>
        )}
      </div>
      <PrintButton />
    </div>
  );
}

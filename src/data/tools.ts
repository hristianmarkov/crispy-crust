export const tools = [
  {
    slug: "starter-feeding-calculator",
    title: "Sourdough Starter Feeding Calculator",
    description:
      "Calculate starter, flour and water from your feeding ratio, a bake quantity plus reserve, or the starter you retain.",
    eyebrow: "Keep your starter",
    formula:
      "One part = (starter needed + reserve) ÷ (starter parts + flour parts + water parts).",
    example:
      "For 150 g in your recipe plus 25 g reserve at 1:2:2, one part is 175 ÷ 5 = 35 g. Retain 35 g starter and add 70 g flour and 70 g water for 175 g total.",
    limit:
      "A feeding ratio sets the weights, not the time to peak. Temperature, flour and the condition of the seed starter affect activity. These weights assume no jar losses.",
    links: [
      {
        href: "/journal/sourdough-starter-feeding-ratio",
        label: "Choose a feeding ratio",
      },
      {
        href: "/journal/feed-sourdough-starter",
        label: "Feed your starter step by step",
      },
    ],
  },
  {
    slug: "sourdough-schedule-calculator",
    title: "Sourdough Schedule Calculator",
    description:
      "Work backwards from serving time through cooling, baking and fermentation, then check hands-on steps against the hours you are home.",
    eyebrow: "Find your baking window",
    formula:
      "Work backwards: serving − cooling − baking = oven loading. Subtract the final proof, shaping and bulk stages to find mixing time. Preheating overlaps the end of the cold proof.",
    example:
      "Illustrative Sunday 11:00 plan: cool from 09:00, bake from 08:10 and preheat from 07:25. With a 12-hour cold proof, shaping is Saturday 19:50–20:10, mixing begins 14:50, and an eight-hour starter window starts 06:50. A 07:00–22:00 home window conflicts with that feed; the calculator suggests an 11:15 serving time with the same durations.",
    limit:
      "Replace the example durations with a recipe you have tested in your kitchen. Fermentation timings are estimates. When the dough is not ready, reassess the serving time and follow the recipe’s readiness cues. A home window is assumed to repeat every day; specific appointments still need a manual check.",
    links: [
      {
        href: "/journal/sourdough-baking-schedule",
        label: "Plan around your day",
      },
      {
        href: "/journal/weekend-sourdough-baking-schedule",
        label: "A weekend baking schedule",
      },
      {
        href: "/journal/sourdough-schedule-for-working-people",
        label: "Bake around a full-time job",
      },
    ],
  },
  {
    slug: "sourdough-hydration-calculator",
    title: "Sourdough Hydration Calculator",
    description:
      "Calculate total dough hydration including your starter, with separate flour and water contributions for liquid or stiff starter.",
    eyebrow: "Understand the dough",
    formula:
      "Starter flour = starter weight ÷ (1 + starter hydration ÷ 100). Starter water = starter weight − starter flour. Total hydration = total water ÷ total flour × 100.",
    example:
      "With 500 g added flour, 350 g added water and 100 g of 100%-hydration starter, the starter contributes 50 g flour and 50 g water. Total hydration is 400 ÷ 550 × 100 = 72.7%, while added-water hydration is 70%.",
    limit:
      "The starter amount is the portion that goes into the dough. Exclude your reserve. Hydration compares flour and water by weight; flour type and other ingredients still change handling. This calculator does not account for water in milk, eggs, fruit or other additions.",
    links: [
      {
        href: "/journal/calculate-sourdough-hydration-with-starter",
        label: "Learn the hydration calculation",
      },
      {
        href: "/journal/bakers-percentages-sourdough",
        label: "Understand baker’s percentages",
      },
    ],
  },
  {
    slug: "sourdough-rise-calculator",
    title: "Sourdough Percentage Rise Calculator",
    description:
      "Turn starting and current container readings into percentage dough rise, and calculate the mark for a recipe’s target rise.",
    eyebrow: "Read the rise",
    formula:
      "Percentage rise = (current reading − starting reading) ÷ starting reading × 100. Target mark = starting reading × (1 + target rise ÷ 100).",
    example:
      "From a 400 mL starting reading to 600 mL, the increase is 200 mL: 200 ÷ 400 × 100 = 50%. A 75% target from the same start is 400 × 1.75 = 700 mL. In a straight-sided jar, 20 mm to 30 mm is also 50%.",
    limit:
      "Use consistent units and the same baseline. Height is a proxy for volume only in a vessel with a constant cross-section. In a tapered bowl use calibrated volume marks. A late starting mark, folds and a small aliquot sample can change the interpretation. The percentage alone is not a shaping decision.",
    links: [
      {
        href: "/journal/measure-sourdough-rise-percentage",
        label: "Measure percentage rise",
      },
      {
        href: "/journal/bulk-fermentation-chart",
        label: "Read the conditional temperature chart",
      },
      {
        href: "/journal/when-is-bulk-fermentation-done",
        label: "Judge bulk readiness",
      },
    ],
  },
  {
    slug: "discard-recipe-finder",
    title: "Sourdough Discard Recipes by Grams Available",
    description:
      "Find published sourdough discard recipes for 100, 113, 200 or 227 grams, with equipment and planning notes before you mix.",
    eyebrow: "Use what is in the jar",
    formula:
      "Weigh your usable discard, choose a recipe that uses that amount or less, then calculate leftover discard = available grams − recipe grams.",
    example:
      "With 200 g available, the 100 g pancakes leave 100 g and the 113 g brownies leave 87 g. The 200 g pancake recipe uses the full portion. A recipe requiring 227 g does not fit until you have that amount.",
    limit:
      "This is a selection tool, not a recipe scaler. Use the published formula’s hydration, ingredients and cooking directions. Keep discard from a healthy established starter, label the oldest collection date, and discard suspect growth or jars with an uncertain history. Cook raw flour, eggs and discard fully.",
    links: [
      {
        href: "/journal/sourdough-discard-recipes-by-amount",
        label: "Choose discard recipes by amount",
      },
      {
        href: "/journal/store-sourdough-discard",
        label: "Store and label discard",
      },
      {
        href: "/journal/sourdough-discard-pancakes",
        label: "Same-day pancake guide",
      },
      {
        href: "/journal/sourdough-discard-crackers",
        label: "Rolled cracker guide",
      },
    ],
  },
] as const;

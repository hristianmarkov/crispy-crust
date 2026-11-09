export interface Guide {
  slug: string;
  title: string;
  description: string;
  eyebrow: string;
  readTime: string;
  intro: string;
  sections: {
    heading: string;
    paragraphs: string[];
    bullets?: string[];
  }[];
  faqs: { question: string; answer: string }[];
}

export const guides: Guide[] = [
  {
    slug: "sourdough-baking-schedule",
    title: "How to plan sourdough around your day",
    description:
      "Build a realistic sourdough baking schedule by working backwards from serving time, separating hands-on work from fermentation, and allowing room for your dough to change pace.",
    eyebrow: "A little planning",
    readTime: "5 min read",
    intro:
      "A useful sourdough schedule starts with when you want to eat, then works backwards through cooling, baking, proofing, shaping, bulk fermentation and mixing. Treat fermentation times as windows. Your dough's temperature and progress decide when a stage is ready.",
    sections: [
      {
        heading: "Start with the moment you want to slice",
        paragraphs: [
          "Put your serving time on the page first. Leave the cooling time recommended by your recipe: the inside of a loaf continues to set after it leaves the oven. Cutting too early can give you a sticky crumb even when the loaf is baked through.",
          "Work backwards through baking and preheating next. Check whether your recipe calls for a preheated Dutch oven, a covered baking phase or an oven-temperature change. Those details determine when you need to be in the kitchen.",
        ],
      },
      {
        heading: "Separate kitchen time from waiting time",
        paragraphs: [
          "Mixing, folding, shaping and loading the oven need your attention. Much of bulk fermentation and proofing does not. Mark those two kinds of time differently, then add the parts of your day you cannot move: work, sleep, school runs or an afternoon away.",
          "Folds are brief, but several folds spread across an afternoon still constrain your plans. Look at the whole sequence before starting a recipe, rather than only its total preparation time.",
        ],
        bullets: [
          "Reserve hands-on windows for feeding, mixing, folds, shaping and baking.",
          "Leave observation windows to check how fermentation is progressing.",
          "Include preheating and cooling, not just oven time.",
          "Check fridge space and baking-vessel capacity if making several loaves.",
        ],
      },
      {
        heading: "Use an overnight proof thoughtfully",
        paragraphs: [
          "A recipe with a refrigerated final proof can make an overnight schedule practical. You might feed and mix on Saturday, shape when the dough is ready, then refrigerate and bake on Sunday morning. Follow a recipe designed for that method rather than adding a long cold proof to any dough.",
          "The fridge slows fermentation; it does not stop it immediately. Dough size, fridge temperature, flour and fermentation before refrigeration all affect how much flexibility you have. An overnight proof is a planning tool, not an unlimited pause button.",
        ],
      },
      {
        heading: "Give the dough room to run late",
        paragraphs: [
          "A cooler kitchen can stretch fermentation well beyond the time printed in a recipe. Write down the dough temperature when you mix and check the recipe's readiness cues as you approach its estimated window. If the dough is not ready, a countdown reaching zero does not make shaping the right next step.",
          "When the schedule slips, keep the completed steps and reconsider the remaining ones. Use adjustments supported by your recipe, or move the serving time. Avoid compressing fermentation or skipping cooling simply to protect the original deadline. Record what actually happened: your next schedule will be better grounded in your kitchen.",
        ],
      },
    ],
    faqs: [
      {
        question: "Can I make sourdough if I work full time?",
        answer:
          "Yes. Choose a tested recipe whose hands-on steps fit your availability, often with an overnight refrigerated proof. Check the timing of feeding, mixing, folds and shaping before you begin, and allow flexibility for fermentation.",
      },
      {
        question: "How long does sourdough take from start to finish?",
        answer:
          "Many schedules span one or two days, but there is no universal duration. Starter readiness, inoculation, dough temperature, flour and proofing method all change the timing. Use your recipe's estimates together with observations of the dough.",
      },
      {
        question: "Can I put sourdough in the fridge to delay baking?",
        answer:
          "Refrigeration can provide flexibility when your recipe includes a cold-proof stage. It slows fermentation gradually, and the workable duration depends on the dough and fridge temperature. Follow the recipe's guidance rather than treating refrigeration as an indefinite pause.",
      },
    ],
  },
  {
    slug: "when-is-sourdough-starter-ready",
    title: "Is your sourdough starter ready to bake?",
    description:
      "Learn the signs of a starter that is ready for bread: a predictable rise after feeding, bubbles throughout, and a pattern you can recognise in your own jar.",
    eyebrow: "Know your starter",
    readTime: "4 min read",
    intro:
      "A starter is usually ready to leaven bread when it rises reliably after feeding and shows a repeatable pattern of activity. For an established starter, many recipes use it near its peak. A clock, a jar of bubbles or the float test alone cannot tell you everything.",
    sections: [
      {
        heading: "Look for a repeatable rise",
        paragraphs: [
          "Mark the starter's height immediately after a feed. Use a straight-sided jar with room for expansion and keep the sides reasonably clear. A rubber band or removable mark makes growth easier to compare than memory does.",
          "Look for bubbles through the mixture and a clear rise above the starting mark. Some starters double readily; others behave differently because of flour, hydration or feeding ratio. For a young starter, repeatable activity across several feeds is more useful than one dramatic rise early in its life.",
        ],
      },
      {
        heading: "Get to know the peak in your jar",
        paragraphs: [
          "After feeding, an active starter rises, reaches a high point and eventually falls. Around its peak, the top may change from domed to flatter before the mixture begins to recede. A tide mark on the glass can reveal a peak you missed.",
          "For recipes calling for ripe starter, aim for the active window described by that recipe. The exact window depends on the jar and feed. Starter that has fallen is not automatically unusable, but its condition may affect flavour and fermentation speed; a fresh feed can make the timing more predictable.",
        ],
      },
      {
        heading: "Compare like with like",
        paragraphs: [
          "Record the feeding ratio by weight, flour, water and room temperature. A larger feed usually takes longer to mature than a smaller one under otherwise similar conditions. A warmer location generally speeds activity, while a cooler room can delay it.",
          "Changing several things at once makes patterns hard to interpret. Try observing the same feed over a few cycles. Record the time to check again, rather than promising yourself it will peak at an exact minute.",
        ],
        bullets: [
          "Mark the level just after feeding.",
          "Note the weights of starter, flour and water.",
          "Check for rise and bubbles throughout, not only at the surface.",
          "Record the highest level you actually observed; label a missed peak as unknown.",
        ],
      },
      {
        heading: "Treat quick tests as clues",
        paragraphs: [
          "The float test checks whether a small spoonful holds enough gas to float. Flour choice, hydration and handling can change the result. A floating sample is not proof that a new culture is mature, and a sinking sample does not by itself mean an established starter cannot bake bread.",
          "If a starter changes unexpectedly, review recent feeding, temperature and storage changes. Activity is not a food-safety test. Visible mould or unusual pink or orange discolouration is a reason to stop using it and consult established food-safety guidance. A photo or this checklist cannot certify a starter as safe.",
        ],
      },
    ],
    faqs: [
      {
        question: "Does sourdough starter have to double before baking?",
        answer:
          "Doubling is a useful benchmark for many starters, but flour and hydration affect visible rise. Look for reliable activity over repeated feeds and follow the readiness cues in your recipe, rather than relying on a single height measurement.",
      },
      {
        question: "Is the sourdough float test reliable?",
        answer:
          "It is only one clue. A starter may sink because of its flour, hydration or how the sample was handled. Assess its rise pattern, bubbles and feeding history alongside the test.",
      },
      {
        question: "Why is my starter taking longer than yesterday?",
        answer:
          "A cooler room, a larger feeding ratio, a different flour or a change in the starter's condition can slow its rise. Compare the feed and temperature with previous entries before assuming something is wrong.",
      },
    ],
  },
  {
    slug: "when-is-bulk-fermentation-done",
    title: "How to tell when bulk fermentation is done",
    description:
      "Read bulk fermentation using dough temperature, measured rise, bubbles and texture. Learn why the timer is an estimate and why every dough does not need to double.",
    eyebrow: "Follow the dough",
    readTime: "5 min read",
    intro:
      "Bulk fermentation is ready when the dough has developed the rise and structure your recipe calls for. Use a combination of measured growth, bubbles, texture and dough temperature. Elapsed time is a useful reference, but it is not a readiness test on its own.",
    sections: [
      {
        heading: "Know when your bulk stage begins",
        paragraphs: [
          "Bulk fermentation generally starts when starter is incorporated into the dough and ends when the dough is divided or shaped. An earlier flour-and-water rest without starter does not count toward that fermentation time. Check how your recipe defines its stages so you compare the same thing each bake.",
          "Folds happen during bulk, so their time usually belongs within the overall fermentation window. Counting bulk only after the last fold can accidentally extend fermentation well beyond the recipe's intention.",
        ],
      },
      {
        heading: "Measure the rise you can actually see",
        paragraphs: [
          "A transparent, straight-sided container helps you follow expansion. Mark the starting level after mixing and compare the dough against that mark. In a bowl with sloping sides, a change in height does not translate neatly to the same percentage change in volume.",
          "Use the rise target in your recipe. Some doughs are shaped well before doubling, especially when they will continue fermenting during a long final proof. Flour choice, dough strength and temperature affect the appropriate target. There is no single percentage that works for every loaf.",
        ],
      },
      {
        heading: "Read several signs together",
        paragraphs: [
          "As fermentation progresses, look for bubbles at the sides and beneath the surface, a more aerated feel and a dough that moves with some lightness when the container is gently shaken. The top may look slightly rounded rather than flat and dense. These signs vary with hydration and flour, so compare them with your own earlier doughs.",
          "A very loose dough may spread without holding a dramatic dome. A whole-grain dough may feel and look different from a strong white-flour dough. Avoid repeatedly pressing or stretching the dough just to inspect it; observation should not become extra handling.",
        ],
        bullets: [
          "Compare growth with the starting mark and the recipe's target.",
          "Look for aeration through the dough, not just a few surface bubbles.",
          "Consider the dough temperature and the remaining proofing plan.",
          "Use elapsed time as context for these observations.",
        ],
      },
      {
        heading: "Adjust the plan, then learn from the loaf",
        paragraphs: [
          "Dough in a cool kitchen often needs more time. If growth is limited and the dough still feels dense, make another check rather than shaping automatically when the timer sounds. If the dough is advancing faster than expected, reassess sooner instead of waiting for the scheduled finish.",
          "Record the temperature, approximate rise and actual bulk duration before shaping. After baking, add a crumb photo and your notes. A dense crumb or a spreading loaf can have several causes, so avoid diagnosing fermentation from one photo alone. Change one manageable variable on the next bake and compare the result.",
        ],
      },
    ],
    faqs: [
      {
        question: "Should sourdough double during bulk fermentation?",
        answer:
          "Not always. The appropriate rise depends on the recipe, dough temperature, flour and remaining proof. Many recipes call for shaping before doubling. Follow the recipe's target and assess the dough's other signs of readiness.",
      },
      {
        question: "How long should bulk fermentation take?",
        answer:
          "It depends on temperature, starter activity, inoculation and the formula. Start with the recipe's estimated window, then use measured rise and dough observations to decide when to shape.",
      },
      {
        question: "Is the poke test useful during bulk fermentation?",
        answer:
          "The poke test is more commonly used as one clue during final proofing. During bulk, measured rise, visible aeration, texture and temperature usually provide a clearer combined picture. No single test replaces the recipe's guidance.",
      },
    ],
  },
];

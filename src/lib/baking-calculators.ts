/** Calculations use unrounded weights; round only when displaying results. */
export function starterFeed(input: {
  mode: "target" | "retained";
  target: number;
  reserve: number;
  retained: number;
  starterPart: number;
  flourPart: number;
  waterPart: number;
  seedHydration: number;
}) {
  const {
    mode,
    target,
    reserve,
    retained,
    starterPart,
    flourPart,
    waterPart,
    seedHydration,
  } = input;
  const values = [
    ...(mode === "target" ? [target, reserve] : [retained]),
    starterPart,
    flourPart,
    waterPart,
    seedHydration,
  ];
  if (
    values.some((n) => !Number.isFinite(n) || n < 0 || n > 1e7) ||
    starterPart <= 0 ||
    flourPart <= 0 ||
    (mode === "target" ? target + reserve <= 0 : retained <= 0)
  ) {
    return null;
  }
  const part =
    mode === "target"
      ? (target + reserve) / (starterPart + flourPart + waterPart)
      : retained / starterPart;
  const starter = part * starterPart;
  const flour = part * flourPart;
  const water = part * waterPart;
  const seedFlour = starter / (1 + seedHydration / 100);
  const seedWater = starter - seedFlour;
  return {
    starter,
    flour,
    water,
    total: starter + flour + water,
    freshHydration: (water / flour) * 100,
    finalHydration: ((water + seedWater) / (flour + seedFlour)) * 100,
  };
}

export function doughHydration(
  flour: number,
  water: number,
  starter: number,
  starterHydration: number,
) {
  if (
    [flour, water, starter, starterHydration].some(
      (n) => !Number.isFinite(n) || n < 0 || n > 1e7,
    ) ||
    flour <= 0
  )
    return null;
  const starterFlour = starter / (1 + starterHydration / 100);
  const starterWater = starter - starterFlour;
  const totalFlour = flour + starterFlour;
  const totalWater = water + starterWater;
  return {
    starterFlour,
    starterWater,
    totalFlour,
    totalWater,
    addedHydration: (water / flour) * 100,
    totalHydration: (totalWater / totalFlour) * 100,
  };
}

export function doughRise(start: number, current: number, target: number) {
  if (
    ![start, current, target].every(Number.isFinite) ||
    start <= 0 ||
    current <= 0 ||
    target < 0 ||
    [start, current, target].some((n) => n > 1e7)
  )
    return null;
  return {
    percentage: ((current - start) / start) * 100,
    targetMark: start * (1 + target / 100),
  };
}

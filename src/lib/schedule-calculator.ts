/** Backwards arithmetic, not a model of fermentation or starter readiness. */
export type ScheduleInput = {
  serving: string;
  homeStart: string;
  homeEnd: string;
  cooling: number;
  baking: number;
  preheat: number;
  coldProof: number;
  shaping: number;
  bulk: number;
  mixing: number;
  starter: number;
};
export type ScheduleRow = {
  id: string;
  label: string;
  start: Date;
  end: Date;
  handsOn: boolean;
  note: string;
  conflict: boolean;
};
export type ScheduleResult = {
  rows: ScheduleRow[];
  conflicts: ScheduleRow[];
  serving: Date;
  laterServing: Date | null;
  error: string | null;
};
export const defaultSchedule: ScheduleInput = {
  serving: "2026-11-15T11:00",
  homeStart: "07:00",
  homeEnd: "22:00",
  cooling: 120,
  baking: 50,
  preheat: 45,
  coldProof: 720,
  shaping: 20,
  bulk: 300,
  mixing: 20,
  starter: 480,
};
const minute = 60_000;
const plus = (time: Date, minutes: number) =>
  new Date(time.getTime() + minutes * minute);
const timeParts = (time: string) => time.split(":").map(Number);
const validClock = (time: string) => /^([01]\d|2[0-3]):[0-5]\d$/.test(time);

/** A hands-on interval must fit wholly inside one daily home window. Equal times mean all day. */
export function isAvailable(
  start: Date,
  end: Date,
  homeStart: string,
  homeEnd: string,
): boolean {
  if (homeStart === homeEnd) return true;
  const [startHour, startMinute] = timeParts(homeStart);
  const [endHour, endMinute] = timeParts(homeEnd);
  for (let offset = -1; offset <= 1; offset += 1) {
    const windowStart = new Date(
      start.getFullYear(),
      start.getMonth(),
      start.getDate() + offset,
      startHour,
      startMinute,
    );
    const windowEnd = new Date(
      start.getFullYear(),
      start.getMonth(),
      start.getDate() + offset,
      endHour,
      endMinute,
    );
    if (windowEnd <= windowStart) windowEnd.setDate(windowEnd.getDate() + 1);
    if (start >= windowStart && end <= windowEnd) return true;
  }
  return false;
}
function makeRows(input: ScheduleInput, serving: Date): ScheduleRow[] {
  const coolingStart = plus(serving, -input.cooling);
  const bakingStart = plus(coolingStart, -input.baking);
  const preheatStart = plus(bakingStart, -input.preheat);
  const proofStart = plus(bakingStart, -input.coldProof);
  const shapeStart = plus(proofStart, -input.shaping);
  const bulkStart = plus(shapeStart, -input.bulk);
  const feedStart = plus(bulkStart, -input.starter);
  const rows: ScheduleRow[] = [];
  const add = (
    id: string,
    label: string,
    start: Date,
    end: Date,
    handsOn: boolean,
    note: string,
  ) => {
    rows.push({
      id,
      label,
      start,
      end,
      handsOn,
      note,
      conflict:
        handsOn && !isAvailable(start, end, input.homeStart, input.homeEnd),
    });
  };
  add(
    "feed",
    "Feed starter",
    feedStart,
    plus(feedStart, 10),
    true,
    "Example 10-minute feed. Use only when its observed activity matches your recipe.",
  );
  add(
    "starter",
    "Starter maturation",
    feedStart,
    bulkStart,
    false,
    "Estimated window; a ripe-starter check decides whether mixing can begin.",
  );
  add(
    "mix",
    "Mix dough",
    bulkStart,
    plus(bulkStart, input.mixing),
    true,
    "Mixing is included in bulk fermentation time.",
  );
  add(
    "bulk",
    "Bulk fermentation",
    bulkStart,
    shapeStart,
    false,
    "Estimated duration; follow the recipe’s temperature and rise cues.",
  );
  for (let fold = 1; fold <= 3; fold += 1) {
    const at = fold * 30;
    if (at >= input.mixing && at + 5 <= input.bulk) {
      add(
        `fold-${fold}`,
        `Fold ${fold}`,
        plus(bulkStart, at),
        plus(bulkStart, at + 5),
        true,
        "Illustrative 5-minute fold. Adjust to your actual recipe.",
      );
    }
  }
  add(
    "shape",
    "Shape and refrigerate",
    shapeStart,
    proofStart,
    true,
    "Only shape when the dough is ready; this clock cannot assess fermentation.",
  );
  add(
    "proof",
    "Refrigerated final proof",
    proofStart,
    bakingStart,
    false,
    "Preheating overlaps this stage. Confirm the recipe supports your cold-proof duration.",
  );
  add(
    "preheat",
    "Start preheating",
    preheatStart,
    plus(preheatStart, 5),
    true,
    "Example 5-minute setup; remaining preheat is passive.",
  );
  add(
    "preheat-window",
    "Oven preheating",
    preheatStart,
    bakingStart,
    false,
    "Use your recipe and equipment’s required preheat.",
  );
  add(
    "load",
    "Score and load",
    bakingStart,
    plus(bakingStart, Math.min(10, input.baking)),
    true,
    "Loading time is included in the bake window.",
  );
  add(
    "bake",
    "Bake",
    bakingStart,
    coolingStart,
    false,
    "Include any lid removal or oven changes from your recipe as extra attention windows.",
  );
  add(
    "unload",
    "Remove loaf",
    plus(coolingStart, -5),
    coolingStart,
    true,
    "Allow a safe, clear place for hot equipment and the cooling loaf.",
  );
  add(
    "cool",
    "Cool before slicing",
    coolingStart,
    serving,
    false,
    "Cooling is preserved; do not shorten it to catch up with the schedule.",
  );
  return rows.sort(
    (a, b) =>
      a.start.getTime() - b.start.getTime() ||
      Number(b.handsOn) - Number(a.handsOn),
  );
}
export function calculateSchedule(
  input: ScheduleInput,
  findLater = true,
): ScheduleResult {
  const serving = new Date(input.serving);
  const invalid =
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(input.serving) ||
    !Number.isFinite(serving.getTime()) ||
    !validClock(input.homeStart) ||
    !validClock(input.homeEnd);
  const durations = [
    input.cooling,
    input.baking,
    input.preheat,
    input.coldProof,
    input.shaping,
    input.bulk,
    input.mixing,
    input.starter,
  ];
  let error: string | null = null;
  if (invalid)
    error = "Enter a valid serving date, serving time and daily home window.";
  else if (durations.some((n) => !Number.isFinite(n) || n <= 0 || n > 4320))
    error =
      "Each duration must be more than 0 and no more than 4,320 minutes (72 hours).";
  else if (input.mixing > input.bulk)
    error = "Mixing must fit inside the bulk fermentation duration.";
  else if (input.baking < 10 || input.preheat < 5 || input.starter < 10)
    error =
      "Allow at least 10 minutes for baking and starter maturation, and 5 minutes for preheating.";
  else if (input.preheat > input.coldProof)
    error =
      "Preheating must fit within this template’s refrigerated final proof. Change the durations or choose a different recipe workflow.";
  if (error)
    return { rows: [], conflicts: [], serving, laterServing: null, error };
  const rows = makeRows(input, serving);
  const conflicts = rows.filter((row) => row.conflict);
  let laterServing: Date | null = null;
  if (conflicts.length && findLater) {
    // Search every 15 minutes for seven days; preserve every recipe duration.
    for (let offset = 15; offset <= 7 * 24 * 60; offset += 15) {
      const candidate = plus(serving, offset);
      if (!makeRows(input, candidate).some((row) => row.conflict)) {
        laterServing = candidate;
        break;
      }
    }
  }
  return { rows, conflicts, serving, laterServing, error: null };
}
export function formatLocalDateInput(date: Date): string {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

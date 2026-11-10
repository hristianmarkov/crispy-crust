"use client";

import { useState } from "react";
import {
  calculateSchedule,
  defaultSchedule,
  formatLocalDateInput,
  type ScheduleInput,
} from "@/lib/schedule-calculator";

const formatDate = (date: Date) =>
  new Intl.DateTimeFormat("en-GB", {
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(date);
const durationFields: {
  key: keyof Pick<
    ScheduleInput,
    | "starter"
    | "mixing"
    | "bulk"
    | "shaping"
    | "coldProof"
    | "preheat"
    | "baking"
    | "cooling"
  >;
  label: string;
}[] = [
  { key: "starter", label: "Starter maturation (minutes)" },
  { key: "mixing", label: "Mixing, within bulk (minutes)" },
  { key: "bulk", label: "Total bulk fermentation (minutes)" },
  { key: "shaping", label: "Shaping and refrigeration (minutes)" },
  { key: "coldProof", label: "Refrigerated final proof (minutes)" },
  { key: "preheat", label: "Oven preheating (minutes)" },
  { key: "baking", label: "Baking, including load/unload (minutes)" },
  { key: "cooling", label: "Cooling before serving (minutes)" },
];

export function ScheduleCalculator() {
  const [input, setInput] = useState<ScheduleInput>(defaultSchedule);
  const result = calculateSchedule(input);
  function update(key: keyof ScheduleInput, value: string | number) {
    setInput((previous) => ({ ...previous, [key]: value }));
  }
  function download() {
    const quote = (value: string) => `"${value.replaceAll('"', '""')}"`;
    const csv = [
      [
        "Stage",
        "Starts (your local time)",
        "Ends (your local time)",
        "Attention",
        "Availability",
        "Notes",
      ],
      ...result.rows.map((row) => [
        row.label,
        formatDate(row.start),
        formatDate(row.end),
        row.handsOn ? "Hands-on" : "Passive",
        row.conflict ? "Conflict" : "Fits",
        row.note,
      ]),
      [
        "Serve",
        formatDate(result.serving),
        "",
        "",
        "",
        "Illustrative plan. Fermentation follows dough readiness.",
      ],
    ]
      .map((row) => row.map(quote).join(","))
      .join("\r\n");
    const url = URL.createObjectURL(
      new Blob([csv], { type: "text/csv;charset=utf-8" }),
    );
    const link = document.createElement("a");
    link.href = url;
    link.download = "crispy-crust-sourdough-schedule.csv";
    link.click();
    URL.revokeObjectURL(url);
  }
  return (
    <div
      className="tools-calculator"
      onBlur={() => {
        if (!result.error)
          window.dispatchEvent(
            new CustomEvent("crispy:tool-completed", {
              detail: { tool: "schedule" },
            }),
          );
      }}
    >
      <div className="tools-note">
        <strong>Illustrative overnight-proof template.</strong> The initial plan
        serves bread on Sunday 15 November 2026 at 11:00. Replace the durations
        with a tested recipe you follow. Times use the clock on your device. The
        fixed 10-minute feed, 5-minute folds and 5-minute oven setup are example
        attention windows, not instructions for every recipe.
      </div>
      <div className="tools-grid">
        <label className="tools-field" htmlFor="schedule-serving">
          When do you want to serve it?
          <input
            id="schedule-serving"
            type="datetime-local"
            value={input.serving}
            onChange={(event) => update("serving", event.target.value)}
          />
        </label>
        <label className="tools-field" htmlFor="schedule-home-start">
          Home each day from
          <input
            id="schedule-home-start"
            type="time"
            value={input.homeStart}
            onChange={(event) => update("homeStart", event.target.value)}
          />
        </label>
        <label className="tools-field" htmlFor="schedule-home-end">
          Home each day until
          <input
            id="schedule-home-end"
            type="time"
            value={input.homeEnd}
            onChange={(event) => update("homeEnd", event.target.value)}
          />
        </label>
      </div>
      <p className="tools-note">
        An end time earlier than the start crosses midnight. Set both times
        equal for all-day availability. This single daily window repeats every
        day; check extra commitments against the exported plan.
      </p>
      <details>
        <summary>Adjust the recipe durations</summary>
        <div className="tools-grid">
          {durationFields.map(({ key, label }) => (
            <label
              className="tools-field"
              htmlFor={`schedule-${key}`}
              key={key}
            >
              {label}
              <input
                id={`schedule-${key}`}
                type="number"
                inputMode="numeric"
                min="1"
                max="4320"
                step="1"
                value={Number.isNaN(input[key]) ? "" : input[key]}
                onChange={(event) =>
                  update(
                    key,
                    event.target.value === ""
                      ? NaN
                      : Number(event.target.value),
                  )
                }
              />
            </label>
          ))}
        </div>
      </details>
      {result.error ? (
        <p className="tools-error" role="alert">
          {result.error}
        </p>
      ) : (
        <>
          <div className="tools-result" role="status" aria-live="polite">
            <h2>
              {result.conflicts.length
                ? `${result.conflicts.length} hands-on ${result.conflicts.length === 1 ? "step conflicts" : "steps conflict"} with your availability`
                : "The example attention windows fit"}
            </h2>
            <p>
              Serve {formatDate(result.serving)}. Cooling begins{" "}
              {formatDate(result.rows.find((row) => row.id === "cool")!.start)}.
            </p>
            {result.conflicts.length > 0 && (
              <p>
                {result.conflicts.map((row) => row.label).join(", ")}{" "}
                {result.conflicts.length === 1 ? "falls" : "fall"} outside your
                home window. Move the serving time or choose a recipe designed
                for your availability.
              </p>
            )}
            {result.laterServing ? (
              <p>
                A later plan fits at{" "}
                <strong>{formatDate(result.laterServing)}</strong> with the same
                durations.{" "}
                <button
                  className="tools-button"
                  type="button"
                  onClick={() =>
                    update(
                      "serving",
                      formatLocalDateInput(result.laterServing!),
                    )
                  }
                >
                  Use this later serving time
                </button>
              </p>
            ) : result.conflicts.length > 0 ? (
              <p>
                No fit was found in the next seven days when checked at
                15-minute intervals. Widen your availability or choose a
                different tested recipe. A timing change is not a substitute for
                dough readiness.
              </p>
            ) : null}
          </div>
          <div className="tools-table-wrap">
            <table className="tools-table">
              <caption>
                Your backwards schedule — passive stages may overlap attention
                windows
              </caption>
              <thead>
                <tr>
                  <th scope="col">Stage</th>
                  <th scope="col">Starts</th>
                  <th scope="col">Ends</th>
                  <th scope="col">Attention</th>
                  <th scope="col">Check</th>
                </tr>
              </thead>
              <tbody>
                {result.rows.map((row) => (
                  <tr key={row.id}>
                    <th scope="row">
                      {row.label}
                      <small>{row.note}</small>
                    </th>
                    <td>{formatDate(row.start)}</td>
                    <td>{formatDate(row.end)}</td>
                    <td>{row.handsOn ? "Hands-on" : "Passive"}</td>
                    <td>
                      {row.conflict
                        ? "Outside home window"
                        : row.handsOn
                          ? "Fits home window"
                          : "Check progress"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="tools-actions">
            <button className="tools-button" type="button" onClick={download}>
              Download schedule CSV
            </button>
            <button
              className="tools-button"
              type="button"
              onClick={() => window.print()}
            >
              Print schedule
            </button>
            <button
              className="tools-button"
              type="button"
              onClick={() => setInput(defaultSchedule)}
            >
              Reset example
            </button>
          </div>
        </>
      )}
      <noscript>
        JavaScript is needed to change this example. Work backwards from
        serving: subtract cooling, baking, refrigerated proof, shaping and bulk.
        Start preheating before loading while the dough remains refrigerated.
        Mixing belongs inside bulk time. Compare every hands-on step with your
        home window.
      </noscript>
    </div>
  );
}

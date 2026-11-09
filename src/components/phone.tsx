import { Bell, BookOpen, Check, Clock3, Home, Wheat } from "lucide-react";
import { LogoMark } from "./brand";
export type Screen = "today" | "planner" | "starter" | "journal";
const contents = {
  today: {
    eyebrow: "FRIDAY · YOUR EVENING BAKE",
    title: "A loaf.\nA plan that fits.",
    subtitle: "Country sourdough · strong white flour",
    label: "YOUR NEXT STEP",
    task: "Mix your dough",
    detail: "18:00 · 15 minutes hands-on",
    note: "You’re available 18:00–21:30",
    rows: [
      ["18:30", "Stretch & fold", "5 min hands-on"],
      ["EVENING", "Check rise & shape", "Follow your dough"],
      ["OVERNIGHT", "Cold proof", "In the fridge"],
    ],
  },
  planner: {
    eyebrow: "BAKE AROUND YOUR DAY",
    title: "Your time.\nYour timeline.",
    subtitle: "Country sourdough · overnight cold proof",
    label: "YOUR AVAILABLE HOURS",
    task: "18:00 – 21:30",
    detail: "Friday evening + Saturday morning",
    note: "Hands-on steps in your free time",
    rows: [
      ["FRI", "Mix, fold & shape", "Evening availability"],
      ["NIGHT", "Cold proof", "No hands-on time"],
      ["SAT", "Bake & cool", "Morning availability"],
    ],
  },
  starter: {
    eyebrow: "YOUR STARTER · MATILDA",
    title: "Know when\nit’s ready.",
    subtitle: "Feeding history, rise and temperature",
    label: "LATEST CHECK-IN",
    task: "Nearly doubled",
    detail: "Fed 4 hours ago · kitchen 23°C",
    note: "Watch the rise, not just the timer",
    rows: [
      ["08:00", "Feed recorded", "White + wholemeal flour"],
      ["10:00", "Rise check", "Bubbles appearing"],
      ["12:00", "Check the peak", "Record what you see"],
    ],
  },
  journal: {
    eyebrow: "YOUR PERSONAL BAKE JOURNAL",
    title: "Keep what\nworked.",
    subtitle: "The recipe, the timing, the result",
    label: "SAVED BAKE",
    task: "The Sunday loaf",
    detail: "Country sourdough · 75% hydration",
    note: "Same recipe. Your observations.",
    rows: [
      ["FLOUR", "White + wholemeal", "Your exact blend"],
      ["PROOF", "12 hours cold", "Actual time recorded"],
      ["NEXT", "Repeat with notes", "Try a darker crust"],
    ],
  },
};
export function Phone({
  screen = "today",
  className = "",
}: {
  screen?: Screen;
  className?: string;
}) {
  const c = contents[screen];
  return (
    <div
      className={`phone ${className}`}
      role="img"
      aria-label={`Crispy Crust ${screen} app design preview`}
    >
      <div className="phone-camera" />
      <div className="phone-screen">
        <div className="mock-status">
          <span>9:41</span>
          <span>▮▮▮ ▰</span>
        </div>
        <div className="mock-brand">
          <span>
            <LogoMark /> Crispy Crust
          </span>
          <Bell size={16} />
        </div>
        <div className="mock-intro">
          <span>{c.eyebrow}</span>
          <h3>
            {c.title.split("\n").map((line, i) => (
              <span key={line}>
                {i > 0 && <br />}
                {line}
              </span>
            ))}
          </h3>
          <p>{c.subtitle}</p>
        </div>
        <div className="mock-task">
          <span>{c.label}</span>
          <h4>{c.task}</h4>
          <p>{c.detail}</p>
          <div>
            <Check size={14} />
            {c.note}
          </div>
        </div>
        <div className="mock-timeline-title">
          {screen === "journal" ? "THE DETAILS" : "THE PLAN AT A GLANCE"}
        </div>
        <div className="mock-rows">
          {c.rows.map(([time, title, sub]) => (
            <div key={title}>
              <span>{time}</span>
              <div>
                <strong>{title}</strong>
                <p>{sub}</p>
              </div>
            </div>
          ))}
        </div>
        <div className="mock-footer">
          {[Home, Wheat, Clock3, BookOpen].map((Icon, i) => (
            <span
              key={i}
              className={
                i === ["today", "starter", "planner", "journal"].indexOf(screen)
                  ? "active"
                  : ""
              }
            >
              <Icon size={18} />
              {["Today", "Starter", "Plan", "Journal"][i]}
            </span>
          ))}
        </div>
        <div className="phone-home" />
      </div>
    </div>
  );
}

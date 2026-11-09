import {
  ArrowUpRight,
  Bell,
  BookOpen,
  Check,
  ChevronLeft,
  ChevronRight,
  Clock3,
  Flame,
  Home,
  Leaf,
  Plus,
  Sparkles,
  Wheat,
} from "lucide-react";
import { LogoMark } from "./brand";
export type Screen = "today" | "planner" | "starter" | "journal";
export function Phone({
  screen = "today",
  className = "",
}: {
  screen?: Screen;
  className?: string;
}) {
  return (
    <div
      className={`phone ${className}`}
      aria-label={`Crumb & Clock ${screen} app concept preview`}
      role="img"
    >
      <div className="phone-camera" />
      <div className="phone-screen">
        <div className="phone-status">
          <span>9:41</span>
          <span className="phone-status-icons">
            ▮▮▮ <span>◔</span> ▰
          </span>
        </div>
        <div className="app-top">
          <div className="app-mini-brand">
            <LogoMark /> crumb & clock
          </div>
          <Bell size={14} />
        </div>
        {screen === "today" && (
          <>
            <div className="app-greeting">SUNDAY, THE SLOW WAY</div>
            <h3>
              A good day
              <br />
              for good bread.
            </h3>
            <div className="app-weather">
              <span className="sun-icon">☀</span> Your kitchen is a cosy 23°C
            </div>
            <div className="app-main-card">
              <div className="app-card-top">
                <span>YOUR WEEKEND LOAF</span>
                <span className="live-dot">LIVE</span>
              </div>
              <h4>
                A little fold.
                <br />A little patience.
              </h4>
              <p>
                Your dough is ready for its next
                <br />
                stretch & fold.
              </p>
              <div className="fold-illustration">
                <svg viewBox="0 0 160 75" fill="none">
                  <ellipse cx="80" cy="46" rx="55" ry="23" fill="#d6bd85" />
                  <path
                    d="M38 45c14-27 32-28 49-12 12-17 31-9 34 12-23 12-50 15-83 0Z"
                    fill="#ebd6a8"
                  />
                  <path
                    d="M59 34c11 1 24 6 31 14M75 26c0 13 11 19 20 20"
                    stroke="#b69863"
                    strokeWidth="1.7"
                    strokeLinecap="round"
                  />
                  <path
                    d="M42 16c-4-6-1-11 7-11M115 14c6-5 13-2 13 4"
                    stroke="#65734b"
                    strokeWidth="1.5"
                    strokeLinecap="round"
                  />
                </svg>
              </div>
              <div className="app-do-button">
                Let’s do the fold <ArrowUpRight size={13} />
              </div>
              <div className="app-time-note">
                <Clock3 size={10} /> About 2 minutes. Then, back to your day.
              </div>
            </div>
            <div className="app-starter-card">
              <span className="jar-icon">♧</span>
              <div>
                <strong>Matilda’s looking lively</strong>
                <p>Your starter is near its peak.</p>
              </div>
              <ChevronRight size={13} />
            </div>
            <div className="app-next">
              <span>UP NEXT</span>
              <div>
                <span className="app-timeline-dot" />
                <strong>Let the dough rest</strong>
                <span>10:30</span>
              </div>
            </div>
          </>
        )}
        {screen === "planner" && (
          <>
            <div className="app-back">
              <ChevronLeft size={13} /> YOUR WEEKEND BAKE
            </div>
            <h3>
              Life first.
              <br />
              Loaf second.
            </h3>
            <p className="app-subtitle">Bread on the table. Right on time.</p>
            <div className="app-plan-target">
              <span>READY TO SLICE</span>
              <strong>
                Sunday, 11:00 <span>AM</span>
              </strong>
              <span className="app-green-note">
                <Check size={11} /> Fits around your plans
              </span>
            </div>
            <div className="app-schedule">
              {[
                ["SAT", "18:00", "Feed your starter", "5 min hands-on"],
                ["", "21:00", "Mix & let it rest", "15 min hands-on"],
                ["SUN", "07:30", "Shape your loaf", "10 min hands-on"],
                ["", "09:15", "Into the oven", "45 min bake"],
                ["", "10:00", "A little cooling time", "1 hour, all yours"],
                ["", "11:00", "Slice. Butter. Enjoy.", "The best part."],
              ].map(([day, time, title, sub], i) => (
                <div
                  className={`schedule-item ${i === 5 ? "schedule-final" : ""}`}
                  key={title}
                >
                  <div className="schedule-time">
                    <span>{day}</span>
                    {time}
                  </div>
                  <div className="schedule-line">
                    <i />
                  </div>
                  <div>
                    <strong>{title}</strong>
                    <p>{sub}</p>
                  </div>
                </div>
              ))}
            </div>
            <div className="app-bottom-note">
              <Sparkles size={12} /> Real life happens. Your plan can adapt.
            </div>
          </>
        )}
        {screen === "starter" && (
          <>
            <div className="app-back">
              <ChevronLeft size={13} /> YOUR STARTERS
            </div>
            <div className="app-starter-title">
              <h3>Meet Matilda.</h3>
              <span>✳</span>
            </div>
            <p className="app-subtitle">A small jar. A living little thing.</p>
            <div className="starter-visual">
              <div className="starter-jar">
                <div className="jar-lid" />
                <div className="jar-fill">
                  <i />
                  <i />
                  <i />
                  <i />
                  <i />
                  <i />
                </div>
                <div className="jar-mark" />
              </div>
              <div className="starter-peak">
                LOOKING LIVELY <ArrowUpRight size={12} />
              </div>
            </div>
            <div className="starter-metrics">
              <div>
                <span>LAST FED</span>
                <strong>4 hours ago</strong>
              </div>
              <div>
                <span>RISE</span>
                <strong>Nearly 2×</strong>
              </div>
            </div>
            <div className="app-chart">
              <div className="chart-title">
                A little rise report <span>TODAY</span>
              </div>
              <svg viewBox="0 0 230 80">
                <path
                  d="M0 60H230M0 30H230"
                  stroke="#e0e3d7"
                  strokeDasharray="3 3"
                />
                <path
                  d="M4 70C40 69 47 63 68 59S92 46 110 34 148 14 169 12 202 18 225 28"
                  stroke="#627045"
                  strokeWidth="3"
                  fill="none"
                />
                <circle cx="169" cy="12" r="4" fill="#627045" />
              </svg>
              <div className="chart-labels">
                <span>8 AM</span>
                <span>10 AM</span>
                <span>12 PM</span>
              </div>
            </div>
            <div className="app-do-button">
              Log a little check-in <Plus size={13} />
            </div>
          </>
        )}
        {screen === "journal" && (
          <>
            <div className="app-greeting">YOUR BAKING STORY</div>
            <h3>
              Keep the
              <br />
              keepers.
            </h3>
            <p className="app-subtitle">Every loaf has a little lesson.</p>
            <div className="app-journal-photo">
              <img src="/images/sourdough.webp" alt="" />
            </div>
            <div className="app-journal-info">
              <span>THE ONE TO BAKE AGAIN</span>
              <h4>The Sunday regular</h4>
              <p>Country sourdough · 75% hydration</p>
              <div className="app-stars">✦ ✦ ✦ ✦ ✦</div>
              <blockquote>
                “That crust. That crumb. A longer cold proof next time.”
              </blockquote>
              <div className="app-bake-tags">
                <span>24°C kitchen</span>
                <span>12h cold proof</span>
              </div>
            </div>
            <div className="app-do-button">
              Bake this one again <ArrowUpRight size={13} />
            </div>
          </>
        )}
        <div className="app-tabs">
          {[
            [Home, "Today"],
            [Wheat, "Starters"],
            [Clock3, "Bake"],
            [BookOpen, "Journal"],
          ].map(([Icon, label], i) => {
            const C = Icon as typeof Home;
            return (
              <div
                key={i}
                className={
                  (screen === "today" && i === 0) ||
                  (screen === "starter" && i === 1) ||
                  (screen === "planner" && i === 2) ||
                  (screen === "journal" && i === 3)
                    ? "active"
                    : ""
                }
              >
                <C size={16} />
                <span>{label as string}</span>
              </div>
            );
          })}
        </div>
        <div className="phone-home" />
      </div>
    </div>
  );
}

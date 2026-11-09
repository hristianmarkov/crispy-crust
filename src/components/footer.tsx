import Link from "next/link";
import { ArrowUpRight, Heart } from "lucide-react";
import { Brand, LogoMark } from "./brand";
import { WaitlistButton } from "./site-interactions";
export function LaunchSection() {
  return (
    <section className="launch-section" id="early-access">
      <div className="launch-sprig">✳</div>
      <span className="eyebrow">LESS OVERTHINKING. MORE OVEN SPRING.</span>
      <h2>
        Your next chapter
        <br />
        smells like <em>good bread.</em>
      </h2>
      <p>
        Something thoughtful is rising.
        <br />
        Be the first to know when it’s ready.
      </p>
      <WaitlistButton className="button button-light">
        Join the early birds <ArrowUpRight size={17} />
      </WaitlistButton>
      <div className="launch-meta">
        <span className="tiny-dot" /> In the making, for iOS & Android
      </div>
    </section>
  );
}
export function Footer() {
  return (
    <footer className="footer">
      <div className="footer-top">
        <div>
          <Brand />
          <p>Good bread. A little less guesswork.</p>
        </div>
        <div className="footer-links">
          <Link href="/#how-it-works">How it works</Link>
          <Link href="/#features">The good stuff</Link>
          <Link href="/journal">The Baker’s Journal</Link>
          <Link href="/#faq">FAQs</Link>
        </div>
      </div>
      <div className="footer-bottom">
        <span>© {new Date().getFullYear()} Crumb & Clock</span>
        <span className="footer-made">
          Made for slow mornings & impatient bakers.
        </span>
        <Link href="/privacy">Privacy, please</Link>
      </div>
    </footer>
  );
}

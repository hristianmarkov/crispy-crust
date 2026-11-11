import Link from "next/link";
import { Brand } from "./brand";
export function LaunchSection() {
  return (
    <section className="launch-section" id="app-status">
      <div className="launch-sprig">✳</div>
      <span className="eyebrow">LESS OVERTHINKING. MORE OVEN SPRING.</span>
      <h2>
        Your next chapter
        <br />
        smells like <em>good bread.</em>
      </h2>
      <p>
        Good bread, on your time.
        <br />
        The iOS and Android app is in development.
      </p>
      <p className="launch-status">Not publicly released yet. A release date and pricing have not been announced. Store links will appear here when the app is available.</p>
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
          <Link href="/tools">Baking explainers</Link>
          <Link href="/about">About & editorial policy</Link>
          <Link href="/#faq">FAQs</Link>
        </div>
      </div>
      <div className="footer-bottom">
        <span>© {new Date().getFullYear()} Crispy Crust</span>
        <span className="footer-made">
          Made for slow mornings & impatient bakers.
        </span>
        <Link href="/privacy">Privacy, please</Link>
      </div>
    </footer>
  );
}

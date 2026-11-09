import Link from "next/link";
import { ArrowRight } from "lucide-react";
export default function NotFound() {
  return (
    <main id="main" className="not-found">
      <span className="eyebrow">THIS ONE DIDN’T QUITE RISE</span>
      <h1>A little off the recipe.</h1>
      <p>
        We couldn’t find that page. There’s still plenty of good stuff back
        home.
      </p>
      <Link href="/" className="button">
        Back to the kitchen <ArrowRight size={16} />
      </Link>
    </main>
  );
}

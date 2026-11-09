import type { Metadata } from "next";
import { RemoveEmail } from "@/components/remove-email";
export const metadata: Metadata = {
  title: "Privacy, please",
  description:
    "How the Crumb & Clock early-access website handles your email address and platform preference.",
  alternates: { canonical: "/privacy" },
};
export default function Privacy() {
  return (
    <main id="main" className="article-page privacy-page">
      <span className="eyebrow">YOUR DETAILS BELONG TO YOU</span>
      <h1>Privacy, please.</h1>
      <p>
        This notice covers the early-access website for Crumb & Clock. The
        mobile app is in development; its own privacy information will be
        provided before launch.
      </p>
      <h2>What the early-access form collects</h2>
      <p>
        If you join the list, we store your email address, preferred phone
        platform, the time of your signup, and a record that you asked for
        launch updates. We use these details to manage launch interest and send
        launch news when it’s available.
      </p>
      <h2>A small amount of data, for a clear reason</h2>
      <p>
        Signing up is optional. Your details are stored privately in a Supabase database,
        not published or sold. The form does not add your address to a
        third-party email service. The site does not set analytics or
        advertising cookies. Hosting infrastructure may process technical
        request logs to operate and secure the website. A daily keyed hash of your network address is used for short-lived signup rate limits; the raw address is not stored in the waitlist database.
      </p>
      <h2>Changed your mind?</h2>
      <p>
        Use this form to remove an email address from the early-access list. For
        privacy, the response is the same whether an address was on the list or
        not.
      </p>
      <RemoveEmail />
      <h2>About the app previews</h2>
      <p>
        The example starter, bake details, and journal notes shown on this site
        are illustrative design concepts. They are not real user records or
        testimonials. App features, platform availability, and screens may
        change before release.
      </p>
    </main>
  );
}

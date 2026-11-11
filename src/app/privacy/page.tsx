import type { Metadata } from "next";
export const metadata: Metadata = {
  title: "Privacy, please",
  description: "Privacy information for the Crispy Crust marketing website and its retired early-access form.",
  alternates: { canonical: "/privacy" },
  openGraph: { title: "Crispy Crust Privacy", description: "Marketing website privacy and historical early-access data.", url: "/privacy", images: ["/images/social-card.jpg"] },
  twitter: { card: "summary_large_image", title: "Crispy Crust Privacy", description: "Marketing website privacy and historical early-access data." },
};
export default function Privacy() {
  return <main id="main" className="article-page privacy-page">
    <span className="eyebrow">YOUR DETAILS BELONG TO YOU</span>
    <h1>Privacy, please.</h1>
    <p>This notice covers the Crispy Crust marketing website. The mobile app is in development; its own privacy information will be provided before launch.</p>
    <h2>A marketing website</h2>
    <p>This website provides product information, illustrative previews and baking articles. It does not create app accounts, save baking records, run a planner, process purchases or accept new early-access signups. Worked examples are static educational content.</p>
    <h2>Historical early-access information</h2>
    <p>An earlier version offered an optional launch-interest form that collected an email address, phone-platform preference and signup time. That form and its website submission and removal endpoints have been retired. Retiring the form does not itself delete previously collected records or unsubscribe an address.</p>
    <p>Historical records remain subject to the purpose and privacy commitments under which they were collected. They must not be converted into app accounts or treated as consent to app analytics. This website does not claim that all historical records have been deleted.</p>
    <h2>Requests about historical records</h2>
    <p>The former automated removal form is no longer available. Until a verified privacy/support contact is published, this page cannot accept or confirm an individual removal request. No unverified email address or false removal confirmation is presented here.</p>
    <h2>Website analytics and infrastructure</h2>
    <p>Vercel Web Analytics may count page visits, guide views and static printable downloads when enabled for the site. Events contain page paths and controlled content identifiers, not email addresses or baking entries. Query strings are stripped, and the integration respects Do Not Track and Global Privacy Control. It does not use advertising cookies. Hosting infrastructure may process technical request logs to operate and secure the website. See <a href="https://vercel.com/docs/analytics/privacy-policy">Vercel’s analytics privacy information</a>.</p>
    <h2>About the app previews</h2>
    <p>Example starters, bake details and journal notes are illustrative design concepts, not real user records, testimonials or validated recipe outcomes. App features, platform availability and screens may change before release.</p>
  </main>;
}

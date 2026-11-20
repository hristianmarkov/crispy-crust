import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

const titles: Record<string, string> = {
  privacy: "Mobile app privacy", terms: "Mobile app terms",
  support: "Crispy Crust support", "delete-account": "Delete your app account",
};
const email = "hello@leymora.com";

export function generateStaticParams() {
  return Object.keys(titles).map((document) => ({ document }));
}
export async function generateMetadata({ params }: { params: Promise<{ document: string }> }): Promise<Metadata> {
  const { document } = await params;
  return { title: titles[document] ?? "Crispy Crust", alternates: { canonical: `/mobile/${document}` },
  };
}

function Contact() {
  return <a href={`mailto:${email}`}>{email}</a>;
}

export default async function MobileDocument({ params }: { params: Promise<{ document: string }> }) {
  const { document } = await params;
  if (!Object.hasOwn(titles, document)) notFound();
  return <main id="main" className="article-page privacy-page">
    <span className="eyebrow">CRISPY CRUST BAKING</span>
    <h1>{titles[document]}</h1>
    <p>Updated 18 November 2026. These pages cover the Crispy Crust Baking mobile app, operated by Hristiyan Markov.</p>
    {document === "privacy" && <>
      <h2>Your kitchen, on your device</h2>
      <p>You can use the local baking tools without an account. Starter records, baking plans, notes and photos you save locally remain on your device unless you choose a connected feature, sharing or an export. Your device or backup provider may separately back up app files. Uninstalling the app can remove local records; export anything you want to keep first.</p>
      <h2>Accounts and connected services</h2>
      <p>When you sign in, Supabase processes your account identifier, email address and authentication information. Google or Apple handles the sign-in you select. We do not receive your Google or Apple password. If you enable cloud synchronisation, selected kitchen records and changes are stored with your account. Photos you choose to upload are held in private storage and accessed through authorised requests.</p>
      <h2>The baking coach</h2>
      <p>Before sending a question, the app asks you to review the text, recipe name and current step being shared. Supabase processes the request and sends this selected context to OpenAI to generate guidance. Do not include sensitive personal information in your question. The coach request and answer are saved with your account until deletion. We request responses with provider storage disabled; OpenAI may retain operational or abuse-monitoring data under its own applicable policies. Coach output can be inaccurate and is not a food-safety assessment.</p>
      <h2>Subscriptions</h2>
      <p>Apple or Google processes your payment. RevenueCat processes purchase receipts, store transaction and subscription status, and an app user identifier so that we can verify access, restore purchases and handle renewals or refunds. We do not receive your full payment-card details. Subscription data is used to provide the service and meet applicable accounting or legal obligations.</p>
      <h2>Optional analytics</h2>
      <p>If you turn on analytics, PostHog receives controlled events such as opening the app, a main tab or subscription settings, together with technical app and device metadata and a pseudonymous installation identifier. The app does not send your questions, starter names, baking notes, photos or email in these events. Session replay, advertising tracking and person profiles are disabled. You can turn analytics off in the app. Hosting and service providers also process technical request logs to operate and protect their services.</p>
      <h2>Why we process information</h2>
      <p>Account, cloud and purchase information is processed to provide the services you request. Optional coach context and analytics are sent following your choices in the app. Operational security and fraud prevention support our legitimate interest in keeping the service reliable; legally required records are retained to meet those obligations. We do not sell your personal information or use it for cross-app advertising.</p>
      <h2>Providers, transfers and retention</h2>
      <p>Our providers include Supabase, OpenAI, RevenueCat, PostHog and the store or sign-in provider you use. They may process information outside the United Kingdom or your country, subject to their contractual safeguards and applicable transfer arrangements. App records are retained while your account exists or until you remove them. Deletion removes app-owned data and the authentication account after required ownership checks; provider backups, security logs and legally required purchase records may follow separate retention schedules. Local copies and exports on your devices are under your control.</p>
      <h2>Your choices and requests</h2>
      <p>You can review permissions, export local records, withdraw optional feature consent and request account deletion in the app. See <Link href="/mobile/delete-account">account deletion instructions</Link>. For access, correction, deletion, portability or an objection to processing, contact <Contact />. We verify identity before disclosing or deleting account information. You can also complain to the UK Information Commissioner’s Office or your local data-protection authority.</p>
      <p>The app is intended for general home baking and is not directed at children. We will update this notice when our processing changes.</p>
    </>}
    {document === "terms" && <>
      <h2>Using Crispy Crust</h2>
      <p>Crispy Crust helps organise home baking. You are responsible for your ingredients, allergies, equipment and food handling. Fermentation forecasts and recipe schedules are estimates: check the dough and follow equipment instructions. Experimental recipes and generated recipe illustrations do not establish a kitchen-tested result. AI guidance can be wrong and cannot determine whether food is safe to eat.</p>
      <h2>Free features and Crispy Crust Pro</h2>
      <p>Local starter tracking, the current recipe catalogue, bake planning, calculators, timers and your journal are available without a subscription. A signed-in free account includes three baking-coach questions per calendar month. Pro includes 60 per calendar month. A submitted question counts once; follow-up questions count separately. Allowances reset at 00:00 UTC on the first day of the month, do not roll over and are shared across your account’s devices. A limit of 20 requests in a rolling 24-hour period also applies. Coach access needs internet and available provider services.</p>
      <p>Monthly and annual subscriptions provide the same Pro access. The store shows your local price, billing period and applicable taxes before confirmation. Payment is charged through your Apple or Google account. Subscriptions renew automatically unless cancelled through the store. Cancel before the store’s renewal deadline, generally at least 24 hours before renewal, to avoid the next charge. You can manage or cancel in the store’s subscription settings. Refund requests follow the store’s rules and your applicable consumer rights. Deleting your app account does not cancel a subscription.</p>
      <h2>Your records and account</h2>
      <p>Keep a backup of records that matter to you. You retain rights to content you create and give us permission to process it only as needed for the features you request. Only upload content you have permission to use. Keep your account secure and do not abuse connected services, attempt unauthorised access or submit unlawful content.</p>
      <h2>Availability and changes</h2>
      <p>Connected features depend on third-party services and may be interrupted. We may make reasonable changes to improve or maintain the app and will give any notice required by law for material subscription changes. Nothing here limits statutory consumer rights or liability that cannot lawfully be excluded. These terms are governed by the law of England and Wales, subject to mandatory protections and jurisdiction rights in your place of residence.</p>
      <p>Questions about the app or these terms: <Contact />.</p>
    </>}
    {document === "support" && <>
      <h2>Get help with the app</h2>
      <p>Contact <Contact />. Include your phone model, app version, what you were trying to do and the error shown. Do not send passwords, authentication codes, payment-card details or private API keys. Attach screenshots only if you are comfortable sharing their contents.</p>
      <h2>Purchases and restores</h2>
      <p>Sign in to the app account you used when subscribing, open Features → Connected services → Subscriptions and purchases, and choose Restore purchases. Make sure the device uses the store account that bought the subscription. Manage cancellations in Apple or Google’s subscription settings. The app cannot cancel a store subscription by deleting an account.</p>
      <h2>Baking plans and timers</h2>
      <p>A plan is a guide, and dough may be ready earlier or later. Review the recipe’s dough cues before continuing. For reminder issues, check the app’s notification permission and your device’s battery restrictions. Save a local export before reinstalling or clearing app storage.</p>
      <p>For data requests, see <Link href="/mobile/delete-account">account deletion</Link> and <Link href="/mobile/privacy">mobile app privacy</Link>.</p>
    </>}
    {document === "delete-account" && <>
      <h2>Delete from the app</h2>
      <p>Open Features → Connected services, find the account and privacy controls, and choose account deletion. You will be asked to sign in again recently and confirm the request. If you own a shared kitchen, transfer ownership first. Deletion is processed in the background; a queued request is not confirmation that every deletion has finished.</p>
      <h2>Request deletion without the app</h2>
      <p>Email <Contact /> from the address associated with your app account, with the subject “Crispy Crust account deletion”. Tell us that you want the Crispy Crust Baking account and its app-owned data deleted. We will verify ownership before processing the request. Never send your password or sign-in code.</p>
      <h2>What deletion covers</h2>
      <p>The deletion process removes the authentication account and app-owned cloud records, jobs and uploaded media, subject to shared-kitchen ownership checks. Store transaction records, legally required records, provider security logs and backups may have separate retention requirements. Delete local records or uninstall the app separately, and remove any exports or device backups you no longer want. Optional analytics uses a separate installation identifier and is not linked to the sign-in account.</p>
      <h2>Cancel your subscription separately</h2>
      <p>Account deletion does not cancel billing. Cancel in the Apple App Store or Google Play subscription settings before deleting your account if you no longer want Pro.</p>
    </>}
    <p><Link href="/mobile/support">Support</Link> · <Link href="/mobile/privacy">Privacy</Link> · <Link href="/mobile/terms">Terms</Link> · <Link href="/mobile/delete-account">Account deletion</Link></p>
  </main>;
}

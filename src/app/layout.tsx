import type { Metadata, Viewport } from "next";
import "@fontsource/dm-sans/400.css";
import "@fontsource/dm-sans/500.css";
import "@fontsource/dm-sans/600.css";
import "@fontsource/dm-sans/700.css";
import "@fontsource/dm-serif-display/400.css";
import "@fontsource/dm-serif-display/400-italic.css";
import "./globals.css";
import { Header } from "@/components/header";
import { Footer } from "@/components/footer";
import { WaitlistDialog } from "@/components/site-interactions";
import { siteUrl, isPublicSite } from "@/lib/site";
export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: "Crispy Crust — Sourdough, on your time.",
    template: "%s | Crispy Crust",
  },
  description:
    "Crispy Crust brings flour-specific sourdough and focaccia recipes, bake plans around your available hours, starter care and a personal bake journal.",
  applicationName: "Crispy Crust",
  openGraph: {
    type: "website",
    locale: "en_GB",
    siteName: "Crispy Crust",
    title: "Good bread. On your time.",
    description:
      "Your sourdough starter, your baking rhythm, your best loaf yet. A thoughtful mobile baking companion is rising.",
    images: [
      {
        url: "/images/social-card.jpg",
        width: 1200,
        height: 630,
        alt: "Crispy Crust — Good bread. On your time.",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Crispy Crust — Good bread. On your time.",
    description: "A calmer kind of sourdough baking is on its way.",
  },
  robots: { index: isPublicSite, follow: true },
  icons: { icon: "/icon.svg", apple: "/icon.svg" },
};
export const viewport: Viewport = { themeColor: "#f8f7f0" };
export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <a className="skip-link" href="#main">
          Skip to content
        </a>
        <Header />
        {children}
        <Footer />
        <WaitlistDialog />
      </body>
    </html>
  );
}

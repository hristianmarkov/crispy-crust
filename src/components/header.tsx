"use client";
import { useState } from "react";
import Link from "next/link";
import { ArrowUpRight, Menu, X } from "lucide-react";
import { Brand } from "./brand";
export function Header() {
  const [open, setOpen] = useState(false);
  const close = () => setOpen(false);
  return (
    <header className="header">
      <div className="nav-shell">
        <Brand />
        <nav
          className={open ? "nav-links is-open" : "nav-links"}
          aria-label="Main navigation"
        >
          <Link href="/#how-it-works" onClick={close}>
            How it works
          </Link>
          <Link href="/#features" onClick={close}>
            The good stuff
          </Link>
          <Link href="/journal" onClick={close}>
            The Baker’s Journal <span className="nav-new">READ</span>
          </Link>
          <Link href="/tools" onClick={close}>
            Baking explainers
          </Link>
          <Link href="/#app-status" className="button button-small nav-mobile-cta" onClick={close}>
            App in development <ArrowUpRight size={15} />
          </Link>
        </nav>
        <Link href="/#app-status" className="button button-small desktop-cta">
          App in development <ArrowUpRight size={15} />
        </Link>
        <button
          className="menu-button"
          aria-label={open ? "Close navigation" : "Open navigation"}
          aria-expanded={open}
          onClick={() => setOpen(!open)}
        >
          {open ? <X /> : <Menu />}
        </button>
      </div>
    </header>
  );
}

import Link from "next/link";

export function LogoMark({ className = "" }: { className?: string }) {
  return (
    <svg
      className={className}
      width="44"
      height="44"
      viewBox="0 0 48 48"
      fill="none"
      aria-hidden="true"
    >
      <path
        d="M8 30C8 18.4 14.7 8 25 8c10.1 0 16 8.4 16 19.5C41 36 34.3 41 24 41S8 37.2 8 30Z"
        stroke="currentColor"
        strokeWidth="2.5"
      />
      <path
        d="m24 16-3.5 10.5 10 3M15 17l4-4M33 15l3 4M13 29l-1 3"
        stroke="currentColor"
        strokeWidth="2.5"
        strokeLinecap="round"
      />
      <circle cx="20.5" cy="26.5" r="1.8" fill="currentColor" />
    </svg>
  );
}
export function Brand({ light = false }: { light?: boolean }) {
  return (
    <Link
      href="/"
      className={`brand ${light ? "brand-light" : ""}`}
      aria-label="Crumb and Clock home"
    >
      <LogoMark />
      <span>
        crumb <span className="brand-amp">&</span> clock
        <span className="brand-dot">✳</span>
      </span>
    </Link>
  );
}

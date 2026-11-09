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
        d="M7 29C7 16 15 8 25 8s17 9 17 21c0 8-7 12-18 12S7 37 7 29Z"
        fill="currentColor"
      />
      <path
        d="m18 17-5 9m14-11-7 14m15-10-5 10"
        stroke="#f8f7f0"
        strokeWidth="2.8"
        strokeLinecap="round"
      />
      <path
        d="M12 35c7 3 17 3 24-1"
        stroke="#f8f7f0"
        strokeWidth="1.5"
        strokeLinecap="round"
      />
    </svg>
  );
}
export function Brand({ light = false }: { light?: boolean }) {
  return (
    <Link
      href="/"
      className={`brand ${light ? "brand-light" : ""}`}
      aria-label="Crispy Crust home"
    >
      <LogoMark />
      <span>
        Crispy <em>Crust</em>
      </span>
    </Link>
  );
}

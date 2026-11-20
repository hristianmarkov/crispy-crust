import Link from "next/link";
export function LogoMark({ className = "" }: { className?: string }) {
  return <svg className={className} width="44" height="44" viewBox="0 0 128 128" fill="currentColor" aria-hidden="true">
    <path fillRule="evenodd" d="M104 29C94 12 76 6 56 10C27 16 11 42 14 70C17 99 41 119 70 118C87 117 101 108 109 94C114 85 108 80 100 84C87 90 74 84 70 73C64 56 77 40 95 41C106 42 111 38 104 29Z M29 69C42 46 62 30 88 23C65 35 47 51 29 69Z" />
  </svg>;
}
export function Brand({ light = false }: { light?: boolean }) {
  return <Link href="/" className={`brand ${light ? "brand-light" : ""}`} aria-label="Crispy Crust home">
    <LogoMark /><span>Crispy <em>Crust</em></span>
  </Link>;
}

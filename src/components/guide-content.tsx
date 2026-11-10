import Link from "next/link";
import { Fragment, type ReactNode } from "react";

export function InlineText({ text, sourceCount = 0 }: { text: string; sourceCount?: number }) {
  text = text.replace(/\[\[(\d+)\]\]\(([^)]+)\)/g, "[$1]($2)");
  const parts: ReactNode[] = [];
  const pattern = /\[([^\]]+)\]\(([^)]+)\)|\[(\d+)\]/g;
  let start = 0;
  for (const match of text.matchAll(pattern)) {
    const index = match.index ?? 0;
    parts.push(text.slice(start, index));
    if (match[3] && Number(match[3]) <= sourceCount) parts.push(<a key={index} className="source-reference" href={`#source-${match[3]}`} aria-label={`Source ${match[3]}`}>[{match[3]}]</a>);
    else if (match[1] && match[2] && /^(https?:\/\/|\/(?!\/)|#)/.test(match[2])) {
      const label = /^\d+$/.test(match[1]) ? `[${match[1]}]` : match[1];
      parts.push(match[2].startsWith("/") ? <Link key={index} href={match[2]}>{label}</Link> : <a key={index} href={match[2]}>{label}</a>);
    }
    else parts.push(match[0]);
    start = index + match[0].length;
  }
  parts.push(text.slice(start));
  return <>{parts.map((part, index) => <Fragment key={index}>{part}</Fragment>)}</>;
}

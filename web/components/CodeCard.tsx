"use client";
import { useRef, useState } from "react";
import { formatCode } from "@/lib/code";

/**
 * The printed player card: the one object players physically hold. Credit-card proportions, paper stock,
 * a double rule like a scorecard header, the code set large in mono. Prints four to a page.
 */
export default function CodeCard({ tournament, player, code, host }: { tournament: string; player: string; code: string; host: string }) {
  return (
    <div data-code-card data-player={player} className="break-inside-avoid rounded-xl bg-paper p-5 ring-1 ring-hair print:rounded-none print:ring-stone-400">
      <div className="flex items-center gap-2">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/icon-192.png" alt="" className="h-6 w-6 object-contain mix-blend-multiply" />
        <span className="text-xs text-stone-600">Albatross Tournaments</span>
      </div>
      <div className="mt-4 border-y-4 border-double border-stone-300 py-3">
        <div className="font-serif text-2xl leading-tight text-brand">{tournament}</div>
        <div className="mt-1 text-lg font-bold text-stone-900">{player}</div>
      </div>
      <div className="mt-4 font-mono text-3xl tracking-widest text-stone-900">{formatCode(code)}</div>
      <div className="mt-3 text-xs text-stone-600">Enter this code at {host}/join</div>
    </div>
  );
}

export type IssuedCard = { userId: string; name: string; code: string };

/**
 * The new player cards, one at a time: swipe or use the arrows, the dots show how many there are.
 * Printing lays every card out in a grid instead.
 */
export function CodeCarousel({ cards, tournament, host }: { cards: IssuedCard[]; tournament: string; host: string }) {
  const track = useRef<HTMLDivElement>(null);
  const [index, setIndex] = useState(0);
  const current = Math.min(index, Math.max(0, cards.length - 1));

  const go = (to: number) => {
    const el = track.current;
    if (!el) return;
    const next = Math.max(0, Math.min(cards.length - 1, to));
    el.scrollTo({ left: next * el.clientWidth, behavior: "smooth" });
    setIndex(next);
  };
  const onScroll = () => {
    const el = track.current;
    if (el && el.clientWidth > 0) setIndex(Math.round(el.scrollLeft / el.clientWidth));
  };

  return (
    <div role="group" aria-roledescription="carousel" aria-label="New player cards" className="space-y-3">
      <div className="flex items-center gap-2">
        <button type="button" className="btn-ghost shrink-0 !px-3 print:hidden" aria-label="Previous card" disabled={current === 0} onClick={() => go(current - 1)}>‹</button>
        <div ref={track} tabIndex={0} aria-label={`Card ${current + 1} of ${cards.length}`} onScroll={onScroll}
          onKeyDown={(e) => { if (e.key === "ArrowLeft") { e.preventDefault(); go(current - 1); } if (e.key === "ArrowRight") { e.preventDefault(); go(current + 1); } }}
          className="flex min-w-0 flex-1 snap-x snap-mandatory overflow-x-auto scroll-smooth [scrollbar-width:none] [&::-webkit-scrollbar]:hidden print:grid print:grid-cols-2 print:gap-2 print:overflow-visible">
          {cards.map((c, i) => (
            <div key={c.userId} aria-label={`${i + 1} of ${cards.length}`} className="w-full shrink-0 snap-center px-1 print:w-auto print:px-0">
              <CodeCard tournament={tournament} player={c.name} code={c.code} host={host} />
            </div>
          ))}
        </div>
        <button type="button" className="btn-ghost shrink-0 !px-3 print:hidden" aria-label="Next card" disabled={current >= cards.length - 1} onClick={() => go(current + 1)}>›</button>
      </div>
      <div className="flex flex-wrap items-center justify-center gap-x-1 print:hidden">
        {cards.map((c, i) => (
          <button key={c.userId} type="button" aria-label={`Show ${c.name}'s card`} aria-current={i === current} onClick={() => go(i)} className="flex h-6 w-5 items-center justify-center">
            <span className={`h-2 w-2 rounded-full transition-colors duration-150 ${i === current ? "bg-brand" : "bg-stone-300"}`} />
          </button>
        ))}
      </div>
      <p className="muted text-center print:hidden"><span className="tnum">{current + 1}</span> of <span className="tnum">{cards.length}</span></p>
    </div>
  );
}

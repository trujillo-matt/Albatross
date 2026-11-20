import Link from "next/link";
import Page from "@/components/Page";
import ScorecardPreview from "@/components/ScorecardPreview";

export default function Home() {
  return (
    <Page wide>
      <div className="flex min-h-[calc(100svh-3rem)] flex-col gap-12 pt-8 md:grid md:min-h-0 md:grid-cols-2 md:items-center md:gap-16 md:pt-24">
        <div className="flex flex-1 flex-col justify-center md:block">
          <p className="label">Albatross Tournaments</p>
          <h1 className="h1 mt-3 text-4xl md:text-5xl">Score your golf tournament, hole by hole</h1>
          <p className="mt-4 max-w-md text-lg leading-7 text-stone-600">
            Players enter the code from their organizer, log their own round on a phone, and follow the standings
          </p>
          <div className="mt-8 flex flex-col gap-3 sm:flex-row">
            <Link href="/join" className="btn">I have a player code</Link>
            <Link href="/admin" className="btn-ghost">Tournament admin</Link>
          </div>
        </div>
        <div className="-mx-4 -mb-6 mt-auto md:mx-0 md:mb-0 md:mt-0"><ScorecardPreview /></div>
      </div>
    </Page>
  );
}

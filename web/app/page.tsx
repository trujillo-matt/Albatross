import Link from "next/link";

export default function Home() {
  return (
    <div className="space-y-6 pt-10 text-center">
      <h1 className="text-3xl font-bold text-brand">Albatross Tournaments</h1>
      <p className="muted">Log your scores, vote for captains, and follow the standings.</p>
      <Link href="/join" className="btn w-full">I have a player code</Link>
      <Link href="/admin" className="btn-ghost w-full">Tournament admin</Link>
    </div>
  );
}

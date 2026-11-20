import Page from "@/components/Page";

export default function Offline() {
  return (
    <Page>
      <div className="card mt-12 space-y-2">
        <h1 className="h2">You are offline</h1>
        <p className="muted">Scores you already entered are saved on this phone and will sync when you have signal again. Open your scorecard from the match list if you were already signed in</p>
      </div>
    </Page>
  );
}

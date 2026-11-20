# Web app design notes

Result of an unslop pass on the web app (screens audited at phone width for players and desktop width for admin).
The app was already restrained, so this was polish: no gradients, glows or emoji to remove. What changed is craft.

## Direction

- **Product:** a phone-first scoring site for golf trips and club events. Players enter their own scores with a code;
  organizers run captains, the draft, pairings and standings.
- **Character:** calm, exact, a little heritage.
- **World:** the printed scorecard and the clubhouse leaderboard. Paper, ink, fairway green.
- **Moments:** the standings scoreboard (`components/Scoreboard.tsx`) and the printed player card
  (`components/CodeCard.tsx`). The landing page also shows a scorecard preview (`components/ScorecardPreview.tsx`).
- **Signature:** the status dot (`components/ui.tsx`): green is live or synced, amber needs attention, grey is idle.

## System

- **Brand:** forest green `#243627`, the same as the iOS app. Everything else is a warm neutral.
- **Type:** Newsreader (serif) for page titles and score numerals only, Inter for everything else, both self-hosted
  through `@fontsource-variable` so every device matches and no phone calls a third party. Weights 400 and 500.
  `.num` is serif tabular figures for scores; `.tnum` is tabular figures for counts inside sentences.
- **Hairline:** one value, `hair` (stone-900 at 10%), for every border and divider.
- **Controls:** 44px tall buttons, 8px radius, hover, focus-visible and press states, one easing curve
  (`cubic-bezier(0.22, 1, 0.36, 1)`), transitions on color, background and transform only.
- **Lists:** rows with dividers inside one card, not a card per row.
- **Layout:** players get a phone-width column; the admin dashboard widens to about 1000px on desktop with underline tabs.

## Not changed on purpose

Palette, player flows, logic, copy meaning, and the iOS-matching brand green.

## Suggestions not applied

- Scorecard notation (ring for birdie, square for bogey) on the player's own scorecard strip. It is used on the landing
  preview only.
- Reconsider Realtime copy ("Updates every 15 seconds" on the spectator page) once push updates are verified on phones.

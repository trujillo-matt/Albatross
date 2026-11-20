-- Gives each tournament team an explicit side so nothing depends on row order.
-- NOT YET APPLIED. Written against the schema inferred from the Swift client;
-- review against the live Supabase schema before running.

alter table tournament_teams
  add column if not exists side text;

-- Backfill existing rows from the names the iOS app has always used.
update tournament_teams set side = 'A' where side is null and name = 'Team A';
update tournament_teams set side = 'B' where side is null and name = 'Team B';

-- Any row still null has a non-standard name. Inspect before enforcing:
--   select * from tournament_teams where side is null;

alter table tournament_teams
  add constraint tournament_teams_side_check check (side in ('A', 'B'));

create unique index if not exists tournament_teams_one_per_side
  on tournament_teams (tournament_id, side);

-- Make it NOT NULL only after the backfill check above returns zero rows:
--   alter table tournament_teams alter column side set not null;

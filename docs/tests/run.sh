#!/usr/bin/env bash
# Applies a local copy of the live schema and migrations 001 to 021 to a scratch Postgres database and runs the SQL tests.
# Usage: PGHOST=/path/to/socket PGPORT=5544 PGUSER=postgres docs/tests/run.sh
set -euo pipefail
cd "$(dirname "$0")"
DB=albatross_test
psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists $DB" -c "create database $DB"
# roles are cluster-wide, so tolerate them already existing
psql -d postgres -q -c "drop role if exists anon" -c "drop role if exists authenticated" 2>/dev/null || true
for f in 00_stub_schema.sql ../migrations/001_tournament_team_side.sql ../migrations/002_tournament_rules.sql \
         ../migrations/003_player_codes.sql ../migrations/004_spectator_audit.sql \
         05_demonstrate_bugs.sql ../migrations/005_rls_fixes.sql ../migrations/006_function_privileges.sql ../migrations/007_signup_trigger_search_path.sql ../migrations/008_sessions_callouts.sql ../migrations/009_group_scoring.sql 10_rules_test.sql 20_rls_test.sql 30_privileges_test.sql 40_signup_trigger_test.sql 50_sessions_callouts_test.sql 60_group_scoring_test.sql ../migrations/010_tournament_news.sql ../migrations/011_callout_presence.sql ../migrations/012_foursome_scoring.sql ../migrations/013_team_style_tee_times.sql ../migrations/014_security_hardening.sql ../migrations/015_public_standings_sessions.sql ../migrations/016_lead_change_news.sql 70_security_hardening_test.sql ../migrations/017_shamble.sql 80_shamble_test.sql ../migrations/018_admin_edit_recomputes.sql ../migrations/019_admin_set_result.sql ../migrations/020_admin_remove_player.sql ../migrations/021_tiebreak_match.sql 90_admin_edits_test.sql; do
  echo "== $f"
  psql -v ON_ERROR_STOP=1 -q -d $DB -f "$f"
done
echo "ALL SQL TESTS PASSED"

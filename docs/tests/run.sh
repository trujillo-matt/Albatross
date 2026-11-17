#!/usr/bin/env bash
# Applies a local copy of the live schema and migrations 001 to 005 to a scratch Postgres database and runs the SQL tests.
# Usage: PGHOST=/path/to/socket PGPORT=5544 PGUSER=postgres docs/tests/run.sh
set -euo pipefail
cd "$(dirname "$0")"
DB=albatross_test
psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists $DB" -c "create database $DB"
# roles are cluster-wide, so tolerate them already existing
psql -d postgres -q -c "drop role if exists anon" -c "drop role if exists authenticated" 2>/dev/null || true
for f in 00_stub_schema.sql ../migrations/001_tournament_team_side.sql ../migrations/002_tournament_rules.sql \
         ../migrations/003_player_codes.sql ../migrations/004_spectator_audit.sql \
         05_demonstrate_bugs.sql ../migrations/005_rls_fixes.sql 10_rules_test.sql 20_rls_test.sql; do
  echo "== $f"
  psql -v ON_ERROR_STOP=1 -q -d $DB -f "$f"
done
echo "ALL SQL TESTS PASSED"

-- Rollback for 023: no queued alerts, no turn trigger, no tee time reminders. News alerts (022) are untouched.
begin;
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'tee-time-reminders';
  end if;
end $$;
drop trigger if exists push_callout_turn on tournament_sessions;
drop function if exists push_on_callout_turn();
drop function if exists queue_tee_time_reminders();
drop trigger if exists push_queue_kick on push_queue;
drop function if exists push_queue_kick();
drop function if exists claim_push_queue(int);
drop table if exists push_queue;
commit;

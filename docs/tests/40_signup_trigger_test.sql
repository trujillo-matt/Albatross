-- After 007: the signup trigger works when Auth runs it (search_path = auth) and keeps the old behavior.
do $$ begin
  set local search_path = auth;
  insert into auth.users (id, raw_user_meta_data) values (b.u(91), '{"display_name":"Managed Y"}');
  insert into auth.users (id, raw_user_meta_data) values (b.u(92), '{"full_name":"Full Z","display_name":"ignored","username":"zed"}');
  insert into auth.users (id) values (b.u(93));
  reset search_path;
  perform b.assert((select display_name from public.profiles where id = b.u(91)) = 'Managed Y', 'display_name used when no full_name');
  perform b.assert((select display_name from public.profiles where id = b.u(92)) = 'Full Z', 'full_name wins, as before');
  perform b.assert((select username from public.profiles where id = b.u(92)) = 'zed', 'username copied, as before');
  perform b.assert((select display_name from public.profiles where id = b.u(93)) = '', 'empty name when no metadata, as before');
  perform b.assert((select prosecdef and proconfig is not null from pg_proc where proname = 'handle_new_user'), 'security definer with pinned search_path');
end $$;

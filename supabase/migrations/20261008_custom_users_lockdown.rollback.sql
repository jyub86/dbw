-- 20261008_custom_users_lockdown 되돌리기 (문제가 생겼을 때만 실행)
-- 적용 전 정책을 그대로 복원한다. 보안 구멍도 함께 되살아나므로 원인을 고친 뒤 다시 적용할 것.

drop trigger if exists custom_users_guard on public.custom_users;
drop function if exists public.custom_users_guard();

drop policy if exists cu_sel_anon on public.custom_users;
drop policy if exists cu_sel_auth on public.custom_users;
drop policy if exists cu_upd_self on public.custom_users;
drop policy if exists cu_upd_manager on public.custom_users;
drop policy if exists cu_ins on public.custom_users;

create policy "Enable read access for all users" on public.custom_users for select to public using (true);
create policy "Allow updates based on active status" on public.custom_users for update to authenticated
  using ((active = false) or ((active = true) and (auth.uid() = auth_id)));
create policy " Allow update for high-permission users" on public.custom_users for update to public
  using ((select roles.level from roles where roles.id = (select custom_users_1.role from custom_users custom_users_1 where custom_users_1.auth_id = auth.uid())) >= 50)
  with check ((select roles.level from roles where roles.id = (select custom_users_1.role from custom_users custom_users_1 where custom_users_1.auth_id = auth.uid())) >= 50);
create policy "Enable insert for authenticated users only" on public.custom_users for insert to authenticated with check (true);
grant all on public.custom_users to anon;

alter function public.welcome_new_user() security invoker reset search_path;

drop policy if exists msg_ins on public.messages;
create policy "Enable insert for authenticated users only" on public.messages for insert to authenticated with check (true);
drop policy if exists posts_ins on public.posts;
create policy "Enable insert for authenticated users only" on public.posts for insert to authenticated with check (true);
drop policy if exists comments_ins on public.comments;
create policy "Enable insert for authenticated users only" on public.comments for insert to authenticated with check (true);
drop policy if exists likes_ins on public.likes;
create policy "Enable insert for authenticated users only" on public.likes for insert to authenticated with check (true);

-- 헬퍼 함수(app_user_level, app_is_member, app_can_view_all_profiles)와 인덱스는 남겨 둬도 무해하다.
notify pgrst, 'reload schema';

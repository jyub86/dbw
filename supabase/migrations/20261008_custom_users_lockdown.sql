-- custom_users 보안 강화 (2026-10-08)
--
-- 고치는 것
--   1. 비로그인(anon)이 교인 전원의 전화·생년월일·이메일·성별을 읽을 수 있음
--   2. 로그인 사용자도 전원의 개인정보를 읽을 수 있음
--   3. 본인 role 을 관리자로 바꾸거나, 처음 가입할 때 role 을 지정할 수 있음 (권한 상승)
--   4. 남의 미가입 placeholder 행(active=false)을 수정할 수 있음 (auth_id 가로채기 포함)
--   5. 본인을 교인 인증(member=true) 처리할 수 있음
--   6. 로그인 사용자 누구나 '전체' 메시지를 넣어 전 교인에게 푸시를 보낼 수 있음, 발신자 사칭 가능
--   7. 게시글·댓글·좋아요를 남의 이름(user_id)으로 넣을 수 있음
--
-- 지키는 것 (웹·Flutter 앱 사용처 전수 조사 기준)
--   - 앱은 custom_users 를 select('*') 로 읽으므로 authenticated 의 컬럼 권한은 건드리지 않고 '행'만 좁힌다.
--     authenticated 컬럼 권한 회수는 앱 업데이트 이후 2단계로 미룬다.
--   - anon 이 쓰는 컬럼은 게시판 작성자 표시용(auth_id, name, office, profile_picture)뿐이다.
--   - merge_user_data(가입 시 placeholder 병합)는 SECURITY DEFINER 라 아래 가드에 걸리지 않는다.
--   - 서비스 롤(bpdb_daily, Edge Function)과 대시보드는 RLS·가드 대상이 아니다.
--
-- 알려진 영향
--   - 2025-02~03 빌드(앱 1.0.2~1.0.6)의 '기존 placeholder 연결' 가입 방식은 더 이상 동작하지 않는다.

-- ─────────────────────────────────────────────────────────────
-- 0. 헬퍼 (SECURITY DEFINER: custom_users 정책 안에서 써도 재귀하지 않는다)
-- ─────────────────────────────────────────────────────────────

create or replace function public.app_user_level() returns integer
language sql stable security definer set search_path = public as $fn$
  select coalesce((select r.level::int
                     from custom_users u join roles r on r.id = u.role
                    where u.auth_id = auth.uid()), 0)
$fn$;

create or replace function public.app_is_member() returns boolean
language sql stable security definer set search_path = public as $fn$
  select coalesce((select u.member from custom_users u where u.auth_id = auth.uid()), false)
$fn$;

-- 교인 전원의 프로필을 볼 수 있는 사람: 매니저 이상(앱 요람·관리 화면), 교역자, 관리자
create or replace function public.app_can_view_all_profiles() returns boolean
language sql stable security definer set search_path = public as $fn$
  select public.app_user_level() >= 50 or public.app_can_manage()
$fn$;

-- 아래 정책의 EXISTS 조회용
create index if not exists idx_posts_user_id on public.posts (user_id);
create index if not exists idx_comments_user_id on public.comments (user_id);
create index if not exists idx_messages_sender_id on public.messages (sender_id);

-- ─────────────────────────────────────────────────────────────
-- 1. 조회
-- ─────────────────────────────────────────────────────────────

drop policy if exists "Enable read access for all users" on public.custom_users;

-- 비로그인: 게시판 작성자 행만, 공개 컬럼만
create policy cu_sel_anon on public.custom_users for select to anon
  using (exists (select 1 from public.posts p
                  where p.user_id = custom_users.auth_id and p.active is not false));

revoke all on public.custom_users from anon;
grant select (id, auth_id, name, office, profile_picture, role) on public.custom_users to anon;

-- 로그인: 아래 중 하나에 해당하는 행만
create policy cu_sel_auth on public.custom_users for select to authenticated
  using (
    -- 본인
    auth_id = (select auth.uid())
    -- 매니저 이상·교역자·관리자는 전원 (앱 요람 전체, 명단 관리, 사람 검색)
    or (select public.app_can_view_all_profiles())
    -- 정보공개에 동의한 교인 (조회자도 교인일 때) — 앱 요람
    or (is_info_public and member and (select public.app_is_member()))
    -- 게시글·댓글 작성자, 나에게 보이는 메시지의 발신자 — 이름 표시
    or exists (select 1 from public.posts p
                where p.user_id = custom_users.auth_id and p.active is not false)
    or exists (select 1 from public.comments c
                where c.user_id = custom_users.auth_id and c.active is not false)
    or exists (select 1 from public.messages m where m.sender_id = custom_users.auth_id)
    -- 내가 볼 수 있는 소그룹 명단의 구성원 (리더 → 자기 그룹, 교역자 → 전체) — 출석부
    or exists (select 1 from public.small_group_members g where g.user_id = custom_users.id)
    -- 내가 볼 수 있는 차량의 차주 (주차 담당자) — 이중주차 연락
    or exists (select 1 from public.member_vehicles v where v.user_id = custom_users.id)
  );

-- ─────────────────────────────────────────────────────────────
-- 2. 쓰기
-- ─────────────────────────────────────────────────────────────

-- 남의 active=false 행까지 고칠 수 있던 정책 → 본인 행만
drop policy if exists "Allow updates based on active status" on public.custom_users;
create policy cu_upd_self on public.custom_users for update to authenticated
  using (auth_id = (select auth.uid()))
  with check (auth_id = (select auth.uid()));

-- 매니저 이상(level >= 50)의 성도 정보 수정(앱 요람). 기존 정책은 custom_users 를 직접 서브쿼리해서,
-- 위 조회 정책(서브쿼리 포함)과 만나면 '정책 무한 재귀'로 모든 UPDATE 가 실패한다 → definer 헬퍼로 바꾼다.
drop policy if exists " Allow update for high-permission users" on public.custom_users;
create policy cu_upd_manager on public.custom_users for update to authenticated
  using ((select public.app_user_level()) >= 50)
  with check ((select public.app_user_level()) >= 50);

-- 아무 행이나 넣을 수 있던 정책 → 본인 행, 또는 담당자가 만드는 미가입 교인 프로필
drop policy if exists "Enable insert for authenticated users only" on public.custom_users;
create policy cu_ins on public.custom_users for insert to authenticated
  with check (auth_id = (select auth.uid()) or (select public.app_can_view_all_profiles()));

-- 컬럼 가드: role·auth_id 는 관리자만, member·active 는 담당자만 바꾼다.
create or replace function public.custom_users_guard() returns trigger
language plpgsql set search_path = public as $fn$
begin
  -- 서비스 롤·대시보드·SECURITY DEFINER 함수(merge_user_data 등)는 검사하지 않는다
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.role is distinct from 4 and not public.app_is_admin() then  -- 4 = 일반 사용자(기본값)
      raise exception '권한 등급은 관리자만 지정할 수 있습니다' using errcode = '42501';
    end if;
    if new.member and not public.app_can_view_all_profiles() then
      raise exception '교인 인증은 담당자만 할 수 있습니다' using errcode = '42501';
    end if;
    return new;
  end if;

  if (new.role is distinct from old.role or new.auth_id is distinct from old.auth_id)
     and not public.app_is_admin() then
    raise exception '권한 등급과 계정 연결은 관리자만 바꿀 수 있습니다' using errcode = '42501';
  end if;
  if (new.member is distinct from old.member or new.active is distinct from old.active)
     and not public.app_can_view_all_profiles() then
    raise exception '교인 인증과 활성 상태는 담당자만 바꿀 수 있습니다' using errcode = '42501';
  end if;
  return new;
end
$fn$;

drop trigger if exists custom_users_guard on public.custom_users;
create trigger custom_users_guard before insert or update on public.custom_users
  for each row execute function public.custom_users_guard();

-- ─────────────────────────────────────────────────────────────
-- 3. 메시지: 보내기는 매니저 이상만, 발신자는 본인으로
-- ─────────────────────────────────────────────────────────────

-- 가입 환영 메시지는 가입자 본인 권한으로 들어가므로 definer 로 바꾼다
alter function public.welcome_new_user() security definer set search_path = public;

drop policy if exists "Enable insert for authenticated users only" on public.messages;
create policy msg_ins on public.messages for insert to authenticated
  with check (sender_id = (select auth.uid()) and (select public.app_user_level()) >= 50);

-- ─────────────────────────────────────────────────────────────
-- 4. 게시글·댓글·좋아요: 남의 이름으로 쓰지 못하게
-- ─────────────────────────────────────────────────────────────

drop policy if exists "Enable insert for authenticated users only" on public.posts;
create policy posts_ins on public.posts for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Enable insert for authenticated users only" on public.comments;
create policy comments_ins on public.comments for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Enable insert for authenticated users only" on public.likes;
create policy likes_ins on public.likes for insert to authenticated
  with check (user_id = (select auth.uid()));

notify pgrst, 'reload schema';

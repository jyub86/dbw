-- 교적 2단계 인증(인증 앱)을 교적 전용 비밀번호로 바꾼다 (2026-10-14 사용자 결정, 설계 §4.4·§9 결정 2)
--
--   - 교역자가 처음 등록한 인증 앱을 다시 찾지 못해 막혀서, 들어갈 때마다 본인이 정한 비밀번호를 넣는 방식으로 바꾼다.
--     로그인은 카카오·애플·구글이라 우리 쪽에 로그인 비밀번호가 없다
--   - 처음 들어갈 때 본인이 정한다. 영문과 숫자를 섞어 8자 이상. bcrypt(pgcrypto)로만 저장한다
--   - 맞히면 그 로그인 세션(JWT session_id)만 열린다. 화면을 쓰는 동안 registry_touch 가 늘리고,
--     쓰지 않고 idle_minutes 가 지나면 서버에서도 닫힌다
--   - 5번 연속 틀리면 잠기고, 사이트 관리자가 '권한·기록'에서 초기화할 때까지 열 수 없다
--   - 정하기·맞힘·틀림·잠김·초기화는 접속기록(action 'auth')에 남는다
--   - 비밀번호와 세션은 auth.users 를 참조한다. 앱 탈퇴로 계정이 지워지면 함께 지워진다

-- ─────────────────────────────────────────────────────────────
-- 1. 표
-- ─────────────────────────────────────────────────────────────

alter table privacy.access_logs drop constraint access_logs_action_check;
alter table privacy.access_logs add constraint access_logs_action_check
  check (action in ('search', 'view', 'create', 'update', 'delete', 'export', 'print', 'auth'));

alter table registry.settings add column require_password boolean not null default true;  -- 장애 대응용 스위치. 평소에는 켜 둔다

create table registry.passwords (
  auth_id   uuid primary key references auth.users(id) on delete cascade,
  hash      text not null,
  failed    integer not null default 0,  -- 연속으로 틀린 횟수. 맞히면 0
  locked_at timestamptz,                 -- 5번째로 틀린 때. 초기화하면 행이 지워진다
  set_at    timestamptz not null default now()
);
alter table registry.passwords enable row level security;

create table registry.unlocks (
  session_id  uuid primary key,          -- 로그인 세션 (JWT session_id)
  auth_id     uuid not null references auth.users(id) on delete cascade,
  unlocked_at timestamptz not null default now(),
  last_seen   timestamptz not null default now()
);
create index unlocks_auth_id_idx on registry.unlocks (auth_id);
alter table registry.unlocks enable row level security;

-- ─────────────────────────────────────────────────────────────
-- 2. 확인 헬퍼
-- ─────────────────────────────────────────────────────────────

create function registry.session_id() returns uuid
language sql stable set search_path = '' as $fn$
  select nullif(auth.jwt() ->> 'session_id', '')::uuid;
$fn$;

-- 이 로그인 세션이 비밀번호로 열려 있고, idle_minutes 안에 쓴 적이 있는지
create function registry.unlocked() returns boolean
language sql stable security definer set search_path = '' as $fn$
  select exists (
    select 1 from registry.unlocks l
     where l.session_id = registry.session_id()
       and l.auth_id = auth.uid()
       and l.last_seen > now() - make_interval(mins => coalesce((select s.idle_minutes from registry.settings s), 30)));
$fn$;

-- 교적 비밀번호 확인. 프론트는 hint = 'unlock_required' 로 비밀번호 화면에 보낸다
create function registry.require_unlock() returns void
language plpgsql stable security definer set search_path = '' as $fn$
begin
  if coalesce((select s.require_password from registry.settings s), true) and not registry.unlocked() then
    raise exception '교적 비밀번호를 넣어 주세요' using errcode = '42501', hint = 'unlock_required';
  end if;
end
$fn$;

create or replace function registry.require(p_need text default 'view') returns registry.staff
language plpgsql stable security definer set search_path = '' as $fn$
declare
  s registry.staff;
begin
  if auth.uid() is null then
    raise exception '로그인이 필요합니다' using errcode = '42501';
  end if;
  select * into s from registry.staff st where st.user_id = public.app_current_user_id();
  if not found then
    raise exception '교적 권한이 없습니다' using errcode = '42501';
  end if;
  perform registry.require_unlock();
  if (p_need = 'edit' and not s.can_edit)
     or (p_need = 'export' and not s.can_export)
     or (p_need = 'pastoral' and not s.can_pastoral) then
    raise exception '이 작업을 할 권한이 없습니다' using errcode = '42501';
  end if;
  return s;
end
$fn$;

-- 교적 권한을 다루고 접속기록을 보는 사람: 사이트 관리자 + 교적 비밀번호
create or replace function registry.require_admin() returns void
language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not public.app_is_admin() then
    raise exception '사이트 관리자만 할 수 있습니다' using errcode = '42501';
  end if;
  perform registry.require_unlock();
end
$fn$;

drop function registry.require_mfa();

-- 교적 비밀번호를 정하거나 넣을 수 있는 사람: 교적 담당자 또는 사이트 관리자
create function registry.can_enter() returns boolean
language sql stable security definer set search_path = '' as $fn$
  select auth.uid() is not null
     and (public.app_is_admin()
          or exists (select 1 from registry.staff st where st.user_id = public.app_current_user_id()));
$fn$;

-- 비밀번호 규칙. 문제가 없으면 null
create function registry.password_problem(p text) returns text
language sql immutable set search_path = '' as $fn$
  select case
    when p is null or length(p) < 8 then '비밀번호는 8자 이상이어야 합니다'
    when length(p) > 64 then '비밀번호는 64자까지 쓸 수 있습니다'
    when p !~ '[0-9]' or p !~ '[A-Za-z]' then '비밀번호는 영문과 숫자를 섞어 주세요'
  end;
$fn$;

-- 지금 로그인 세션을 연다
create function registry.open_session() returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  sid uuid := registry.session_id();
begin
  if sid is null then
    raise exception '로그인을 다시 해 주세요' using errcode = '42501';
  end if;
  delete from registry.unlocks l where l.last_seen < now() - interval '1 day';
  insert into registry.unlocks (session_id, auth_id) values (sid, auth.uid())
  on conflict (session_id) do update set auth_id = excluded.auth_id, unlocked_at = now(), last_seen = now();
end
$fn$;

-- ─────────────────────────────────────────────────────────────
-- 3. 화면이 부르는 함수 (public)
-- ─────────────────────────────────────────────────────────────

-- 처음 들어갈 때 본인이 정한다. 바꾸려면 사이트 관리자가 초기화한 뒤 다시 정한다
create function public.registry_password_set(p_password text) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  why text;
begin
  if not registry.can_enter() then
    raise exception '교적 권한이 없습니다' using errcode = '42501';
  end if;
  if exists (select 1 from registry.passwords p where p.auth_id = auth.uid()) then
    raise exception '이미 교적 비밀번호를 정했습니다. 바꾸려면 사이트 관리자에게 초기화를 부탁해 주세요' using errcode = '42501';
  end if;
  why := registry.password_problem(p_password);
  if why is not null then
    raise exception '%', why using errcode = '22023';
  end if;
  insert into registry.passwords (auth_id, hash)
  values (auth.uid(), extensions.crypt(p_password, extensions.gen_salt('bf', 10)));
  perform registry.open_session();
  perform privacy.log_access('auth', 'registry_password_set', '{}', jsonb_build_object('result', 'set'));
end
$fn$;

-- 틀린 횟수를 남겨야 하므로 예외 대신 결과를 돌려준다: {ok} / {ok:false, reason: not_set|wrong|locked, left}
create function public.registry_unlock(p_password text) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare
  max_tries constant integer := 5;
  pw    registry.passwords;
  tries integer;
begin
  if not registry.can_enter() then
    raise exception '교적 권한이 없습니다' using errcode = '42501';
  end if;
  select * into pw from registry.passwords p where p.auth_id = auth.uid() for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_set');
  end if;
  if pw.locked_at is not null then
    perform privacy.log_access('auth', 'registry_unlock', '{}', jsonb_build_object('result', 'blocked'));
    return jsonb_build_object('ok', false, 'reason', 'locked', 'left', 0);
  end if;

  if pw.hash = extensions.crypt(coalesce(p_password, ''), pw.hash) then
    update registry.passwords p set failed = 0 where p.auth_id = pw.auth_id;
    perform registry.open_session();
    perform privacy.log_access('auth', 'registry_unlock', '{}', jsonb_build_object('result', 'ok'));
    return jsonb_build_object('ok', true);
  end if;

  tries := pw.failed + 1;
  update registry.passwords p
     set failed = tries,
         locked_at = case when tries >= max_tries then now() end
   where p.auth_id = pw.auth_id;
  if tries >= max_tries then
    delete from registry.unlocks l where l.auth_id = pw.auth_id;
  end if;
  perform privacy.log_access('auth', 'registry_unlock', '{}',
    jsonb_build_object('result', case when tries >= max_tries then 'locked' else 'wrong' end, 'failed', tries));
  return jsonb_build_object('ok', false,
                            'reason', case when tries >= max_tries then 'locked' else 'wrong' end,
                            'left', greatest(max_tries - tries, 0));
end
$fn$;

-- 화면을 쓰는 동안 몇 분마다 부른다. 이미 닫혔으면 false
create function public.registry_touch() returns boolean
language plpgsql security definer set search_path = '' as $fn$
begin
  update registry.unlocks l set last_seen = now()
   where l.session_id = registry.session_id()
     and l.auth_id = auth.uid()
     and l.last_seen > now() - make_interval(mins => coalesce((select s.idle_minutes from registry.settings s), 30));
  return found;
end
$fn$;

-- 화면이 잠길 때 서버 쪽 세션도 닫는다
create function public.registry_lock() returns void
language sql security definer set search_path = '' as $fn$
  delete from registry.unlocks l where l.session_id = registry.session_id() and l.auth_id = auth.uid();
$fn$;

-- 비밀번호를 잊었거나 잠긴 담당자. 지우면 다음에 들어갈 때 새로 정한다
create function public.registry_password_reset(p_user_id uuid) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  a uuid;
begin
  perform registry.require_admin();
  select u.auth_id into a from public.custom_users u where u.id = p_user_id;
  if a is null then
    raise exception '대상을 찾지 못했습니다' using errcode = '22023';
  end if;
  delete from registry.passwords p where p.auth_id = a;
  delete from registry.unlocks l where l.auth_id = a;
  perform privacy.log_access('auth', 'registry_password_reset', array[p_user_id], jsonb_build_object('result', 'reset'));
end
$fn$;

-- 내 교적 권한. 메뉴 표시와 비밀번호 화면 안내용이다. 교인 정보가 없으므로 기록하지 않는다
create or replace function public.registry_me() returns jsonb
language plpgsql stable security definer set search_path = '' as $fn$
declare
  s   registry.staff;
  cfg registry.settings;
  pw  registry.passwords;
begin
  select * into s from registry.staff st where st.user_id = public.app_current_user_id();
  select * into cfg from registry.settings;
  select * into pw from registry.passwords p where p.auth_id = auth.uid();
  return jsonb_build_object(
    'is_staff',          s.user_id is not null,
    'is_admin',          public.app_is_admin(),
    'can_edit',          coalesce(s.can_edit, false),
    'can_export',        coalesce(s.can_export, false),
    'can_pastoral',      coalesce(s.can_pastoral, false),
    'password_required', coalesce(cfg.require_password, true),
    'password_set',      pw.auth_id is not null,
    'locked_out',        pw.locked_at is not null,
    'unlocked',          registry.unlocked(),
    'idle_minutes',      coalesce(cfg.idle_minutes, 30)
  );
end
$fn$;

alter table registry.settings drop column require_mfa;

drop function public.registry_staff_list();
create function public.registry_staff_list()
returns table (user_id uuid, name text, office text, can_edit boolean, can_export boolean,
               can_pastoral boolean, note text, granted_at timestamptz, granted_by_name text, password text)
language plpgsql stable security definer set search_path = '' as $fn$
begin
  perform registry.require_admin();
  return query
    select s.user_id, u.name, u.office, s.can_edit, s.can_export, s.can_pastoral, s.note, s.granted_at, g.name,
           case when pw.auth_id is null then 'none' when pw.locked_at is not null then 'locked' else 'set' end
      from registry.staff s
      join public.custom_users u on u.id = s.user_id
      left join public.custom_users g on g.id = s.granted_by
      left join registry.passwords pw on pw.auth_id = u.auth_id
     order by u.name;
end
$fn$;

-- ─────────────────────────────────────────────────────────────
-- 4. 실행 권한
-- ─────────────────────────────────────────────────────────────

revoke all on function public.registry_staff_list() from public, anon;
revoke all on function public.registry_password_set(text) from public, anon;
revoke all on function public.registry_unlock(text) from public, anon;
revoke all on function public.registry_touch() from public, anon;
revoke all on function public.registry_lock() from public, anon;
revoke all on function public.registry_password_reset(uuid) from public, anon;
grant execute on function public.registry_staff_list() to authenticated;
grant execute on function public.registry_password_set(text) to authenticated;
grant execute on function public.registry_unlock(text) to authenticated;
grant execute on function public.registry_touch() to authenticated;
grant execute on function public.registry_lock() to authenticated;
grant execute on function public.registry_password_reset(uuid) to authenticated;

revoke all on all functions in schema registry from public;

-- 운영 적용 순서: 지금 배포된 화면은 비밀번호를 넣을 수 없으므로 스위치를 끈 채 적용하고,
-- 새 화면(RegistryGate 비밀번호)이 배포된 뒤 `update registry.settings set require_password = true where id;` 로 켠다
update registry.settings set require_password = false where id;

notify pgrst, 'reload schema';

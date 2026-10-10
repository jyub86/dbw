-- 교적 기반 (2026-10-10): 교적 권한, 접속기록, 변경기록, 권한 이력, 2단계 인증 확인
--
-- 설계: docs/church-admin/02-registry-design.md §2, §4
--   registry : 교적 데이터. 이 마이그레이션에서는 권한·설정만 만든다. API에 노출하지 않는다.
--   privacy  : 접속기록·변경기록·권한 이력. 추가만 된다. 재정도 나중에 같이 쓴다.
--   화면은 public.registry_* / public.privacy_* 함수만 부른다. 함수가 권한을 확인하고 기록을 남긴다.
--
-- 지키는 것
--   - 사이트 관리자도 교적 권한을 따로 받아야 교적을 본다. 권한 부여는 사이트 관리자만 한다.
--   - 교적 권한자와 권한을 다루는 관리자는 2단계 인증(aal2)이 필요하다 (설계 §9 결정 2).
--   - 기록에 실패하면 작업도 실패한다 (fail-closed). 기존 audit_logs 와 다르다.
--   - 기록은 3년 보관 후 매월 자동 삭제한다 (접속기록 2년·권한 이력 3년 이상 의무).
--
-- 한계
--   - 권한이 없어 거절된 호출은 트랜잭션째 되돌려지므로 접속기록에 남지 않는다 (API 로그에는 남는다).

create schema if not exists registry;
create schema if not exists privacy;
revoke all on schema registry from public;
revoke all on schema privacy from public;
-- anon·authenticated 에는 USAGE 를 주지 않는다 → 테이블·함수에 직접 닿지 않는다

-- ─────────────────────────────────────────────────────────────
-- 1. 기록 (privacy)
-- ─────────────────────────────────────────────────────────────

-- 접속기록: 누가·언제·어디서·누구의 정보를·무엇을 (안전성 확보조치 기준 제8조)
create table privacy.access_logs (
  id            bigint generated always as identity primary key,
  at            timestamptz not null default now(),
  actor_auth_id uuid,
  actor_user_id uuid,
  actor_name    text,
  ip            text,
  user_agent    text,
  action        text not null check (action in ('search', 'view', 'create', 'update', 'delete', 'export', 'print')),
  fn            text not null,
  target_ids    uuid[] not null default '{}',
  target_count  integer not null default 0,
  detail        jsonb
);
create index access_logs_at_idx on privacy.access_logs (at desc);
create index access_logs_actor_idx on privacy.access_logs (actor_user_id, at desc);
create index access_logs_target_idx on privacy.access_logs using gin (target_ids);

-- 변경기록: 교적 테이블의 변경 전후 값. 교인 카드의 '변경 이력' 탭이 person_id 로 찾는다
create table privacy.change_logs (
  id             bigint generated always as identity primary key,
  at             timestamptz not null default now(),
  table_name     text not null,
  op             text not null,
  person_id      uuid,
  record_id      text,
  actor_auth_id  uuid,
  actor_user_id  uuid,
  actor_name     text,
  old_data       jsonb,
  new_data       jsonb,
  changed_fields text[]
);
create index change_logs_person_idx on privacy.change_logs (person_id, at desc);
create index change_logs_at_idx on privacy.change_logs (at desc);

-- 권한 이력: 부여·변경·해제 (안전성 확보조치 기준 제5조, 3년)
create table privacy.permission_logs (
  id              bigint generated always as identity primary key,
  at              timestamptz not null default now(),
  area            text not null,                -- registry (나중에 finance)
  op              text not null check (op in ('grant', 'change', 'revoke')),
  subject_user_id uuid not null,                -- 사람이 지워져도 기록이 남도록 FK 를 걸지 않는다
  subject_name    text,
  actor_auth_id   uuid,
  actor_user_id   uuid,
  actor_name      text,
  old_value       jsonb,
  new_value       jsonb
);
create index permission_logs_at_idx on privacy.permission_logs (at desc);

alter table privacy.access_logs enable row level security;
alter table privacy.change_logs enable row level security;
alter table privacy.permission_logs enable row level security;

-- 추가만: 수정·삭제·비우기를 막는다. 보관 기간(트리거 인자)이 지난 행을 purge_expired() 가 지우는 것만 예외
create function privacy.forbid_mutation() returns trigger
language plpgsql set search_path = '' as $fn$
begin
  -- NEW/OLD 는 해당 작업일 때만 읽는다 (DELETE 가 아닌 경우 OLD 가 없을 수 있다)
  if tg_op = 'DELETE' and current_setting('privacy.purging', true) = 'on' then
    if (to_jsonb(old) ->> 'at')::timestamptz < now() - tg_argv[0]::interval then
      return old;
    end if;
  end if;
  raise exception '%.% 은(는) 추가만 할 수 있습니다', tg_table_schema, tg_table_name using errcode = '42501';
end
$fn$;

create trigger forbid_mutation before update or delete on privacy.access_logs
  for each row execute function privacy.forbid_mutation('3 years');
create trigger forbid_truncate before truncate on privacy.access_logs
  for each statement execute function privacy.forbid_mutation('3 years');
create trigger forbid_mutation before update or delete on privacy.change_logs
  for each row execute function privacy.forbid_mutation('3 years');
create trigger forbid_truncate before truncate on privacy.change_logs
  for each statement execute function privacy.forbid_mutation('3 years');
create trigger forbid_mutation before update or delete on privacy.permission_logs
  for each row execute function privacy.forbid_mutation('3 years');
create trigger forbid_truncate before truncate on privacy.permission_logs
  for each statement execute function privacy.forbid_mutation('3 years');

create function privacy.purge_expired() returns void
language plpgsql security definer set search_path = '' as $fn$
begin
  perform set_config('privacy.purging', 'on', true);
  delete from privacy.access_logs where at < now() - interval '3 years';
  delete from privacy.change_logs where at < now() - interval '3 years';
  delete from privacy.permission_logs where at < now() - interval '3 years';
  perform set_config('privacy.purging', 'off', true);
end
$fn$;

-- 매월 2일 03:30 KST
select cron.schedule('privacy-purge-expired', '30 18 1 * *', 'select privacy.purge_expired()');

-- 접속기록 쓰기. IP·브라우저는 PostgREST 가 넘겨주는 요청 헤더에서 읽는다
create function privacy.log_access(
  p_action text, p_fn text, p_targets uuid[] default '{}', p_detail jsonb default null
) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  h  jsonb := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb;
  me record;
begin
  select u.id, u.name into me from public.custom_users u where u.auth_id = auth.uid();
  insert into privacy.access_logs
    (actor_auth_id, actor_user_id, actor_name, ip, user_agent, action, fn, target_ids, target_count, detail)
  values
    (auth.uid(), me.id, me.name,
     coalesce(h ->> 'cf-connecting-ip',
              nullif(btrim(split_part(h ->> 'x-forwarded-for', ',', 1)), ''),
              h ->> 'x-real-ip'),
     left(h ->> 'user-agent', 300),
     p_action, p_fn, coalesce(p_targets, '{}'), coalesce(cardinality(p_targets), 0), p_detail);
end
$fn$;

-- 변경기록 트리거. 교적 테이블에 붙인다(마이그레이션 ②). 예외 처리를 하지 않으므로 기록이 실패하면 저장도 실패한다
create function privacy.log_change() returns trigger
language plpgsql security definer set search_path = '' as $fn$
declare
  o       jsonb;
  n       jsonb;
  r       jsonb;
  changed text[];
  me      record;
begin
  if tg_op <> 'INSERT' then o := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then n := to_jsonb(new); end if;
  r := coalesce(n, o);
  if tg_op = 'UPDATE' then
    select array_agg(k order by k) into changed
      from jsonb_object_keys(n) as k
     where k <> 'updated_at' and n -> k is distinct from o -> k;
    if changed is null then
      return new;  -- 실제로 바뀐 값이 없으면 남기지 않는다
    end if;
  end if;
  select u.id, u.name into me from public.custom_users u where u.auth_id = auth.uid();
  insert into privacy.change_logs
    (table_name, op, person_id, record_id, actor_auth_id, actor_user_id, actor_name, old_data, new_data, changed_fields)
  values
    (tg_table_schema || '.' || tg_table_name, tg_op, (r ->> 'person_id')::uuid,
     coalesce(r ->> 'id', r ->> 'person_id'), auth.uid(), me.id, me.name, o, n, changed);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$fn$;

-- ─────────────────────────────────────────────────────────────
-- 2. 교적 권한·설정 (registry)
-- ─────────────────────────────────────────────────────────────

create table registry.settings (
  id           boolean primary key default true check (id),
  require_mfa  boolean not null default true,   -- 장애 대응용 스위치. 평소에는 켜 둔다
  idle_minutes integer not null default 30 check (idle_minutes between 5 and 240),
  updated_at   timestamptz not null default now()
);
insert into registry.settings default values;
alter table registry.settings enable row level security;

-- 교적 담당자. scope='communities' 는 나중에 공동체별 담당으로 바꿀 때를 위해 남겨 둔다(1단계는 전부 'all', 설계 §9 결정 1)
create table registry.staff (
  user_id       uuid primary key references public.custom_users(id) on delete cascade,
  scope         text not null default 'all' check (scope in ('all', 'communities')),
  community_ids bigint[] not null default '{}',
  can_edit      boolean not null default false,  -- 등록·수정·상태 처리
  can_export    boolean not null default false,  -- 내려받기·출력
  can_pastoral  boolean not null default false,  -- 심방 (2단계)
  note          text,
  granted_by    uuid,
  granted_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (scope = 'all' or cardinality(community_ids) > 0)
);
alter table registry.staff enable row level security;

create function registry.log_staff_change() returns trigger
language plpgsql security definer set search_path = '' as $fn$
declare
  o    jsonb;
  n    jsonb;
  subj uuid;
  me   record;
begin
  if tg_op <> 'INSERT' then o := to_jsonb(old) - 'updated_at'; subj := old.user_id; end if;
  if tg_op <> 'DELETE' then n := to_jsonb(new) - 'updated_at'; subj := new.user_id; end if;
  if tg_op = 'UPDATE' and o = n then
    return new;  -- 같은 값으로 다시 저장한 경우
  end if;
  select u.id, u.name into me from public.custom_users u where u.auth_id = auth.uid();
  insert into privacy.permission_logs
    (area, op, subject_user_id, subject_name, actor_auth_id, actor_user_id, actor_name, old_value, new_value)
  values
    ('registry',
     case tg_op when 'INSERT' then 'grant' when 'UPDATE' then 'change' else 'revoke' end,
     subj, (select u.name from public.custom_users u where u.id = subj),
     auth.uid(), me.id, me.name, o, n);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$fn$;

create trigger staff_permission_log after insert or update or delete on registry.staff
  for each row execute function registry.log_staff_change();

-- 2단계 인증 확인. 프론트는 hint = 'mfa_required' 로 인증 화면에 보낸다
create function registry.require_mfa() returns void
language plpgsql stable security definer set search_path = '' as $fn$
begin
  if coalesce((select s.require_mfa from registry.settings s), true)
     and coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' then
    raise exception '2단계 인증이 필요합니다' using errcode = '42501', hint = 'mfa_required';
  end if;
end
$fn$;

-- 교적 함수의 첫 줄. 권한이 없으면 예외, 있으면 담당자 행을 돌려준다.
-- p_need: view(검색·열람) / edit(등록·수정) / export(내려받기·출력) / pastoral(심방)
create function registry.require(p_need text default 'view') returns registry.staff
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
  perform registry.require_mfa();
  if (p_need = 'edit' and not s.can_edit)
     or (p_need = 'export' and not s.can_export)
     or (p_need = 'pastoral' and not s.can_pastoral) then
    raise exception '이 작업을 할 권한이 없습니다' using errcode = '42501';
  end if;
  return s;
end
$fn$;

-- 교적 권한을 다루고 접속기록을 보는 사람: 사이트 관리자 + 2단계 인증
create function registry.require_admin() returns void
language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not public.app_is_admin() then
    raise exception '사이트 관리자만 할 수 있습니다' using errcode = '42501';
  end if;
  perform registry.require_mfa();
end
$fn$;

revoke all on all functions in schema registry from public;
revoke all on all functions in schema privacy from public;

-- ─────────────────────────────────────────────────────────────
-- 3. 화면이 부르는 함수 (public)
-- ─────────────────────────────────────────────────────────────

-- 내 교적 권한. 메뉴 표시와 2단계 인증 안내용이다. 교인 정보가 없으므로 기록하지 않는다
create function public.registry_me() returns jsonb
language plpgsql stable security definer set search_path = '' as $fn$
declare
  s   registry.staff;
  cfg registry.settings;
begin
  select * into s from registry.staff st where st.user_id = public.app_current_user_id();
  select * into cfg from registry.settings;
  return jsonb_build_object(
    'is_staff',     s.user_id is not null,
    'is_admin',     public.app_is_admin(),
    'can_edit',     coalesce(s.can_edit, false),
    'can_export',   coalesce(s.can_export, false),
    'can_pastoral', coalesce(s.can_pastoral, false),
    'mfa_required', coalesce(cfg.require_mfa, true),
    'aal',          coalesce(auth.jwt() ->> 'aal', 'aal1'),
    'idle_minutes', coalesce(cfg.idle_minutes, 30)
  );
end
$fn$;

create function public.registry_staff_list()
returns table (user_id uuid, name text, office text, can_edit boolean, can_export boolean,
               can_pastoral boolean, note text, granted_at timestamptz, granted_by_name text)
language plpgsql stable security definer set search_path = '' as $fn$
begin
  perform registry.require_admin();
  return query
    select s.user_id, u.name, u.office, s.can_edit, s.can_export, s.can_pastoral, s.note, s.granted_at, g.name
      from registry.staff s
      join public.custom_users u on u.id = s.user_id
      left join public.custom_users g on g.id = s.granted_by
     order by u.name;
end
$fn$;

create function public.registry_staff_set(
  p_user_id uuid, p_can_edit boolean, p_can_export boolean, p_can_pastoral boolean, p_note text default null
) returns void
language plpgsql security definer set search_path = '' as $fn$
begin
  perform registry.require_admin();
  if not exists (select 1 from public.custom_users u where u.id = p_user_id and u.active) then
    raise exception '가입한 계정에만 교적 권한을 줄 수 있습니다' using errcode = '22023';
  end if;
  insert into registry.staff (user_id, can_edit, can_export, can_pastoral, note, granted_by)
  values (p_user_id, coalesce(p_can_edit, false), coalesce(p_can_export, false),
          coalesce(p_can_pastoral, false), p_note, public.app_current_user_id())
  on conflict (user_id) do update
     set can_edit     = excluded.can_edit,
         can_export   = excluded.can_export,
         can_pastoral = excluded.can_pastoral,
         note         = excluded.note,
         granted_by   = excluded.granted_by,
         updated_at   = now();
end
$fn$;

create function public.registry_staff_remove(p_user_id uuid) returns void
language plpgsql security definer set search_path = '' as $fn$
begin
  perform registry.require_admin();
  delete from registry.staff s where s.user_id = p_user_id;
end
$fn$;

-- 접속기록 열람. 열람한 것도 기록한다
create function public.privacy_access_logs(
  p_from timestamptz default null, p_to timestamptz default null,
  p_actor uuid default null, p_target uuid default null,
  p_limit integer default 100, p_offset integer default 0
) returns table (id bigint, at timestamptz, actor_name text, ip text, user_agent text, action text,
                 fn text, target_count integer, target_names text[], detail jsonb)
language plpgsql security definer set search_path = '' as $fn$
#variable_conflict use_column
begin
  perform registry.require_admin();
  perform privacy.log_access('view', 'privacy_access_logs',
    case when p_target is null then '{}'::uuid[] else array[p_target] end,
    jsonb_build_object('from', p_from, 'to', p_to, 'actor', p_actor, 'target', p_target,
                       'limit', p_limit, 'offset', p_offset));
  return query
    select l.id, l.at, l.actor_name, l.ip, l.user_agent, l.action, l.fn, l.target_count,
           (select array_agg(t.name)
              from (select u.name from public.custom_users u
                     where u.id = any (l.target_ids) order by u.name limit 20) t),
           l.detail
      from privacy.access_logs l
     where (p_from is null or l.at >= p_from)
       and (p_to is null or l.at < p_to)
       and (p_actor is null or l.actor_user_id = p_actor)
       and (p_target is null or l.target_ids @> array[p_target])
     order by l.at desc, l.id desc
     limit least(greatest(coalesce(p_limit, 100), 1), 500)
    offset greatest(coalesce(p_offset, 0), 0);
end
$fn$;

create function public.privacy_permission_logs(p_limit integer default 100, p_offset integer default 0)
returns table (id bigint, at timestamptz, area text, op text, subject_name text, actor_name text,
               old_value jsonb, new_value jsonb)
language plpgsql stable security definer set search_path = '' as $fn$
#variable_conflict use_column
begin
  perform registry.require_admin();
  return query
    select l.id, l.at, l.area, l.op, l.subject_name, l.actor_name, l.old_value, l.new_value
      from privacy.permission_logs l
     order by l.at desc, l.id desc
     limit least(greatest(coalesce(p_limit, 100), 1), 500)
    offset greatest(coalesce(p_offset, 0), 0);
end
$fn$;

-- public 함수는 기본값으로 anon 에게도 실행 권한이 붙는다 → 로그인 사용자만
revoke all on function public.registry_me() from public, anon;
revoke all on function public.registry_staff_list() from public, anon;
revoke all on function public.registry_staff_set(uuid, boolean, boolean, boolean, text) from public, anon;
revoke all on function public.registry_staff_remove(uuid) from public, anon;
revoke all on function public.privacy_access_logs(timestamptz, timestamptz, uuid, uuid, integer, integer) from public, anon;
revoke all on function public.privacy_permission_logs(integer, integer) from public, anon;
grant execute on function public.registry_me() to authenticated;
grant execute on function public.registry_staff_list() to authenticated;
grant execute on function public.registry_staff_set(uuid, boolean, boolean, boolean, text) to authenticated;
grant execute on function public.registry_staff_remove(uuid) to authenticated;
grant execute on function public.privacy_access_logs(timestamptz, timestamptz, uuid, uuid, integer, integer) to authenticated;
grant execute on function public.privacy_permission_logs(integer, integer) to authenticated;

notify pgrst, 'reload schema';

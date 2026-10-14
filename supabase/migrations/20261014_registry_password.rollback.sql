-- 20261014_registry_password 되돌리기. 2단계 인증(인증 앱)으로 돌아간다.
-- 적용 전 운영 상태는 2단계 인증 스위치를 끈 상태였다(2026-10-14, 인증 앱 등록도 지움). 그대로 꺼 둔다.
-- 'auth' 접속기록은 지울 수 없으므로 action 제약은 기존 행을 검사하지 않는다(not valid)

drop function if exists public.registry_password_set(text);
drop function if exists public.registry_unlock(text);
drop function if exists public.registry_touch();
drop function if exists public.registry_lock();
drop function if exists public.registry_password_reset(uuid);

alter table registry.settings add column require_mfa boolean not null default true;  -- 장애 대응용 스위치. 평소에는 켜 둔다
update registry.settings set require_mfa = false where id;

create function registry.require_mfa() returns void
language plpgsql stable security definer set search_path = '' as $fn$
begin
  if coalesce((select s.require_mfa from registry.settings s), true)
     and coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' then
    raise exception '2단계 인증이 필요합니다' using errcode = '42501', hint = 'mfa_required';
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
  perform registry.require_mfa();
  if (p_need = 'edit' and not s.can_edit)
     or (p_need = 'export' and not s.can_export)
     or (p_need = 'pastoral' and not s.can_pastoral) then
    raise exception '이 작업을 할 권한이 없습니다' using errcode = '42501';
  end if;
  return s;
end
$fn$;

create or replace function registry.require_admin() returns void
language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not public.app_is_admin() then
    raise exception '사이트 관리자만 할 수 있습니다' using errcode = '42501';
  end if;
  perform registry.require_mfa();
end
$fn$;

create or replace function public.registry_me() returns jsonb
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

drop function public.registry_staff_list();
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
revoke all on function public.registry_staff_list() from public, anon;
grant execute on function public.registry_staff_list() to authenticated;

drop function registry.require_unlock();
drop function registry.unlocked();
drop function registry.can_enter();
drop function registry.password_problem(text);
drop function registry.open_session();
drop function registry.session_id();
drop table registry.unlocks;
drop table registry.passwords;
alter table registry.settings drop column require_password;

alter table privacy.access_logs drop constraint access_logs_action_check;
alter table privacy.access_logs add constraint access_logs_action_check
  check (action in ('search', 'view', 'create', 'update', 'delete', 'export', 'print')) not valid;

revoke all on all functions in schema registry from public;

notify pgrst, 'reload schema';

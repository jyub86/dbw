-- 교적 본체 (2026-10-11): 교적·세대·이력 테이블, 화면용 함수, 가입 병합·앱 탈퇴 변경
--
-- 설계: docs/church-admin/02-registry-design.md §3, §5, §6
-- 앞: 20261010_registry_foundation (권한·기록)   다음: 20261011_registry_seed (기존 프로필에서 초기 교적 생성)
--
-- 지키는 것
--   - 교적 행이 생기면 그 사람 행(custom_users)은 지울 수 없다(RESTRICT). 그래서 함께 바꾼다.
--       · 가입 병합(merge_user_data): 미가입 프로필의 교적·목장·출석을 가입자 행으로 옮긴 뒤 프로필을 지운다.
--         로그인 계정이 있는 행에서만 돈다(담당자가 미가입 프로필을 고쳐도 다른 프로필과 합쳐지지 않는다).
--       · 앱 탈퇴: Edge Function delete-account 가 account_delete_prepare() 를 먼저 부른다.
--         교적·목장·출석 기록이 있으면 계정 연결만 끊고, 없으면 지금처럼 행을 지운다(설계 §9 결정 4).
--         → 이 마이그레이션을 적용한 뒤, 초기 교적을 만들기 전에 delete-account 를 새로 배포해야 한다.
--   - 가입 환영 메시지는 로그인 계정이 있는 행에만 보낸다(담당자가 만드는 미가입 프로필에는 보내지 않는다).
--   - 화면은 public.registry_* 함수만 부른다. 모든 함수가 registry.require() 로 권한·2단계 인증을 확인하고
--     privacy.log_access() 로 접속기록을 남긴다. 교적 테이블의 변경은 privacy.change_logs 에 남는다.
--
-- 값의 뜻
--   재적 상태: active 재적 / hold 보류 / transferred 전출 / deceased 별세 / removed 제적
--   신급:     baptized 세례교인 / infant_baptized 유아세례교인 / catechumen 학습교인 / seeker 원입교인 / unknown 미확인

-- ─────────────────────────────────────────────────────────────
-- 1. 테이블
-- ─────────────────────────────────────────────────────────────

-- 교회가 이름을 바꿀 수 있는 목록. relation 의 'self'(본인 = 세대주)는 동작에 쓰이므로 코드를 바꾸지 않는다
create table registry.codes (
  category   text not null,
  code       text not null,
  label      text not null,
  title      text,                         -- 직분의 표시 호칭 (custom_users.office 에 들어가는 값)
  sort_order integer not null default 0,   -- 직분은 작을수록 높다
  active     boolean not null default true,
  primary key (category, code)
);
insert into registry.codes (category, code, label, title, sort_order) values
  ('office',   'pastor',          '목사',     '목사',     10),
  ('office',   'evangelist',      '전도사',   '전도사',   20),
  ('office',   'elder',           '장로',     '장로',     30),
  ('office',   'ordained_deacon', '시무집사', '시무집사', 40),  -- 이 교회는 '안수집사' 대신 '시무집사'로 부른다
  ('office',   'kwonsa',          '권사',     '권사',     50),
  ('office',   'deacon',          '서리집사', '집사',     60),
  ('relation', 'self',            '본인',     null, 10),
  ('relation', 'spouse',          '배우자',   null, 20),
  ('relation', 'child',           '자녀',     null, 30),
  ('relation', 'parent',          '부모',     null, 40),
  ('relation', 'daughter_in_law', '며느리',   null, 50),
  ('relation', 'son_in_law',      '사위',     null, 60),
  ('relation', 'grandchild',      '손자녀',   null, 70),
  ('relation', 'sibling',         '형제자매', null, 80),
  ('relation', 'other',           '기타',     null, 90),
  ('marital',  'single',          '미혼',     null, 10),
  ('marital',  'married',         '기혼',     null, 20),
  ('marital',  'widowed',         '사별',     null, 30),
  ('marital',  'other',           '기타',     null, 40);

-- 교적 (사람당 1행). 이름·전화·성별·생년월일·호칭은 custom_users 에 그대로 둔다
create table registry.people (
  person_id        uuid primary key references public.custom_users(id) on delete restrict,
  reg_no           text unique,            -- 교번. 처음에는 비워 두고 재정을 시작할 때 매긴다(설계 §9 결정 7)
  name_note        text,                   -- 동명이인 구분 표시
  birth_lunar      boolean not null default false,
  address_zip      text,
  address1         text,
  address2         text,                   -- 개인 주소. 비어 있으면 세대 주소를 쓴다
  occupation       text,
  workplace        text,
  marital_status   text,
  wedding_date     date,
  previous_church  text,
  guide_person_id  uuid references public.custom_users(id) on delete set null,
  guide_name       text,
  sms_opt_out      boolean not null default false,
  faith_checked_on date,                   -- 신급을 확인한 날. 학습·세례 기록이 없을 때 원입/미확인을 가른다
  note             text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  updated_by       uuid
);

create table registry.households (
  id           bigint generated always as identity primary key,
  household_no text unique,
  address_zip  text,
  address1     text,
  address2     text,
  home_phone   text,
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- 세대원. 교인이면 person_id, 교인이 아닌 가족이면 이름·출생연도만
create table registry.household_members (
  id           bigint generated always as identity primary key,
  household_id bigint not null references registry.households(id) on delete cascade,
  person_id    uuid unique references registry.people(person_id) on delete restrict on update cascade,
  name         text,
  birth_year   integer check (birth_year between 1900 and 2100),
  relation     text not null,
  sort_order   integer not null default 0,
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (person_id is not null or nullif(btrim(name), '') is not null)
);
create unique index household_members_one_self on registry.household_members (household_id) where relation = 'self';
create index household_members_household_idx on registry.household_members (household_id);

-- 아래 하위 테이블은 모두 people 을 ON UPDATE CASCADE 로 참조한다
-- → 가입 병합 때 people.person_id 한 줄만 바꾸면 이력이 전부 따라간다
create table registry.status_events (
  id          bigint generated always as identity primary key,
  person_id   uuid not null references registry.people(person_id) on delete cascade on update cascade,
  kind        text not null check (kind in ('register', 'transfer_in', 'restore', 'hold', 'transfer_out', 'deceased', 'removed')),
  event_date  date,                        -- 비어 있으면 날짜 미상 (초기 생성한 '등록')
  reason      text,
  church_name text,
  created_by  uuid,
  created_at  timestamptz not null default now()
);
create index status_events_person_idx on registry.status_events (person_id, event_date, id);

create table registry.faith_events (
  id          bigint generated always as identity primary key,
  person_id   uuid not null references registry.people(person_id) on delete cascade on update cascade,
  kind        text not null check (kind in ('catechumen', 'baptism', 'infant_baptism', 'confirmation')),
  event_date  date,
  church_name text,                        -- 비면 본 교회
  officiant   text,
  note        text,
  created_by  uuid,
  created_at  timestamptz not null default now()
);
create index faith_events_person_idx on registry.faith_events (person_id);

create table registry.office_terms (
  id         bigint generated always as identity primary key,
  person_id  uuid not null references registry.people(person_id) on delete cascade on update cascade,
  office     text not null,
  standing   text not null default 'serving'
             check (standing in ('serving', 'retired', 'emeritus', 'honorary', 'cooperating', 'resigned')),
  started_on date,
  ended_on   date,
  note       text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ended_on is null or started_on is null or ended_on >= started_on)
);
create index office_terms_person_idx on registry.office_terms (person_id);

create table registry.notes (
  id         bigint generated always as identity primary key,
  person_id  uuid not null references registry.people(person_id) on delete cascade on update cascade,
  body       text not null check (btrim(body) <> ''),
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index notes_person_idx on registry.notes (person_id, created_at desc);

create table registry.consents (
  id             bigint generated always as identity primary key,
  person_id      uuid not null references registry.people(person_id) on delete cascade on update cascade,
  kind           text not null check (kind in ('registry', 'sensitive', 'directory', 'guardian')),
  notice_version text,
  granted_on     date not null default current_date,
  method         text not null default 'paper' check (method in ('paper', 'app', 'verbal')),
  guardian_name  text,
  revoked_on     date,
  note           text,
  recorded_by    uuid,
  created_at     timestamptz not null default now()
);
create index consents_person_idx on registry.consents (person_id);

-- 가입 병합 때 양쪽 모두 교적이 있어서 합치지 못한 경우
create table registry.merge_conflicts (
  id          bigint generated always as identity primary key,
  account_id  uuid not null,              -- 가입한 사람 행
  profile_id  uuid not null,              -- 이름·전화가 같은 미가입 프로필
  detected_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid,
  note        text
);

alter table registry.codes enable row level security;
alter table registry.people enable row level security;
alter table registry.households enable row level security;
alter table registry.household_members enable row level security;
alter table registry.status_events enable row level security;
alter table registry.faith_events enable row level security;
alter table registry.office_terms enable row level security;
alter table registry.notes enable row level security;
alter table registry.consents enable row level security;
alter table registry.merge_conflicts enable row level security;

create function registry.touch() returns trigger
language plpgsql set search_path = '' as $fn$
begin
  new.updated_at := now();
  return new;
end
$fn$;

create trigger touch before update on registry.people for each row execute function registry.touch();
create trigger touch before update on registry.households for each row execute function registry.touch();
create trigger touch before update on registry.household_members for each row execute function registry.touch();
create trigger touch before update on registry.office_terms for each row execute function registry.touch();
create trigger touch before update on registry.notes for each row execute function registry.touch();

create trigger log_change after insert or update or delete on registry.people
  for each row execute function privacy.log_change();
create trigger log_change after insert or update or delete on registry.households
  for each row execute function privacy.log_change();
create trigger log_change after insert or update or delete on registry.household_members
  for each row execute function privacy.log_change();
create trigger log_change after insert or update or delete on registry.status_events
  for each row execute function privacy.log_change();
create trigger log_change after insert or update or delete on registry.faith_events
  for each row execute function privacy.log_change();
create trigger log_change after insert or update or delete on registry.office_terms
  for each row execute function privacy.log_change();
create trigger log_change after insert or update or delete on registry.notes
  for each row execute function privacy.log_change();
create trigger log_change after insert or update or delete on registry.consents
  for each row execute function privacy.log_change();

-- ─────────────────────────────────────────────────────────────
-- 2. 계산 (현재 상태·신급·직분·목장)
-- ─────────────────────────────────────────────────────────────

create function registry.status_of_kind(k text) returns text
language sql immutable set search_path = '' as $fn$
  select case k
    when 'register' then 'active' when 'transfer_in' then 'active' when 'restore' then 'active'
    when 'hold' then 'hold' when 'transfer_out' then 'transferred'
    when 'deceased' then 'deceased' when 'removed' then 'removed' end
$fn$;

create view registry.summary as
select p.person_id,
       (select registry.status_of_kind(e.kind)
          from registry.status_events e
         where e.person_id = p.person_id
         order by e.event_date desc nulls last, e.id desc
         limit 1) as status,
       case
         when exists (select 1 from registry.faith_events f
                       where f.person_id = p.person_id and f.kind in ('baptism', 'confirmation')) then 'baptized'
         when exists (select 1 from registry.faith_events f
                       where f.person_id = p.person_id and f.kind = 'infant_baptism') then 'infant_baptized'
         when exists (select 1 from registry.faith_events f
                       where f.person_id = p.person_id and f.kind = 'catechumen') then 'catechumen'
         when p.faith_checked_on is not null then 'seeker'
         else 'unknown'
       end as faith,
       o.office, o.standing,
       (select min(e.event_date) from registry.status_events e
         where e.person_id = p.person_id and e.kind in ('register', 'transfer_in')) as registered_on,
       g.community_id, g.community_name, g.group_id, g.group_name
  from registry.people p
  left join lateral (
    select t.office, t.standing
      from registry.office_terms t
      join registry.codes c on c.category = 'office' and c.code = t.office
     where t.person_id = p.person_id and t.ended_on is null and t.standing <> 'resigned'
     order by c.sort_order
     limit 1) o on true
  left join lateral (
    select s.community_id, cm.name as community_name, s.id as group_id, s.name as group_name
      from public.small_group_members m
      join public.small_groups s on s.id = m.small_group_id
      join public.communities cm on cm.id = s.community_id
     where m.user_id = p.person_id and m.active and s.active
     order by cm.sort_order, s.sort_order, s.id
     limit 1) g on true;

-- ─────────────────────────────────────────────────────────────
-- 3. 내부 도우미
-- ─────────────────────────────────────────────────────────────

create function registry.assert_person(p_person_id uuid) returns void
language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not exists (select 1 from registry.people p where p.person_id = p_person_id) then
    raise exception '교적에 없는 사람입니다' using errcode = 'P0002';
  end if;
end
$fn$;

create function registry.assert_code(p_category text, p_code text) returns void
language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not exists (select 1 from registry.codes c where c.category = p_category and c.code = p_code) then
    raise exception '알 수 없는 값입니다: % = %', p_category, p_code using errcode = '22023';
  end if;
end
$fn$;

-- custom_users 쪽 변경을 변경기록에 남긴다 (custom_users 에는 변경기록 트리거가 없다)
create function registry.log_profile_change(p_person_id uuid, p_op text, p_old jsonb, p_new jsonb) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  changed text[];
  me      record;
begin
  select array_agg(k order by k) into changed
    from (select jsonb_object_keys(coalesce(p_new, '{}') || coalesce(p_old, '{}')) as k) x
   where p_new -> k is distinct from p_old -> k;
  if changed is null and p_op = 'UPDATE' then
    return;
  end if;
  select u.id, u.name into me from public.custom_users u where u.auth_id = auth.uid();
  insert into privacy.change_logs
    (table_name, op, person_id, record_id, actor_auth_id, actor_user_id, actor_name, old_data, new_data, changed_fields)
  values
    ('public.custom_users', p_op, p_person_id, p_person_id::text, auth.uid(), me.id, me.name, p_old, p_new, changed);
end
$fn$;

-- 재적 상태 → 앱의 교인 인증 (재적·보류 = 교인, 설계 §9 결정 3)
create function registry.sync_member(p_person_id uuid) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  want boolean;
  cur  boolean;
begin
  select s.status in ('active', 'hold') into want from registry.summary s where s.person_id = p_person_id;
  select u.member into cur from public.custom_users u where u.id = p_person_id;
  if want is null or want is not distinct from cur then
    return;
  end if;
  update public.custom_users set member = want where id = p_person_id;
  perform registry.log_profile_change(p_person_id, 'UPDATE',
    jsonb_build_object('member', cur), jsonb_build_object('member', want));
end
$fn$;

-- 직분 이력 → 앱의 표시 호칭. 직분 이력이 없는 사람의 호칭(성도·사모·아동 구분)은 건드리지 않는다
create function registry.sync_office(p_person_id uuid) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  want text;
  cur  text;
begin
  select case t.standing
           when 'serving' then c.title
           else (case t.standing when 'retired' then '은퇴' when 'emeritus' then '원로'
                                 when 'honorary' then '명예' when 'cooperating' then '협동' else '' end)
                || replace(c.title, '시무', '')
         end
    into want
    from registry.office_terms t
    join registry.codes c on c.category = 'office' and c.code = t.office
   where t.person_id = p_person_id and t.ended_on is null and t.standing <> 'resigned'
   order by c.sort_order
   limit 1;
  select u.office into cur from public.custom_users u where u.id = p_person_id;
  if want is null then
    -- 맡은 직분이 없어졌다: 지금 호칭이 직분 호칭일 때만 '성도'로 되돌린다
    if exists (select 1 from registry.codes c where c.category = 'office' and c.title = cur)
       or cur ~ '^(은퇴|원로|명예|협동)' then
      want := '성도';
    else
      return;
    end if;
  end if;
  if want is distinct from cur then
    update public.custom_users set office = want where id = p_person_id;
    perform registry.log_profile_change(p_person_id, 'UPDATE',
      jsonb_build_object('office', cur), jsonb_build_object('office', want));
  end if;
end
$fn$;

-- 지금 호칭이 직분이면 직분 이력 한 건으로 만든다 (초기 생성·기존 사람 교적 등록)
create function registry.office_from_profile(p_person_id uuid) returns void
language sql security definer set search_path = '' as $fn$
  insert into registry.office_terms (person_id, office, standing, note)
  select p_person_id, c.code, 'serving', '기존 프로필 호칭에서 가져옴'
    from public.custom_users u
    join registry.codes c on c.category = 'office' and c.title = u.office
   where u.id = p_person_id
     and not exists (select 1 from registry.office_terms t where t.person_id = p_person_id)
$fn$;

-- 두 사람 행을 하나로 합친다. p_keep = 가입한 계정 행, p_drop = 미가입 프로필 (지워진다)
-- 양쪽 다 교적이 있으면 합치지 않고 merge_conflicts 에 남긴다
create function registry.merge_people(p_keep uuid, p_drop uuid) returns text
language plpgsql security definer set search_path = '' as $fn$
declare
  k public.custom_users;
  d public.custom_users;
  keep_had_registry boolean;
  m record;
begin
  select * into k from public.custom_users where id = p_keep for update;
  select * into d from public.custom_users where id = p_drop for update;
  if k.id is null or d.id is null or k.id = d.id then
    raise exception '합칠 두 사람을 찾지 못했습니다' using errcode = 'P0002';
  end if;

  keep_had_registry := exists (select 1 from registry.people p where p.person_id = p_keep);
  if keep_had_registry and exists (select 1 from registry.people p where p.person_id = p_drop) then
    if not exists (select 1 from registry.merge_conflicts c
                    where c.account_id = p_keep and c.profile_id = p_drop and c.resolved_at is null) then
      insert into registry.merge_conflicts (account_id, profile_id) values (p_keep, p_drop);
    end if;
    return 'conflict';
  end if;

  -- (1) 목장 소속. 같은 목장에 양쪽 다 있으면 미가입 쪽의 출석·특이사항을 가입자 쪽 소속으로 옮긴다
  for m in
    select dm.id as drop_mid, km.id as keep_mid
      from public.small_group_members dm
      join public.small_group_members km on km.small_group_id = dm.small_group_id and km.user_id = p_keep
     where dm.user_id = p_drop
  loop
    update public.attendance_records r set member_id = m.keep_mid
     where r.member_id = m.drop_mid
       and not exists (select 1 from public.attendance_records x where x.member_id = m.keep_mid and x.session_id = r.session_id);
    update public.member_notes n set member_id = m.keep_mid
     where n.member_id = m.drop_mid
       and not exists (select 1 from public.member_notes x where x.member_id = m.keep_mid and x.session_id = n.session_id);
  end loop;
  update public.small_group_members g set user_id = p_keep
   where g.user_id = p_drop
     and not exists (select 1 from public.small_group_members x where x.small_group_id = g.small_group_id and x.user_id = p_keep);

  -- (2) 그 밖의 참조
  update public.attendance_records set recorded_by = p_keep where recorded_by = p_drop;
  update public.member_notes set created_by = p_keep where created_by = p_drop;
  update public.group_session_notes set created_by = p_keep where created_by = p_drop;
  update public.member_vehicles v set user_id = p_keep
   where v.user_id = p_drop
     and not exists (select 1 from public.member_vehicles x where x.user_id = p_keep and x.plate_norm = v.plate_norm);
  update public.user_groups g set user_id = k.auth_id
   where g.user_id = d.auth_id
     and not exists (select 1 from public.user_groups x where x.user_id = k.auth_id and x.group_id = g.group_id);

  -- (3) 교적. 하위 이력은 ON UPDATE CASCADE 로 따라온다
  update registry.people set person_id = p_keep where person_id = p_drop;
  update registry.people set guide_person_id = p_keep where guide_person_id = p_drop;

  -- (4) 미가입 프로필 삭제
  delete from public.custom_users where id = p_drop;

  -- (5) 값 합치기. 가입자 쪽에 이미 교적이 있었다면 교적이 기준이므로 호칭·교인 인증은 그대로 둔다
  if keep_had_registry then
    update public.custom_users
       set active = true,
           gender = coalesce(gender, d.gender),
           birth_date = coalesce(birth_date, d.birth_date)
     where id = p_keep;
  else
    update public.custom_users
       set active = true,
           gender = coalesce(d.gender, gender),
           birth_date = coalesce(d.birth_date, birth_date),
           office = d.office,
           member = d.member
     where id = p_keep;
  end if;

  -- 병합 기록: 교인 카드의 변경 이력이 옛 프로필의 기록까지 이어서 보여 줄 수 있게
  perform registry.log_profile_change(p_keep, 'MERGE',
    jsonb_build_object('profile_id', p_drop, 'name', d.name, 'office', d.office, 'member', d.member),
    jsonb_build_object('account_id', p_keep));

  -- (6) 가입 완료 메시지
  insert into public.messages (receiver_id, title, message, message_type, sender_id)
  values (k.auth_id, '가입 완료',
          coalesce(k.name, d.name, '') || coalesce(d.office, '') || '님, 부평동부교회 애플리케이션 가입이 완료되었습니다!',
          'personal', 'aaa3a5de-67d1-4e47-80dd-f972407681af');
  return 'merged';
end
$fn$;

revoke all on all functions in schema registry from public;

-- ─────────────────────────────────────────────────────────────
-- 4. 기존 흐름 변경: 가입 병합, 가입 환영 메시지
-- ─────────────────────────────────────────────────────────────

create or replace function public.merge_user_data() returns trigger
language plpgsql security definer set search_path to 'public' as $function$
declare
  inactive_user record;
  new_phone_norm text;
begin
  -- 이름·전화가 그대로면 병합 시도 안 함
  if NEW.name is not distinct from OLD.name and NEW.phone is not distinct from OLD.phone then
    return NEW;
  end if;

  -- 로그인 계정이 있는 행(가입자)만. 담당자가 미가입 프로필을 고칠 때는 합치지 않는다
  if not exists (select 1 from auth.users a where a.id = NEW.auth_id) then
    return NEW;
  end if;

  -- 전화번호 정규화(숫자만). 비어있거나 이름이 없으면 병합 대상 없음.
  new_phone_norm := regexp_replace(coalesce(NEW.phone, ''), '[^0-9]', '', 'g');
  if new_phone_norm = '' or NEW.name is null or btrim(NEW.name) = '' then
    return NEW;
  end if;

  -- 이름+전화(정규화) 일치하는 미가입 프로필 검색 (자기 자신 제외)
  select * into inactive_user
    from public.custom_users
   where active = false
     and id <> NEW.id
     and btrim(name) = btrim(NEW.name)
     and regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g') = new_phone_norm
   limit 1;

  if found then
    perform registry.merge_people(NEW.id, inactive_user.id);
  end if;
  return NEW;
end;
$function$;

create or replace function public.welcome_new_user() returns trigger
language plpgsql security definer set search_path to 'public' as $function$
begin
  -- 담당자가 만드는 미가입 프로필(로그인 계정 없음)에는 보내지 않는다
  if not exists (select 1 from auth.users a where a.id = NEW.auth_id) then
    return NEW;
  end if;
  insert into public.messages(receiver_id, title, message, message_type, sender_id)
  values (
    NEW.auth_id,
    '환영합니다!',
    coalesce(nullif(btrim(NEW.name), ''), '회원') || '님, 부평동부교회 앱에 가입하신 것을 진심으로 환영합니다. 더보기에서 이름과 전화번호 및 프로필 사진을 업데이트 해주세요. 신속하게 가입 절차를 진행해 드리겠습니다.',
    'personal',
    'aaa3a5de-67d1-4e47-80dd-f972407681af'
  );
  return NEW;
end;
$function$;

-- 정보공개를 끌 때 글·댓글을 숨기는 기존 트리거. search_path 가 지정돼 있지 않아서, search_path 를 비운
-- 함수(아래 account_delete_prepare) 안에서 불리면 posts 를 찾지 못하고 실패한다 → public 으로 고정한다
alter function public.update_active_status_when_update_user_info() set search_path = public;

-- 앱 탈퇴 준비 (Edge Function delete-account 가 서비스 롤로 부른다)
--   교적·목장·출석 기록이 있으면 계정 연결만 끊는다 → 'unlinked'
--   없으면 지금처럼 사람 행을 지운다 → 'deleted'
-- 로그인 계정(auth.users) 삭제는 Edge Function 이 이어서 한다
create function public.account_delete_prepare(p_auth_id uuid) returns text
language plpgsql security definer set search_path = '' as $fn$
declare
  u public.custom_users;
begin
  select * into u from public.custom_users where auth_id = p_auth_id;
  if not found then
    return 'none';
  end if;

  if not (exists (select 1 from registry.people p where p.person_id = u.id)
          or exists (select 1 from public.small_group_members g where g.user_id = u.id)
          or exists (select 1 from public.attendance_records r where r.recorded_by = u.id)
          or exists (select 1 from public.member_notes n where n.created_by = u.id)
          or exists (select 1 from public.group_session_notes n where n.created_by = u.id)) then
    delete from public.custom_users where id = u.id;
    return 'deleted';
  end if;

  -- 앱 데이터: 지금 CASCADE 로 지워지던 것과 같다. auth_id 를 참조하므로 auth_id 를 바꾸기 전에 지운다
  delete from public.likes where user_id = p_auth_id;
  delete from public.comments where user_id = p_auth_id;
  delete from public.posts where user_id = p_auth_id;
  update public.inquiries set answered_by = null where answered_by = p_auth_id;
  delete from public.inquiries where user_id = p_auth_id;
  delete from public.user_groups where user_id = p_auth_id;
  -- 권한: 로그인할 수 없으므로 의미가 없다 (교적 권한 해제는 권한 이력에 남는다)
  delete from registry.staff where user_id = u.id;
  delete from public.attendance_managers where user_id = u.id;
  delete from public.attendance_stat_viewers where user_id = u.id;
  delete from public.education_report_editors where user_id = u.id;
  delete from public.export_users where user_id = u.id;
  delete from public.parking_managers where user_id = u.id;

  update public.custom_users
     set auth_id = gen_random_uuid(),
         active = false,
         role = 4,
         email = null,
         profile_picture = null,
         privacy_consented_at = null,
         is_info_public = false
   where id = u.id;

  perform registry.log_profile_change(u.id, 'UNLINK',
    jsonb_build_object('auth_id', p_auth_id, 'active', u.active, 'role', u.role),
    jsonb_build_object('active', false, 'role', 4));
  return 'unlinked';
end
$fn$;

revoke all on function public.account_delete_prepare(uuid) from public, anon, authenticated;
grant execute on function public.account_delete_prepare(uuid) to service_role;

-- ─────────────────────────────────────────────────────────────
-- 5. 화면이 부르는 함수 — 조회
-- ─────────────────────────────────────────────────────────────

create function public.registry_codes()
returns table (category text, code text, label text, title text, sort_order integer)
language plpgsql stable security definer set search_path = '' as $fn$
#variable_conflict use_column
begin
  perform registry.require('view');
  return query
    select c.category, c.code, c.label, c.title, c.sort_order
      from registry.codes c where c.active order by c.category, c.sort_order, c.code;
end
$fn$;

-- 교인 검색. p_filters 키:
--   q (이름 여러 개를 쉼표·공백으로, 숫자면 전화번호도), status[], faith[], office[] ('none' = 직분 없음),
--   community_id, group_id, gender, age_min, age_max, registered_from, registered_to, has_account
create function public.registry_search(p_filters jsonb default '{}', p_limit integer default 50, p_offset integer default 0)
returns table (person_id uuid, name text, name_note text, gender text, birth_date date, phone text, office text,
               status text, faith text, community_id bigint, community_name text, group_id bigint, group_name text,
               has_account boolean, registered_on date, total bigint)
language plpgsql security definer set search_path = '' as $fn$
#variable_conflict use_column
declare
  f     jsonb := coalesce(p_filters, '{}');
  terms text[];
  ids   uuid[];
  tot   bigint;
begin
  perform registry.require('view');
  select array_agg(t) into terms
    from (select btrim(x) as t from regexp_split_to_table(coalesce(f ->> 'q', ''), '[,\s]+') x) y
   where t <> '';

  select array_agg(b.person_id order by b.sort_name, b.person_id), max(b.total)
    into ids, tot
    from (
      select s.person_id, coalesce(u.name, '') as sort_name, count(*) over () as total
        from registry.summary s
        join public.custom_users u on u.id = s.person_id
       where (terms is null or exists (
               select 1 from unnest(terms) t
                where u.name ilike '%' || t || '%'
                   or (t ~ '^[0-9-]{4,}$'
                       and regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g') like '%' || replace(t, '-', '') || '%')))
         and (not f ? 'status' or s.status in (select jsonb_array_elements_text(f -> 'status')))
         and (not f ? 'faith' or s.faith in (select jsonb_array_elements_text(f -> 'faith')))
         and (not f ? 'office' or coalesce(s.office, 'none') in (select jsonb_array_elements_text(f -> 'office')))
         and (f ->> 'community_id' is null or s.community_id = (f ->> 'community_id')::bigint)
         and (f ->> 'group_id' is null or s.group_id = (f ->> 'group_id')::bigint)
         and (f ->> 'gender' is null or u.gender = f ->> 'gender')
         and (f ->> 'age_min' is null or extract(year from age(current_date, u.birth_date)) >= (f ->> 'age_min')::int)
         and (f ->> 'age_max' is null or extract(year from age(current_date, u.birth_date)) <= (f ->> 'age_max')::int)
         and (f ->> 'registered_from' is null or s.registered_on >= (f ->> 'registered_from')::date)
         and (f ->> 'registered_to' is null or s.registered_on <= (f ->> 'registered_to')::date)
         and (f ->> 'has_account' is null
              or exists (select 1 from auth.users a where a.id = u.auth_id) = (f ->> 'has_account')::boolean)
       order by coalesce(u.name, ''), s.person_id
       limit least(greatest(coalesce(p_limit, 50), 1), 500)
      offset greatest(coalesce(p_offset, 0), 0)) b;

  perform privacy.log_access('search', 'registry_search', coalesce(ids, '{}'),
    jsonb_build_object('filters', f, 'limit', p_limit, 'offset', p_offset, 'total', coalesce(tot, 0)));

  return query
    select s.person_id, u.name, p.name_note, u.gender, u.birth_date, u.phone, u.office,
           s.status, s.faith, s.community_id, s.community_name, s.group_id, s.group_name,
           exists (select 1 from auth.users a where a.id = u.auth_id), s.registered_on, coalesce(tot, 0)
      from registry.summary s
      join registry.people p on p.person_id = s.person_id
      join public.custom_users u on u.id = s.person_id
     where s.person_id = any (coalesce(ids, '{}'))
     order by array_position(ids, s.person_id);
end
$fn$;

-- 교적 카드 한 장
create function public.registry_card(p_person_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare
  hh_id   bigint;
  targets uuid[];
  merged  uuid[];
  result  jsonb;
begin
  perform registry.require('view');
  perform registry.assert_person(p_person_id);

  select hm.household_id into hh_id from registry.household_members hm where hm.person_id = p_person_id;
  select array_agg(distinct x) into targets
    from (select p_person_id as x
          union all select hm.person_id from registry.household_members hm
                     where hm.household_id = hh_id and hm.person_id is not null) y;
  -- 가입 병합으로 합쳐진 옛 프로필의 기록도 이어서 보여 준다
  select array_agg((l.old_data ->> 'profile_id')::uuid) into merged
    from privacy.change_logs l
   where l.person_id = p_person_id and l.op = 'MERGE';

  select jsonb_build_object(
    'person', jsonb_build_object(
        'person_id', u.id, 'name', u.name, 'phone', u.phone, 'gender', u.gender, 'birth_date', u.birth_date,
        'office', u.office, 'photo', u.profile_picture, 'email', u.email, 'member', u.member,
        'has_account', exists (select 1 from auth.users a where a.id = u.auth_id))
      || (to_jsonb(p) - 'person_id'),
    'summary', to_jsonb(s) - 'person_id',
    'guide', (select g.name from public.custom_users g where g.id = p.guide_person_id),
    'groups', (select coalesce(jsonb_agg(jsonb_build_object(
                  'group_id', sg.id, 'group_name', sg.name, 'community_name', cm.name, 'role', m.role,
                  'active', m.active and sg.active, 'joined_at', m.joined_at)
                  order by (m.active and sg.active) desc, cm.sort_order, sg.sort_order), '[]')
                 from public.small_group_members m
                 join public.small_groups sg on sg.id = m.small_group_id
                 join public.communities cm on cm.id = sg.community_id
                where m.user_id = p_person_id),
    'household', (select jsonb_build_object(
                    'id', h.id, 'household_no', h.household_no, 'address_zip', h.address_zip,
                    'address1', h.address1, 'address2', h.address2, 'home_phone', h.home_phone, 'note', h.note,
                    'members', (select coalesce(jsonb_agg(jsonb_build_object(
                                   'id', hm.id, 'person_id', hm.person_id, 'name', coalesce(cu.name, hm.name),
                                   'relation', hm.relation, 'office', cu.office,
                                   'birth_year', coalesce(extract(year from cu.birth_date)::int, hm.birth_year),
                                   'note', hm.note) order by hm.sort_order, hm.id), '[]')
                                  from registry.household_members hm
                                  left join public.custom_users cu on cu.id = hm.person_id
                                 where hm.household_id = h.id))
                    from registry.households h where h.id = hh_id),
    'status_events', (select coalesce(jsonb_agg(to_jsonb(e) - 'person_id'
                         order by e.event_date nulls first, e.id), '[]')
                        from registry.status_events e where e.person_id = p_person_id),
    'faith_events', (select coalesce(jsonb_agg(to_jsonb(e) - 'person_id'
                        order by e.event_date nulls first, e.id), '[]')
                       from registry.faith_events e where e.person_id = p_person_id),
    'office_terms', (select coalesce(jsonb_agg((to_jsonb(t) - 'person_id') || jsonb_build_object('label', c.label)
                        order by t.started_on nulls first, t.id), '[]')
                       from registry.office_terms t
                       left join registry.codes c on c.category = 'office' and c.code = t.office
                      where t.person_id = p_person_id),
    'notes', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', n.id, 'body', n.body, 'created_at', n.created_at, 'author', a.name)
                 order by n.created_at desc), '[]')
                from registry.notes n left join public.custom_users a on a.id = n.created_by
               where n.person_id = p_person_id),
    'consents', (select coalesce(jsonb_agg(to_jsonb(c) - 'person_id' order by c.granted_on, c.id), '[]')
                   from registry.consents c where c.person_id = p_person_id),
    'history', (select coalesce(jsonb_agg(jsonb_build_object(
                   'at', l.at, 'table', l.table_name, 'op', l.op, 'actor', l.actor_name,
                   'fields', l.changed_fields, 'old', l.old_data, 'new', l.new_data) order by l.at desc, l.id desc), '[]')
                  from (select * from privacy.change_logs l
                         where l.person_id = p_person_id or l.person_id = any (coalesce(merged, '{}'))
                         order by l.at desc, l.id desc limit 200) l)
  ) into result
  from registry.people p
  join public.custom_users u on u.id = p.person_id
  join registry.summary s on s.person_id = p.person_id
  where p.person_id = p_person_id;

  perform privacy.log_access('view', 'registry_card', targets, null);
  return result;
end
$fn$;

-- 교적에 아직 없는 사람 중 확인이 필요한 사람 (설계 §8)
--   no_group: 교인 표시는 있지만 목장에 없음 / left_group: 목장 명단에서 빠짐 / not_member: 목장에 있지만 교인 인증 전
create function public.registry_candidates()
returns table (person_id uuid, name text, office text, member boolean, has_account boolean, group_name text, reason text)
language plpgsql security definer set search_path = '' as $fn$
#variable_conflict use_column
declare
  reasons jsonb;
begin
  perform registry.require('view');
  select jsonb_object_agg(x.id, x.reason) into reasons
    from (select u.id,
                 case
                   when u.member and not exists (select 1 from public.small_group_members g where g.user_id = u.id) then 'no_group'
                   when u.member then 'left_group'
                   else 'not_member'
                 end as reason
            from public.custom_users u
           where not exists (select 1 from registry.people p where p.person_id = u.id)
             and u.member <> exists (
                   select 1 from public.small_group_members g join public.small_groups s on s.id = g.small_group_id
                    where g.user_id = u.id and g.active and s.active)) x;
  -- 위 조건: 교인인데 지금 목장이 없거나(no_group·left_group), 목장에 있는데 교인 인증 전(not_member)
  perform privacy.log_access('search', 'registry_candidates',
    (select coalesce(array_agg(k::uuid), '{}') from jsonb_object_keys(coalesce(reasons, '{}')) k), null);
  return query
    select u.id, u.name, u.office, u.member,
           exists (select 1 from auth.users a where a.id = u.auth_id),
           (select s.name from public.small_group_members g join public.small_groups s on s.id = g.small_group_id
             where g.user_id = u.id order by g.active desc, s.sort_order limit 1),
           reasons ->> u.id::text
      from public.custom_users u
     where reasons ? u.id::text
     order by reasons ->> u.id::text, u.name;
end
$fn$;

-- 새가족 등록 전에 같은 이름이나 전화번호가 있는지 (교적 여부와 상관없이 사람 전체에서)
create function public.registry_find_similar(p_name text, p_phone text default null)
returns table (person_id uuid, name text, office text, phone text, has_account boolean, in_registry boolean, group_name text)
language plpgsql security definer set search_path = '' as $fn$
#variable_conflict use_column
declare
  digits text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  ids    uuid[];
begin
  perform registry.require('view');
  select array_agg(u.id) into ids
    from public.custom_users u
   where (nullif(btrim(p_name), '') is not null and btrim(u.name) = btrim(p_name))
      or (length(digits) >= 8 and regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g') = digits);
  perform privacy.log_access('search', 'registry_find_similar', coalesce(ids, '{}'),
    jsonb_build_object('name', p_name, 'has_phone', length(digits) >= 8));
  return query
    select u.id, u.name, u.office, u.phone,
           exists (select 1 from auth.users a where a.id = u.auth_id),
           exists (select 1 from registry.people p where p.person_id = u.id),
           (select s.name from public.small_group_members g join public.small_groups s on s.id = g.small_group_id
             where g.user_id = u.id and g.active order by s.sort_order limit 1)
      from public.custom_users u where u.id = any (coalesce(ids, '{}'))
     order by u.name;
end
$fn$;

create function public.registry_merge_conflicts()
returns table (id bigint, detected_at timestamptz, account_id uuid, account_name text, profile_id uuid, profile_name text)
language plpgsql security definer set search_path = '' as $fn$
#variable_conflict use_column
begin
  perform registry.require('view');
  perform privacy.log_access('search', 'registry_merge_conflicts',
    (select coalesce(array_agg(x), '{}') from (select c.account_id as x from registry.merge_conflicts c where c.resolved_at is null
                                                 union select c.profile_id from registry.merge_conflicts c where c.resolved_at is null) y),
    null);
  return query
    select c.id, c.detected_at, c.account_id, a.name, c.profile_id, p.name
      from registry.merge_conflicts c
      left join public.custom_users a on a.id = c.account_id
      left join public.custom_users p on p.id = c.profile_id
     where c.resolved_at is null
     order by c.detected_at;
end
$fn$;

-- ─────────────────────────────────────────────────────────────
-- 6. 화면이 부르는 함수 — 등록·수정
-- ─────────────────────────────────────────────────────────────

-- 새가족 등록: 미가입 사람 행 + 교적 + '등록' 이벤트를 한 번에 만든다
--   p: name(필수), phone, gender('남'/'여'), birth_date, birth_lunar, registered_on(기본 오늘), office(직분 코드),
--      address_zip, address1, address2, occupation, workplace, marital_status, wedding_date,
--      previous_church, guide_person_id, guide_name, note
create function public.registry_register(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $fn$
declare
  v_id    uuid;
  v_name  text := nullif(btrim(p ->> 'name'), '');
  v_title text;
begin
  perform registry.require('edit');
  if v_name is null then
    raise exception '이름을 넣어 주세요' using errcode = '22023';
  end if;
  if nullif(p ->> 'gender', '') is not null and p ->> 'gender' not in ('남', '여') then
    raise exception '성별은 남 또는 여입니다' using errcode = '22023';
  end if;
  if nullif(p ->> 'office', '') is not null then
    perform registry.assert_code('office', p ->> 'office');
    select c.title into v_title from registry.codes c where c.category = 'office' and c.code = p ->> 'office';
  end if;
  if nullif(p ->> 'marital_status', '') is not null then
    perform registry.assert_code('marital', p ->> 'marital_status');
  end if;

  insert into public.custom_users (name, phone, gender, birth_date, office, member, active)
  values (v_name, nullif(btrim(p ->> 'phone'), ''), nullif(p ->> 'gender', ''),
          nullif(p ->> 'birth_date', '')::date, coalesce(v_title, '성도'), true, false)
  returning id into v_id;
  perform registry.log_profile_change(v_id, 'INSERT', null,
    jsonb_build_object('name', v_name, 'phone', nullif(btrim(p ->> 'phone'), ''), 'gender', nullif(p ->> 'gender', ''),
                       'birth_date', nullif(p ->> 'birth_date', ''), 'office', coalesce(v_title, '성도'), 'member', true));

  insert into registry.people (person_id, birth_lunar, address_zip, address1, address2, occupation, workplace,
                               marital_status, wedding_date, previous_church, guide_person_id, guide_name, note, updated_by)
  values (v_id, coalesce((p ->> 'birth_lunar')::boolean, false), p ->> 'address_zip', p ->> 'address1', p ->> 'address2',
          p ->> 'occupation', p ->> 'workplace', nullif(p ->> 'marital_status', ''),
          nullif(p ->> 'wedding_date', '')::date, p ->> 'previous_church',
          nullif(p ->> 'guide_person_id', '')::uuid, p ->> 'guide_name', p ->> 'note', public.app_current_user_id());
  insert into registry.status_events (person_id, kind, event_date, reason, created_by)
  values (v_id, 'register', coalesce(nullif(p ->> 'registered_on', '')::date, current_date), '새가족 등록',
          public.app_current_user_id());
  if v_title is not null then
    insert into registry.office_terms (person_id, office, standing, started_on, created_by)
    values (v_id, p ->> 'office', 'serving', nullif(p ->> 'office_started_on', '')::date, public.app_current_user_id());
  end if;

  perform privacy.log_access('create', 'registry_register', array[v_id], null);
  return v_id;
end
$fn$;

-- 이미 있는 사람(앱 가입자, 출석부 프로필)을 교적에 올린다
create function public.registry_enroll(p_person_id uuid, p_registered_on date default null, p_note text default null)
returns void
language plpgsql security definer set search_path = '' as $fn$
begin
  perform registry.require('edit');
  if not exists (select 1 from public.custom_users u where u.id = p_person_id) then
    raise exception '사람을 찾지 못했습니다' using errcode = 'P0002';
  end if;
  if exists (select 1 from registry.people p where p.person_id = p_person_id) then
    raise exception '이미 교적에 있습니다' using errcode = '23505';
  end if;
  insert into registry.people (person_id, note, updated_by) values (p_person_id, p_note, public.app_current_user_id());
  insert into registry.status_events (person_id, kind, event_date, reason, created_by)
  values (p_person_id, 'register', p_registered_on, '기존 사람을 교적에 등록', public.app_current_user_id());
  perform registry.office_from_profile(p_person_id);
  perform registry.sync_member(p_person_id);
  perform privacy.log_access('create', 'registry_enroll', array[p_person_id], null);
end
$fn$;

-- 잘못 만든 교적을 지운다 (중복 등). 교인이 떠난 것은 지우지 말고 전출·제적으로 처리한다
create function public.registry_unenroll(p_person_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $fn$
begin
  perform registry.require('edit');
  perform registry.assert_person(p_person_id);
  if nullif(btrim(p_reason), '') is null then
    raise exception '지우는 이유를 넣어 주세요' using errcode = '22023';
  end if;
  delete from registry.household_members where person_id = p_person_id;
  delete from registry.households h where not exists (select 1 from registry.household_members m where m.household_id = h.id);
  delete from registry.people where person_id = p_person_id;
  perform privacy.log_access('delete', 'registry_unenroll', array[p_person_id], jsonb_build_object('reason', p_reason));
end
$fn$;

-- 인적사항 수정. 넣은 키만 바꾼다(값을 null 로 넣으면 비운다)
create function public.registry_save(p_person_id uuid, p_patch jsonb) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  p        jsonb := coalesce(p_patch, '{}');
  profile  text[] := array['name', 'phone', 'gender', 'birth_date'];
  reg      text[] := array['name_note', 'birth_lunar', 'address_zip', 'address1', 'address2', 'occupation', 'workplace',
                           'marital_status', 'wedding_date', 'previous_church', 'guide_person_id', 'guide_name',
                           'sms_opt_out', 'faith_checked_on', 'note'];
  bad      text[];
  old_prof jsonb;
  new_prof jsonb;
begin
  perform registry.require('edit');
  perform registry.assert_person(p_person_id);
  select array_agg(k) into bad from jsonb_object_keys(p) k where not (k = any (profile) or k = any (reg));
  if bad is not null then
    raise exception '고칠 수 없는 항목입니다: %', array_to_string(bad, ', ') using errcode = '22023';
  end if;
  if p ? 'name' and nullif(btrim(p ->> 'name'), '') is null then
    raise exception '이름은 비울 수 없습니다' using errcode = '22023';
  end if;
  if nullif(p ->> 'gender', '') is not null and p ->> 'gender' not in ('남', '여') then
    raise exception '성별은 남 또는 여입니다' using errcode = '22023';
  end if;
  if nullif(p ->> 'marital_status', '') is not null then
    perform registry.assert_code('marital', p ->> 'marital_status');
  end if;

  if p ?| profile then
    select jsonb_build_object('name', u.name, 'phone', u.phone, 'gender', u.gender, 'birth_date', u.birth_date)
      into old_prof from public.custom_users u where u.id = p_person_id;
    update public.custom_users u
       set name       = case when p ? 'name' then btrim(p ->> 'name') else u.name end,
           phone      = case when p ? 'phone' then nullif(btrim(p ->> 'phone'), '') else u.phone end,
           gender     = case when p ? 'gender' then nullif(p ->> 'gender', '') else u.gender end,
           birth_date = case when p ? 'birth_date' then nullif(p ->> 'birth_date', '')::date else u.birth_date end
     where u.id = p_person_id;
    select jsonb_build_object('name', u.name, 'phone', u.phone, 'gender', u.gender, 'birth_date', u.birth_date)
      into new_prof from public.custom_users u where u.id = p_person_id;
    perform registry.log_profile_change(p_person_id, 'UPDATE', old_prof, new_prof);
  end if;

  if p ?| reg then
    update registry.people r
       set name_note        = case when p ? 'name_note' then p ->> 'name_note' else r.name_note end,
           birth_lunar      = case when p ? 'birth_lunar' then coalesce((p ->> 'birth_lunar')::boolean, false) else r.birth_lunar end,
           address_zip      = case when p ? 'address_zip' then p ->> 'address_zip' else r.address_zip end,
           address1         = case when p ? 'address1' then p ->> 'address1' else r.address1 end,
           address2         = case when p ? 'address2' then p ->> 'address2' else r.address2 end,
           occupation       = case when p ? 'occupation' then p ->> 'occupation' else r.occupation end,
           workplace        = case when p ? 'workplace' then p ->> 'workplace' else r.workplace end,
           marital_status   = case when p ? 'marital_status' then nullif(p ->> 'marital_status', '') else r.marital_status end,
           wedding_date     = case when p ? 'wedding_date' then nullif(p ->> 'wedding_date', '')::date else r.wedding_date end,
           previous_church  = case when p ? 'previous_church' then p ->> 'previous_church' else r.previous_church end,
           guide_person_id  = case when p ? 'guide_person_id' then nullif(p ->> 'guide_person_id', '')::uuid else r.guide_person_id end,
           guide_name       = case when p ? 'guide_name' then p ->> 'guide_name' else r.guide_name end,
           sms_opt_out      = case when p ? 'sms_opt_out' then coalesce((p ->> 'sms_opt_out')::boolean, false) else r.sms_opt_out end,
           faith_checked_on = case when p ? 'faith_checked_on' then nullif(p ->> 'faith_checked_on', '')::date else r.faith_checked_on end,
           note             = case when p ? 'note' then p ->> 'note' else r.note end,
           updated_by       = public.app_current_user_id()
     where r.person_id = p_person_id;
  end if;

  perform privacy.log_access('update', 'registry_save', array[p_person_id],
    jsonb_build_object('fields', (select jsonb_agg(k) from jsonb_object_keys(p) k)));
end
$fn$;

-- 재적 상태
create function public.registry_add_status(
  p_person_id uuid, p_kind text, p_date date, p_reason text default null, p_church text default null
) returns bigint
language plpgsql security definer set search_path = '' as $fn$
declare
  v_id bigint;
begin
  perform registry.require('edit');
  perform registry.assert_person(p_person_id);
  if p_date is null then
    raise exception '날짜를 넣어 주세요' using errcode = '22023';
  end if;
  insert into registry.status_events (person_id, kind, event_date, reason, church_name, created_by)
  values (p_person_id, p_kind, p_date, p_reason, p_church, public.app_current_user_id())
  returning id into v_id;
  perform registry.sync_member(p_person_id);
  perform privacy.log_access('update', 'registry_add_status', array[p_person_id], jsonb_build_object('kind', p_kind));
  return v_id;
end
$fn$;

create function public.registry_delete_status(p_event_id bigint) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  v_person uuid;
begin
  perform registry.require('edit');
  select e.person_id into v_person from registry.status_events e where e.id = p_event_id;
  if v_person is null then
    raise exception '기록을 찾지 못했습니다' using errcode = 'P0002';
  end if;
  if (select count(*) from registry.status_events e where e.person_id = v_person) <= 1 then
    raise exception '마지막 재적 기록은 지울 수 없습니다' using errcode = '22023';
  end if;
  delete from registry.status_events where id = p_event_id;
  perform registry.sync_member(v_person);
  perform privacy.log_access('update', 'registry_delete_status', array[v_person], jsonb_build_object('event_id', p_event_id));
end
$fn$;

-- 신급
create function public.registry_add_faith(
  p_person_id uuid, p_kind text, p_date date default null, p_church text default null,
  p_officiant text default null, p_note text default null
) returns bigint
language plpgsql security definer set search_path = '' as $fn$
declare
  v_id bigint;
begin
  perform registry.require('edit');
  perform registry.assert_person(p_person_id);
  insert into registry.faith_events (person_id, kind, event_date, church_name, officiant, note, created_by)
  values (p_person_id, p_kind, p_date, p_church, p_officiant, p_note, public.app_current_user_id())
  returning id into v_id;
  perform privacy.log_access('update', 'registry_add_faith', array[p_person_id], jsonb_build_object('kind', p_kind));
  return v_id;
end
$fn$;

create function public.registry_delete_faith(p_event_id bigint) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  v_person uuid;
begin
  perform registry.require('edit');
  select e.person_id into v_person from registry.faith_events e where e.id = p_event_id;
  if v_person is null then
    raise exception '기록을 찾지 못했습니다' using errcode = 'P0002';
  end if;
  delete from registry.faith_events where id = p_event_id;
  perform privacy.log_access('update', 'registry_delete_faith', array[v_person], jsonb_build_object('event_id', p_event_id));
end
$fn$;

-- 직분. 새 직분을 넣으면 맡고 있던 직분은 그 날짜로 끝난다
create function public.registry_add_office(
  p_person_id uuid, p_office text, p_standing text default 'serving', p_started_on date default null, p_note text default null
) returns bigint
language plpgsql security definer set search_path = '' as $fn$
declare
  v_id  bigint;
  v_end date := coalesce(p_started_on, current_date);
begin
  perform registry.require('edit');
  perform registry.assert_person(p_person_id);
  perform registry.assert_code('office', p_office);
  update registry.office_terms t
     set ended_on = greatest(v_end, coalesce(t.started_on, v_end))
   where t.person_id = p_person_id and t.ended_on is null;
  insert into registry.office_terms (person_id, office, standing, started_on, note, created_by)
  values (p_person_id, p_office, coalesce(p_standing, 'serving'), p_started_on, p_note, public.app_current_user_id())
  returning id into v_id;
  perform registry.sync_office(p_person_id);
  perform privacy.log_access('update', 'registry_add_office', array[p_person_id],
    jsonb_build_object('office', p_office, 'standing', p_standing));
  return v_id;
end
$fn$;

create function public.registry_end_office(p_term_id bigint, p_ended_on date default null) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  v_person uuid;
begin
  perform registry.require('edit');
  select t.person_id into v_person from registry.office_terms t where t.id = p_term_id;
  if v_person is null then
    raise exception '기록을 찾지 못했습니다' using errcode = 'P0002';
  end if;
  update registry.office_terms set ended_on = coalesce(p_ended_on, current_date) where id = p_term_id;
  perform registry.sync_office(v_person);
  perform privacy.log_access('update', 'registry_end_office', array[v_person], jsonb_build_object('term_id', p_term_id));
end
$fn$;

create function public.registry_delete_office(p_term_id bigint) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  v_person uuid;
begin
  perform registry.require('edit');
  select t.person_id into v_person from registry.office_terms t where t.id = p_term_id;
  if v_person is null then
    raise exception '기록을 찾지 못했습니다' using errcode = 'P0002';
  end if;
  delete from registry.office_terms where id = p_term_id;
  perform registry.sync_office(v_person);
  perform privacy.log_access('update', 'registry_delete_office', array[v_person], jsonb_build_object('term_id', p_term_id));
end
$fn$;

-- 메모
create function public.registry_add_note(p_person_id uuid, p_body text) returns bigint
language plpgsql security definer set search_path = '' as $fn$
declare
  v_id bigint;
begin
  perform registry.require('edit');
  perform registry.assert_person(p_person_id);
  insert into registry.notes (person_id, body, created_by) values (p_person_id, p_body, public.app_current_user_id())
  returning id into v_id;
  perform privacy.log_access('update', 'registry_add_note', array[p_person_id], null);
  return v_id;
end
$fn$;

create function public.registry_delete_note(p_note_id bigint) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  v_person uuid;
begin
  perform registry.require('edit');
  select n.person_id into v_person from registry.notes n where n.id = p_note_id;
  if v_person is null then
    raise exception '메모를 찾지 못했습니다' using errcode = 'P0002';
  end if;
  delete from registry.notes where id = p_note_id;
  perform privacy.log_access('update', 'registry_delete_note', array[v_person], jsonb_build_object('note_id', p_note_id));
end
$fn$;

-- 동의 기록 (새가족 등록카드의 서면 동의 등)
create function public.registry_add_consent(
  p_person_id uuid, p_kind text, p_granted_on date default null, p_method text default 'paper',
  p_notice_version text default null, p_guardian_name text default null, p_note text default null
) returns bigint
language plpgsql security definer set search_path = '' as $fn$
declare
  v_id bigint;
begin
  perform registry.require('edit');
  perform registry.assert_person(p_person_id);
  insert into registry.consents (person_id, kind, granted_on, method, notice_version, guardian_name, note, recorded_by)
  values (p_person_id, p_kind, coalesce(p_granted_on, current_date), coalesce(p_method, 'paper'),
          p_notice_version, p_guardian_name, p_note, public.app_current_user_id())
  returning id into v_id;
  perform privacy.log_access('update', 'registry_add_consent', array[p_person_id], jsonb_build_object('kind', p_kind));
  return v_id;
end
$fn$;

create function public.registry_revoke_consent(p_consent_id bigint, p_revoked_on date default null) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  v_person uuid;
begin
  perform registry.require('edit');
  select c.person_id into v_person from registry.consents c where c.id = p_consent_id;
  if v_person is null then
    raise exception '동의 기록을 찾지 못했습니다' using errcode = 'P0002';
  end if;
  update registry.consents set revoked_on = coalesce(p_revoked_on, current_date) where id = p_consent_id;
  perform privacy.log_access('update', 'registry_revoke_consent', array[v_person], jsonb_build_object('consent_id', p_consent_id));
end
$fn$;

-- 세대
create function public.registry_household_create(p_head uuid, p_data jsonb default '{}') returns bigint
language plpgsql security definer set search_path = '' as $fn$
declare
  v_id bigint;
  d    jsonb := coalesce(p_data, '{}');
begin
  perform registry.require('edit');
  perform registry.assert_person(p_head);
  if exists (select 1 from registry.household_members m where m.person_id = p_head) then
    raise exception '이미 다른 세대에 속해 있습니다' using errcode = '23505';
  end if;
  insert into registry.households (household_no, address_zip, address1, address2, home_phone, note)
  values (nullif(d ->> 'household_no', ''), d ->> 'address_zip', d ->> 'address1', d ->> 'address2',
          d ->> 'home_phone', d ->> 'note')
  returning id into v_id;
  insert into registry.household_members (household_id, person_id, relation) values (v_id, p_head, 'self');
  perform privacy.log_access('create', 'registry_household_create', array[p_head], jsonb_build_object('household_id', v_id));
  return v_id;
end
$fn$;

create function public.registry_household_update(p_household_id bigint, p_data jsonb) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  d   jsonb := coalesce(p_data, '{}');
  bad text[];
begin
  perform registry.require('edit');
  if not exists (select 1 from registry.households h where h.id = p_household_id) then
    raise exception '세대를 찾지 못했습니다' using errcode = 'P0002';
  end if;
  select array_agg(k) into bad from jsonb_object_keys(d) k
   where k <> all (array['household_no', 'address_zip', 'address1', 'address2', 'home_phone', 'note']);
  if bad is not null then
    raise exception '고칠 수 없는 항목입니다: %', array_to_string(bad, ', ') using errcode = '22023';
  end if;
  update registry.households h
     set household_no = case when d ? 'household_no' then nullif(d ->> 'household_no', '') else h.household_no end,
         address_zip  = case when d ? 'address_zip' then d ->> 'address_zip' else h.address_zip end,
         address1     = case when d ? 'address1' then d ->> 'address1' else h.address1 end,
         address2     = case when d ? 'address2' then d ->> 'address2' else h.address2 end,
         home_phone   = case when d ? 'home_phone' then d ->> 'home_phone' else h.home_phone end,
         note         = case when d ? 'note' then d ->> 'note' else h.note end
   where h.id = p_household_id;
  perform privacy.log_access('update', 'registry_household_update',
    (select coalesce(array_agg(m.person_id), '{}') from registry.household_members m
      where m.household_id = p_household_id and m.person_id is not null),
    jsonb_build_object('household_id', p_household_id));
end
$fn$;

-- 세대원 추가. 교인이면 p_person_id, 교인이 아닌 가족이면 p_name. 다른 세대에 있던 교인은 이 세대로 옮긴다
create function public.registry_household_add(
  p_household_id bigint, p_person_id uuid, p_relation text,
  p_name text default null, p_birth_year integer default null, p_note text default null
) returns bigint
language plpgsql security definer set search_path = '' as $fn$
declare
  v_id  bigint;
  old_m registry.household_members;
begin
  perform registry.require('edit');
  perform registry.assert_code('relation', p_relation);
  if not exists (select 1 from registry.households h where h.id = p_household_id) then
    raise exception '세대를 찾지 못했습니다' using errcode = 'P0002';
  end if;
  if p_relation = 'self' and exists (select 1 from registry.household_members m
                                      where m.household_id = p_household_id and m.relation = 'self') then
    raise exception '세대주(본인)는 한 세대에 한 명입니다' using errcode = '23505';
  end if;

  if p_person_id is not null then
    perform registry.assert_person(p_person_id);
    select * into old_m from registry.household_members m where m.person_id = p_person_id;
    if old_m.id is not null then
      if old_m.household_id = p_household_id then
        raise exception '이미 이 세대에 있습니다' using errcode = '23505';
      end if;
      if old_m.relation = 'self' and exists (select 1 from registry.household_members m
                                              where m.household_id = old_m.household_id and m.id <> old_m.id) then
        raise exception '다른 세대의 세대주입니다. 그 세대의 세대주를 먼저 바꿔 주세요' using errcode = '22023';
      end if;
      delete from registry.household_members where id = old_m.id;
      delete from registry.households h
       where h.id = old_m.household_id
         and not exists (select 1 from registry.household_members m where m.household_id = h.id);
    end if;
    insert into registry.household_members (household_id, person_id, relation, note, sort_order)
    values (p_household_id, p_person_id, p_relation, p_note,
            (select coalesce(max(m.sort_order), 0) + 1 from registry.household_members m where m.household_id = p_household_id))
    returning id into v_id;
  else
    if nullif(btrim(p_name), '') is null then
      raise exception '교인이 아닌 가족은 이름을 넣어 주세요' using errcode = '22023';
    end if;
    insert into registry.household_members (household_id, name, birth_year, relation, note, sort_order)
    values (p_household_id, btrim(p_name), p_birth_year, p_relation, p_note,
            (select coalesce(max(m.sort_order), 0) + 1 from registry.household_members m where m.household_id = p_household_id))
    returning id into v_id;
  end if;

  perform privacy.log_access('update', 'registry_household_add',
    case when p_person_id is null then '{}'::uuid[] else array[p_person_id] end,
    jsonb_build_object('household_id', p_household_id, 'relation', p_relation));
  return v_id;
end
$fn$;

create function public.registry_household_member_update(
  p_member_id bigint, p_relation text default null, p_sort_order integer default null, p_note text default null
) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  m registry.household_members;
begin
  perform registry.require('edit');
  select * into m from registry.household_members x where x.id = p_member_id;
  if m.id is null then
    raise exception '세대원을 찾지 못했습니다' using errcode = 'P0002';
  end if;
  if p_relation is not null then
    perform registry.assert_code('relation', p_relation);
    if p_relation = 'self' and m.relation <> 'self'
       and exists (select 1 from registry.household_members x where x.household_id = m.household_id and x.relation = 'self') then
      raise exception '세대주(본인)는 한 세대에 한 명입니다. 지금 세대주의 관계를 먼저 바꿔 주세요' using errcode = '23505';
    end if;
  end if;
  update registry.household_members
     set relation   = coalesce(p_relation, relation),
         sort_order = coalesce(p_sort_order, sort_order),
         note       = coalesce(p_note, note)
   where id = p_member_id;
  perform privacy.log_access('update', 'registry_household_member_update',
    case when m.person_id is null then '{}'::uuid[] else array[m.person_id] end,
    jsonb_build_object('household_id', m.household_id));
end
$fn$;

create function public.registry_household_remove(p_member_id bigint) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  m registry.household_members;
begin
  perform registry.require('edit');
  select * into m from registry.household_members x where x.id = p_member_id;
  if m.id is null then
    raise exception '세대원을 찾지 못했습니다' using errcode = 'P0002';
  end if;
  if m.relation = 'self' and exists (select 1 from registry.household_members x
                                      where x.household_id = m.household_id and x.id <> m.id) then
    raise exception '세대주는 다른 세대원을 먼저 옮기거나 세대주를 바꾼 뒤 뺄 수 있습니다' using errcode = '22023';
  end if;
  delete from registry.household_members where id = p_member_id;
  delete from registry.households h
   where h.id = m.household_id
     and not exists (select 1 from registry.household_members x where x.household_id = h.id);
  perform privacy.log_access('update', 'registry_household_remove',
    case when m.person_id is null then '{}'::uuid[] else array[m.person_id] end,
    jsonb_build_object('household_id', m.household_id));
end
$fn$;

-- 계정 연결 (수동): 가입한 계정 행(p_account_id)에 교회가 입력해 둔 사람(p_person_id)을 합친다.
-- 자동 병합이 이름·전화가 정확히 맞지 않아 놓친 경우에 쓴다 (설계 §5.1)
create function public.registry_link_account(p_person_id uuid, p_account_id uuid) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  r text;
begin
  perform registry.require('edit');
  if not exists (select 1 from public.custom_users u join auth.users a on a.id = u.auth_id where u.id = p_account_id) then
    raise exception '가입한 계정이 아닙니다' using errcode = '22023';
  end if;
  if exists (select 1 from public.custom_users u join auth.users a on a.id = u.auth_id where u.id = p_person_id) then
    raise exception '두 사람 모두 가입한 계정이라 합칠 수 없습니다' using errcode = '22023';
  end if;
  r := registry.merge_people(p_account_id, p_person_id);
  if r = 'conflict' then
    raise exception '두 사람 모두 교적이 있어 합칠 수 없습니다. 잘못 만든 교적을 먼저 지워 주세요' using errcode = '22023';
  end if;
  perform privacy.log_access('update', 'registry_link_account', array[p_account_id, p_person_id], null);
end
$fn$;

-- ─────────────────────────────────────────────────────────────
-- 7. 실행 권한
-- ─────────────────────────────────────────────────────────────

do $grants$
declare
  f regprocedure;
begin
  for f in
    select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like 'registry\_%'
       and p.proname not in ('registry_me', 'registry_staff_list', 'registry_staff_set', 'registry_staff_remove')
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$grants$;

revoke all on all functions in schema registry from public;

notify pgrst, 'reload schema';

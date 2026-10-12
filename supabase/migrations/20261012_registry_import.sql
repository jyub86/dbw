-- 교적 ③: 디모데 가져오기 (설계 docs/church-admin/02-registry-design.md §12)
--
-- 흐름
--   1. 올리기   registry_import_load    정리본에서 만든 파일을 관리자가 화면에서 올린다 (관리자 + 교적 수정 권한)
--   2. 대조     registry_import_list / registry_import_decide / registry_import_accept
--              올릴 때마다 지금 사람들과 다시 대조한다. 이름+생년월일 또는 이름+전화가 한 사람과만 맞으면 '연결 제안'
--   3. 반영     registry_import_apply   확정한 행만, 비어 있는 칸만 채운다. 이미 있는 값이 다르면 덮어쓰지 않고 차이로 남긴다
--   4. 정리     registry_import_close   올린 행을 지운다 (관리자)
--
-- 올린 행(registry.import_rows)은 API로 열리지 않는 registry 스키마에만 있다.
-- 디모데 메모는 교역자(심방 권한)만 보는 registry.legacy_memos 로 옮긴다. 변경기록 트리거를 달지 않는다:
-- 변경기록은 교적 카드의 '변경 이력'에서 교적 권한자 누구나 보므로 메모 본문이 새어 나간다.

-- ─────────────────────────────────────────────────────────────
-- 1. 테이블
-- ─────────────────────────────────────────────────────────────

create table registry.import_rows (
  id          bigint generated always as identity primary key,
  source      text not null default 'dimode',
  src_id      text not null,                     -- 디모데 교적 ID
  sheet       text not null default 'main' check (sheet in ('main', 'deceased')),  -- deceased = 정리본의 별세자 시트
  data        jsonb not null check (jsonb_typeof(data) = 'object'),  -- 정리한 디모데 값 (메모 제외)
  memo        text,                              -- 디모데 메모. 화면 목록에는 내보내지 않는다
  name_key    text not null,                     -- 공백·괄호·영문 구분기호를 뺀 이름
  birth_date  date,
  phones      text[] not null default '{}',      -- 휴대폰·집전화 (숫자만)
  mobile      text,                              -- 휴대폰 (숫자만)
  candidates  jsonb not null default '[]',       -- [{person_id, kind: strong|name|phone}]
  suggestion  text not null default 'review' check (suggestion in ('link', 'new', 'review')),
  decision    text check (decision in ('link', 'new', 'skip')),
  person_id   uuid references public.custom_users(id) on delete set null,  -- 연결할(반영 뒤에는 연결된) 사람
  decided_by  uuid,
  decided_at  timestamptz,
  applied_at  timestamptz,
  result      jsonb,                             -- 반영 결과 {filled: [...], diffs: [...]}
  uploaded_by uuid,
  uploaded_at timestamptz not null default now(),
  unique (source, src_id)
);
-- 한 사람에게 디모데 행 하나만 연결한다
create unique index import_rows_one_person on registry.import_rows (person_id)
  where person_id is not null and decision in ('link', 'new');

-- 디모데 세대(세대주 ID) → 만든 세대. 나눠서 반영해도 같은 세대로 모이게 한다
create table registry.import_households (
  source        text not null default 'dimode',
  household_src text not null,
  household_id  bigint not null references registry.households(id) on delete cascade,
  primary key (source, household_src)
);

-- 옛 시스템 ID ↔ 사람. 가져오기를 정리한 뒤에도 남는다 (헌금번호는 재정 시작 때 교번 참고용)
create table registry.legacy_links (
  source      text not null,
  src_id      text not null,
  person_id   uuid not null references registry.people(person_id) on delete cascade on update cascade,
  offering_no text,
  linked_by   uuid,
  linked_at   timestamptz not null default now(),
  primary key (source, src_id)
);
create index legacy_links_person_idx on registry.legacy_links (person_id);

-- 옛 시스템 메모. 교역자(심방 권한)만 본다. 고치지 않고 읽기만 한다
create table registry.legacy_memos (
  id         bigint generated always as identity primary key,
  person_id  uuid not null references registry.people(person_id) on delete cascade on update cascade,
  source     text not null,
  src_id     text not null,
  body       text not null check (btrim(body) <> ''),
  created_by uuid,
  created_at timestamptz not null default now(),
  unique (source, src_id)
);
create index legacy_memos_person_idx on registry.legacy_memos (person_id);

alter table registry.import_rows enable row level security;
alter table registry.import_households enable row level security;
alter table registry.legacy_links enable row level security;
alter table registry.legacy_memos enable row level security;

create trigger log_change after insert or update or delete on registry.legacy_links
  for each row execute function privacy.log_change();

-- ─────────────────────────────────────────────────────────────
-- 2. 변환 도우미
-- ─────────────────────────────────────────────────────────────

-- 한글 이름 끝에 붙인 영문 구분기호(디모데의 동명이인 a/b)는 뗀다. 영문만 있는 이름은 그대로 둔다
create function registry.strip_mark(p text) returns text
language sql immutable set search_path = '' as $fn$
  select regexp_replace(btrim(coalesce(p, '')), '([가-힣])\s*[A-Za-z]+$', '\1')
$fn$;

create function registry.name_key(p text) returns text
language sql immutable set search_path = '' as $fn$
  select registry.strip_mark(regexp_replace(regexp_replace(coalesce(p, ''), '\s+', '', 'g'), '\(.*?\)', '', 'g'))
$fn$;

create function registry.digits(p text) returns text
language sql immutable set search_path = '' as $fn$
  select nullif(regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g'), '')
$fn$;

-- 디모데 관계(세대주 기준) → 세대 관계 코드
create function registry.dimode_relation(p text) returns text
language sql immutable set search_path = '' as $fn$
  select case
    when r is null then null
    when r = '본인' then 'self'
    when r in ('처', '남편', '부인', '아내') then 'spouse'
    when r ~ '(손자|손녀|외손)' then 'grandchild'
    when r ~ '(자부|며느리)' then 'daughter_in_law'
    when r ~ '사위' then 'son_in_law'
    when r ~ '^(아들|딸|장남|장녀|차남|차녀|삼남|삼녀|[0-9]+(남|녀))' then 'child'
    when r in ('모', '부', '어머니', '아버지', '장모', '장인', '시모', '시부') then 'parent'
    when r in ('형', '누나', '오빠', '언니', '남동생', '여동생', '동생') then 'sibling'
    else 'other'
  end
  from (select nullif(btrim(p), '') as r) x
$fn$;

-- 디모데 직분·세부직분 → 직분 코드와 신분. 휴직·무임·타교 직분은 아직 코드가 없어 null (차이로 남긴다)
create function registry.dimode_office(p_office text, p_detail text, out code text, out standing text)
language sql immutable set search_path = '' as $fn$
  select m[1], m[2]
    from (select case coalesce(nullif(btrim(p_detail), ''), btrim(p_office))
      when '서리집사'     then array['deacon', 'serving']
      when '집사'         then array['deacon', 'serving']
      when '명예집사'     then array['deacon', 'honorary']
      when '안수집사'     then array['ordained_deacon', 'serving']
      when '시무집사'     then array['ordained_deacon', 'serving']
      when '은퇴안수집사' then array['ordained_deacon', 'retired']
      when '협동안수집사' then array['ordained_deacon', 'cooperating']
      when '권사'         then array['kwonsa', 'serving']
      when '시무권사'     then array['kwonsa', 'serving']
      when '명예권사'     then array['kwonsa', 'honorary']
      when '은퇴권사'     then array['kwonsa', 'retired']
      when '협동권사'     then array['kwonsa', 'cooperating']
      when '장로'         then array['elder', 'serving']
      when '시무장로'     then array['elder', 'serving']
      when '은퇴장로'     then array['elder', 'retired']
      when '전입은퇴장로' then array['elder', 'retired']
      when '원로장로'     then array['elder', 'emeritus']
      when '목사'         then array['pastor', 'serving']
      when '담임목사'     then array['pastor', 'serving']
      when '부목사'       then array['pastor', 'serving']
      when '협동목사'     then array['pastor', 'cooperating']
      when '전도사'       then array['evangelist', 'serving']
      when '교육전도사'   then array['evangelist', 'serving']
      when '전임전도사'   then array['evangelist', 'serving']
      when '심방전도사'   then array['evangelist', 'serving']
    end as m) x
$fn$;

-- 디모데 세례 칸 → 신급 이벤트 종류. '유세'는 유아세례의 줄임. '영세'(천주교)는 사람이 판단하도록 null
create function registry.dimode_faith(p text) returns text
language sql immutable set search_path = '' as $fn$
  select case btrim(coalesce(p, ''))
    when '세례' then 'baptism' when '침례' then 'baptism'
    when '유아세례' then 'infant_baptism' when '유세' then 'infant_baptism'
    when '입교' then 'confirmation' when '학습' then 'catechumen'
  end
$fn$;

create function registry.dimode_marital(p text) returns text
language sql immutable set search_path = '' as $fn$
  select case btrim(coalesce(p, ''))
    when '기혼' then 'married' when '미혼' then 'single' when '사별' then 'widowed'
    when '이혼' then 'other' when '재혼' then 'other'
  end
$fn$;

create function registry.relation_rank(p text) returns integer
language sql immutable set search_path = '' as $fn$
  select case p when 'self' then 1 when 'spouse' then 2 when 'child' then 3 when 'daughter_in_law' then 4
                when 'son_in_law' then 4 when 'grandchild' then 5 when 'parent' then 6 when 'sibling' then 7 else 9 end
$fn$;

-- ─────────────────────────────────────────────────────────────
-- 3. 대조
-- ─────────────────────────────────────────────────────────────

-- 반영 전 행의 후보와 제안을 다시 계산한다
--   strong: 이름이 같고 생년월일 또는 전화(휴대폰·집전화)가 같음 / name: 이름만 같음 / phone: 이름은 다르고 휴대폰이 같음
--   제안: 강한 후보가 딱 한 사람이고 그 사람이 다른 행의 강한 후보가 아니면 link,
--         후보가 없고 디모데에서 출석 중이면 new, 나머지는 review
create function registry.import_rematch() returns void
language plpgsql security definer set search_path = '' as $fn$
begin
  with u as (
    select u.id, registry.name_key(u.name) as nk, u.birth_date as b, registry.digits(u.phone) as ph
      from public.custom_users u
  ),
  c as (
    select r.id as row_id, u.id as person_id,
           case when u.nk = r.name_key
                 and ((r.birth_date is not null and u.b = r.birth_date) or u.ph = any (r.phones)) then 'strong'
                when u.nk = r.name_key then 'name'
                else 'phone' end as kind
      from registry.import_rows r
      join u on (u.nk = r.name_key and r.name_key <> '') or (u.ph is not null and u.ph = r.mobile)
     where r.applied_at is null
  )
  update registry.import_rows r
     set candidates = coalesce((
           select jsonb_agg(jsonb_build_object('person_id', c.person_id, 'kind', c.kind)
                            order by case c.kind when 'strong' then 0 when 'name' then 1 else 2 end, c.person_id)
             from c where c.row_id = r.id), '[]')
   where r.applied_at is null;

  with strong as (
    select r.id, (r.candidates -> 0 ->> 'person_id')::uuid as pid
      from registry.import_rows r
     where r.applied_at is null
       and (select count(*) from jsonb_array_elements(r.candidates) e where e ->> 'kind' = 'strong') = 1
  ),
  dup as (select s.pid from strong s group by s.pid having count(*) > 1)
  update registry.import_rows r
     set suggestion = case
           when r.sheet = 'main' and s.pid is not null and not exists (select 1 from dup where dup.pid = s.pid) then 'link'
           when jsonb_array_length(r.candidates) = 0 and r.sheet = 'main'
                and r.data ->> 'status' in ('예배출석', '가끔출석') then 'new'
           else 'review'
         end
    from (select r2.id, s.pid from registry.import_rows r2 left join strong s on s.id = r2.id
           where r2.applied_at is null) s
   where s.id = r.id;
end
$fn$;

-- ─────────────────────────────────────────────────────────────
-- 4. 반영
-- ─────────────────────────────────────────────────────────────

-- 한 사람을 디모데 세대에 넣는다. 세대 주소가 비어 있으면 세대 주소로, 세대 주소와 다르면 개인 주소로 채운다(설계 §9 결정 5)
create function registry.import_place_household(r registry.import_rows, p_pid uuid) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare
  d      jsonb := r.data;
  hsrc   text := d ->> 'head_src';
  hh_id  bigint;
  head   registry.import_rows;
  rel    text;
  note   text;
  self_m registry.household_members;
  h      registry.households;
  filled text[] := '{}';
  diffs  jsonb := '[]';
begin
  if exists (select 1 from registry.household_members m where m.person_id = p_pid) then
    if hsrc is not null or d ? 'address' then
      diffs := diffs || jsonb_build_object('field', 'household', 'dimode', coalesce(d ->> 'head_name', '') || ' 세대',
                                           'current', '이미 다른 세대에 있음');
    end if;
    return jsonb_build_object('filled', filled, 'diffs', diffs);
  end if;

  if hsrc is null then
    -- 세대 정보가 없으면 개인 주소만
    if d ? 'address' and not exists (select 1 from registry.people p where p.person_id = p_pid and p.address1 is not null) then
      update registry.people set address1 = d ->> 'address', address_zip = d ->> 'zip', updated_by = public.app_current_user_id()
       where person_id = p_pid;
      filled := array_append(filled, 'address');
    end if;
    return jsonb_build_object('filled', filled, 'diffs', diffs);
  end if;

  select * into head from registry.import_rows x where x.source = r.source and x.src_id = hsrc;
  select ih.household_id into hh_id from registry.import_households ih where ih.source = r.source and ih.household_src = hsrc;
  if hh_id is null then
    insert into registry.households (address_zip, address1, home_phone, note)
    values (coalesce(head.data ->> 'zip', d ->> 'zip'),
            coalesce(head.data ->> 'address', d ->> 'address'),
            coalesce(head.data ->> 'home_phone', d ->> 'home_phone'),
            case when d ? 'family' then '디모데 가족: ' || (d ->> 'family') end)
    returning id into hh_id;
    insert into registry.import_households (source, household_src, household_id) values (r.source, hsrc, hh_id);
    -- 세대주가 이번 파일에 없으면(교회를 떠난 가족 등) 이름만 있는 세대주를 둔다
    if head.id is null and nullif(btrim(d ->> 'head_name'), '') is not null and r.src_id <> hsrc then
      insert into registry.household_members (household_id, name, relation, sort_order, note)
      values (hh_id, registry.strip_mark(d ->> 'head_name'), 'self', 1, '디모데 세대주');
    end if;
    filled := array_append(filled, 'household');
  end if;

  -- 세대주(본인)는 세대주 ID의 주인만. 다른 사람이 '본인'으로 적혀 있으면 기타로 둔다
  rel := case when r.src_id = hsrc then 'self' else nullif(registry.dimode_relation(d ->> 'relation'), 'self') end;
  rel := coalesce(rel, 'other');
  if rel = 'self' then
    select * into self_m from registry.household_members m where m.household_id = hh_id and m.relation = 'self';
    if self_m.id is not null and self_m.person_id is null
       and registry.name_key(self_m.name) = r.name_key then
      delete from registry.household_members where id = self_m.id;   -- 이름만 있던 세대주 자리를 본인으로 바꾼다
    elsif self_m.id is not null then
      rel := 'other';
    end if;
  end if;
  if rel = 'other' and d ? 'relation' then
    note := '디모데 관계: ' || (d ->> 'relation');
  end if;
  insert into registry.household_members (household_id, person_id, relation, sort_order, note)
  values (hh_id, p_pid, rel, registry.relation_rank(rel), note);
  filled := array_append(filled, 'household_member');

  -- 주소
  select * into h from registry.households x where x.id = hh_id;
  if d ? 'address' then
    if h.address1 is null then
      update registry.households set address1 = d ->> 'address', address_zip = d ->> 'zip' where id = hh_id;
      filled := array_append(filled, 'address');
    elsif registry.name_key(h.address1) <> registry.name_key(d ->> 'address')
          and not exists (select 1 from registry.people p where p.person_id = p_pid and p.address1 is not null) then
      update registry.people set address1 = d ->> 'address', address_zip = d ->> 'zip', updated_by = public.app_current_user_id()
       where person_id = p_pid;
      filled := array_append(filled, 'address');
    end if;
  end if;
  if h.home_phone is null and d ? 'home_phone' then
    update registry.households set home_phone = d ->> 'home_phone' where id = hh_id;
  end if;
  return jsonb_build_object('filled', filled, 'diffs', diffs);
end
$fn$;

-- 행 하나를 반영한다. 비어 있는 칸만 채우고, 이미 있는 값이 다르면 diffs 로 돌려준다
create function registry.import_apply_row(r registry.import_rows) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare
  d       jsonb := r.data;
  me      uuid := public.app_current_user_id();
  pid     uuid;
  created boolean := false;
  u       public.custom_users;
  rp      registry.people;
  om      record;
  fk      text;
  label   text;
  t       registry.office_terms;
  reg     registry.status_events;
  st      text;
  hh      jsonb;
  old_p   jsonb := '{}';
  new_p   jsonb := '{}';
  filled  text[] := '{}';
  diffs   jsonb := '[]';
  v_name  text;
begin
  select * into om from registry.dimode_office(d ->> 'office', d ->> 'office_detail');

  if r.decision = 'new' then
    v_name := registry.strip_mark(d ->> 'name');
    insert into public.custom_users (name, phone, gender, birth_date, office, member, active)
    values (v_name, d ->> 'mobile', d ->> 'gender', nullif(d ->> 'birth_date', '')::date, '성도', true, false)
    returning id into pid;
    perform registry.log_profile_change(pid, 'INSERT', null,
      jsonb_build_object('name', v_name, 'phone', d ->> 'mobile', 'gender', d ->> 'gender',
                         'birth_date', d ->> 'birth_date', 'office', '성도', 'member', true));
    insert into registry.people (person_id, birth_lunar, occupation, workplace, marital_status, wedding_date,
                                 previous_church, guide_name, updated_by)
    values (pid, coalesce((d ->> 'birth_lunar')::boolean, false), d ->> 'occupation', d ->> 'workplace',
            registry.dimode_marital(d ->> 'marital'), nullif(d ->> 'wedding_date', '')::date,
            d ->> 'previous_church', d ->> 'guide', me);
    insert into registry.status_events (person_id, kind, event_date, reason, created_by)
    values (pid, 'register', nullif(d ->> 'registered_on', '')::date, '디모데에서 가져옴', me);
    if om.code is not null then
      insert into registry.office_terms (person_id, office, standing, started_on, note, created_by)
      values (pid, om.code, om.standing, nullif(d ->> 'office_started_on', '')::date, '디모데에서 가져옴', me);
      perform registry.sync_office(pid);
    elsif coalesce(d ->> 'office_detail', d ->> 'office') not in ('성도') then
      diffs := diffs || jsonb_build_object('field', 'office', 'dimode', coalesce(d ->> 'office_detail', d ->> 'office'),
                                           'current', null);
    end if;
    created := true;
    filled := array_append(filled, 'created');
  else
    pid := r.person_id;
    select * into u from public.custom_users x where x.id = pid for update;
    if u.id is null then
      raise exception '연결할 사람을 찾지 못했습니다 (디모데 %). 다시 골라 주세요', r.src_id using errcode = 'P0002';
    end if;

    if not exists (select 1 from registry.people p where p.person_id = pid) then
      insert into registry.people (person_id, updated_by) values (pid, me);
      insert into registry.status_events (person_id, kind, event_date, reason, created_by)
      values (pid, 'register', nullif(d ->> 'registered_on', '')::date, '디모데에서 가져와 교적 등록', me);
      perform registry.office_from_profile(pid);
      perform registry.sync_member(pid);
      filled := array_append(filled, 'enrolled');
    end if;

    -- 앱 프로필의 빈 칸. 가입한 계정의 전화는 채우지 않는다(가입 병합 트리거가 돌기 때문)
    if u.gender is null and d ? 'gender' then
      old_p := old_p || jsonb_build_object('gender', null); new_p := new_p || jsonb_build_object('gender', d ->> 'gender');
    elsif u.gender is distinct from d ->> 'gender' and d ? 'gender' then
      diffs := diffs || jsonb_build_object('field', 'gender', 'dimode', d ->> 'gender', 'current', u.gender);
    end if;
    if u.birth_date is null and d ? 'birth_date' then
      old_p := old_p || jsonb_build_object('birth_date', null); new_p := new_p || jsonb_build_object('birth_date', d ->> 'birth_date');
    elsif d ? 'birth_date' and u.birth_date <> (d ->> 'birth_date')::date then
      diffs := diffs || jsonb_build_object('field', 'birth_date', 'dimode', d ->> 'birth_date', 'current', u.birth_date);
    end if;
    if registry.digits(u.phone) is null and d ? 'mobile'
       and not exists (select 1 from auth.users a where a.id = u.auth_id) then
      old_p := old_p || jsonb_build_object('phone', null); new_p := new_p || jsonb_build_object('phone', d ->> 'mobile');
    elsif d ? 'mobile' and registry.digits(u.phone) is distinct from registry.digits(d ->> 'mobile') then
      diffs := diffs || jsonb_build_object('field', 'phone', 'dimode', d ->> 'mobile', 'current', u.phone);
    end if;
    if registry.name_key(u.name) <> r.name_key then
      diffs := diffs || jsonb_build_object('field', 'name', 'dimode', d ->> 'name', 'current', u.name);
    end if;
    if new_p <> '{}' then
      update public.custom_users x
         set gender     = coalesce(x.gender, new_p ->> 'gender'),
             birth_date = coalesce(x.birth_date, (new_p ->> 'birth_date')::date),
             phone      = coalesce(x.phone, new_p ->> 'phone')
       where x.id = pid;
      perform registry.log_profile_change(pid, 'UPDATE', old_p, new_p);
      filled := filled || array(select jsonb_object_keys(new_p));
    end if;

    -- 교적의 빈 칸
    select * into rp from registry.people p where p.person_id = pid;
    update registry.people p
       set occupation      = coalesce(p.occupation, d ->> 'occupation'),
           workplace       = coalesce(p.workplace, d ->> 'workplace'),
           marital_status  = coalesce(p.marital_status, registry.dimode_marital(d ->> 'marital')),
           wedding_date    = coalesce(p.wedding_date, nullif(d ->> 'wedding_date', '')::date),
           previous_church = coalesce(p.previous_church, d ->> 'previous_church'),
           guide_name      = case when p.guide_person_id is null then coalesce(p.guide_name, d ->> 'guide') else p.guide_name end,
           birth_lunar     = p.birth_lunar or coalesce((d ->> 'birth_lunar')::boolean, false),
           updated_by      = me
     where p.person_id = pid
       and (   (p.occupation is null and d ? 'occupation')
            or (p.workplace is null and d ? 'workplace')
            or (p.marital_status is null and registry.dimode_marital(d ->> 'marital') is not null)
            or (p.wedding_date is null and d ? 'wedding_date')
            or (p.previous_church is null and d ? 'previous_church')
            or (p.guide_person_id is null and p.guide_name is null and d ? 'guide')
            or (not p.birth_lunar and coalesce((d ->> 'birth_lunar')::boolean, false)));
    if found then
      filled := array_append(filled, 'registry');
    end if;

    -- 등록일: 날짜를 모르는 '등록' 한 건만 있을 때 채운다
    if d ? 'registered_on' then
      select * into reg from registry.status_events e
       where e.person_id = pid and e.kind = 'register' order by e.event_date nulls first, e.id limit 1;
      if reg.id is not null and reg.event_date is null
         and (select count(*) from registry.status_events e where e.person_id = pid and e.kind = 'register') = 1 then
        update registry.status_events set event_date = (d ->> 'registered_on')::date where id = reg.id;
        filled := array_append(filled, 'registered_on');
      elsif reg.event_date is distinct from (d ->> 'registered_on')::date then
        diffs := diffs || jsonb_build_object('field', 'registered_on', 'dimode', d ->> 'registered_on', 'current', reg.event_date);
      end if;
    end if;

    -- 직분: 지금 직분과 같은 코드면 임명일만 채운다. 다르면 바꾸지 않고 차이로 남긴다
    label := coalesce(d ->> 'office_detail', d ->> 'office');
    select * into t from registry.office_terms x
     where x.person_id = pid and x.office = om.code and x.ended_on is null limit 1;
    if t.id is not null then
      if t.started_on is null and d ? 'office_started_on' then
        update registry.office_terms set started_on = (d ->> 'office_started_on')::date where id = t.id;
        filled := array_append(filled, 'office_started_on');
      end if;
      if t.standing <> om.standing then
        diffs := diffs || jsonb_build_object('field', 'office', 'dimode', label, 'current', u.office);
      end if;
    elsif label is not null and label not in ('성도') and label is distinct from u.office then
      diffs := diffs || jsonb_build_object('field', 'office', 'dimode', label, 'current', u.office);
    end if;

    -- 재적 상태가 디모데와 어긋나면 알린다 (바꾸지 않는다)
    select s.status into st from registry.summary s where s.person_id = pid;
    if r.sheet = 'deceased' then
      diffs := diffs || jsonb_build_object('field', 'status', 'dimode', '별세' || coalesce(' ' || (d ->> 'deceased_on'), ''),
                                           'current', st);
    elsif d ->> 'kind' in ('보관', '제적', '타교인', '이민', '유고', '타종교', '불신') or d ->> 'status' = '불출석' then
      diffs := diffs || jsonb_build_object('field', 'status', 'dimode', concat_ws(' · ', d ->> 'status', d ->> 'kind'),
                                           'current', st);
    end if;
  end if;

  -- 신급: 같은 종류가 없을 때만 넣는다
  fk := registry.dimode_faith(d ->> 'baptism');
  if fk is not null then
    if not exists (select 1 from registry.faith_events f where f.person_id = pid and f.kind = fk) then
      insert into registry.faith_events (person_id, kind, event_date, church_name, officiant, note, created_by)
      values (pid, fk, nullif(d ->> 'baptism_date', '')::date,
              case when d ->> 'baptism_church' ~ '부평\s*동부' then null else d ->> 'baptism_church' end,
              d ->> 'officiant', '디모데에서 가져옴', me);
      filled := array_append(filled, 'faith');
    end if;
  elsif d ? 'baptism' then
    diffs := diffs || jsonb_build_object('field', 'faith', 'dimode', d ->> 'baptism', 'current', null);
  end if;

  -- 세대·주소
  hh := registry.import_place_household(r, pid);
  filled := filled || array(select jsonb_array_elements_text(hh -> 'filled'));
  diffs := diffs || (hh -> 'diffs');

  -- 옛 메모, 옛 ID
  if r.memo is not null then
    insert into registry.legacy_memos (person_id, source, src_id, body, created_by)
    values (pid, r.source, r.src_id, r.memo, me)
    on conflict (source, src_id) do nothing;
    filled := array_append(filled, 'memo');
  end if;
  insert into registry.legacy_links (source, src_id, person_id, offering_no, linked_by)
  values (r.source, r.src_id, pid, d ->> 'offering_no', me)
  on conflict (source, src_id) do update set person_id = excluded.person_id, offering_no = excluded.offering_no;

  return jsonb_build_object('person_id', pid, 'created', created, 'filled', to_jsonb(filled), 'diffs', diffs);
end
$fn$;

revoke all on all functions in schema registry from public;

-- ─────────────────────────────────────────────────────────────
-- 5. 화면이 부르는 함수
-- ─────────────────────────────────────────────────────────────

-- 올리기. p_rows = [{src_id, sheet, data, memo}]. 같은 디모데 ID를 다시 올리면 반영 전 행만 새 값으로 바꾼다
create function public.registry_import_load(p_rows jsonb) returns integer
language plpgsql security definer set search_path = '' as $fn$
declare
  n integer;
begin
  perform registry.require('edit');
  perform registry.require_admin();
  if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception '올릴 행이 없습니다' using errcode = '22023';
  end if;
  if jsonb_array_length(p_rows) > 500 then
    raise exception '한 번에 500행까지 올릴 수 있습니다' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(p_rows) x
              where jsonb_typeof(x -> 'data') is distinct from 'object'
                 or coalesce(x ->> 'sheet', 'main') not in ('main', 'deceased')) then
    raise exception '파일 형식이 맞지 않습니다' using errcode = '22023';
  end if;

  insert into registry.import_rows (source, src_id, sheet, data, memo, name_key, birth_date, phones, mobile, uploaded_by)
  select 'dimode', x ->> 'src_id', coalesce(x ->> 'sheet', 'main'), x -> 'data', nullif(btrim(x ->> 'memo'), ''),
         registry.name_key(x -> 'data' ->> 'name'),
         case when x -> 'data' ->> 'birth_date' ~ '^\d{4}-\d{2}-\d{2}$' then (x -> 'data' ->> 'birth_date')::date end,
         array_remove(array[registry.digits(x -> 'data' ->> 'mobile'), registry.digits(x -> 'data' ->> 'home_phone')], null),
         registry.digits(x -> 'data' ->> 'mobile'),
         public.app_current_user_id()
    from jsonb_array_elements(p_rows) x
   where nullif(btrim(x ->> 'src_id'), '') is not null
     and nullif(btrim(x -> 'data' ->> 'name'), '') is not null
  on conflict (source, src_id) do update
     set sheet = excluded.sheet, data = excluded.data, memo = excluded.memo, name_key = excluded.name_key,
         birth_date = excluded.birth_date, phones = excluded.phones, mobile = excluded.mobile,
         uploaded_by = excluded.uploaded_by, uploaded_at = now()
   where registry.import_rows.applied_at is null;
  get diagnostics n = row_count;

  perform registry.import_rematch();
  perform privacy.log_access('create', 'registry_import_load', '{}', jsonb_build_object('rows', n));
  return n;
end
$fn$;

-- 건수만 (개인 정보 없음)
create function public.registry_import_summary() returns jsonb
language plpgsql security definer set search_path = '' as $fn$
begin
  perform registry.require('edit');
  return (
    select jsonb_build_object(
      'total', count(*),
      'link', count(*) filter (where r.applied_at is null and r.decision is null and r.suggestion = 'link'),
      'review', count(*) filter (where r.applied_at is null and r.decision is null and r.suggestion = 'review'),
      'new', count(*) filter (where r.applied_at is null and r.decision is null and r.suggestion = 'new'),
      'decided', count(*) filter (where r.applied_at is null and r.decision in ('link', 'new')),
      'skipped', count(*) filter (where r.decision = 'skip'),
      'applied', count(*) filter (where r.applied_at is not null),
      'diffs', count(*) filter (where r.applied_at is not null and jsonb_array_length(coalesce(r.result -> 'diffs', '[]')) > 0),
      'uploaded_at', max(r.uploaded_at))
    from registry.import_rows r);
end
$fn$;

-- 목록. p_view: link(연결 제안) | review(확인 필요) | new(새 교적 후보) | decided(확정, 반영 전) | skipped | applied | diffs
create function public.registry_import_list(p_view text, p_limit integer default 100, p_offset integer default 0)
returns table (id bigint, src_id text, sheet text, data jsonb, has_memo boolean, candidates jsonb, suggestion text,
               decision text, person_id uuid, person_name text, applied_at timestamptz, result jsonb, total bigint)
language plpgsql security definer set search_path = '' as $fn$
#variable_conflict use_column
declare
  ids     bigint[];
  tot     bigint;
  targets uuid[];
begin
  perform registry.require('edit');
  if p_view not in ('link', 'review', 'new', 'decided', 'skipped', 'applied', 'diffs') then
    raise exception '알 수 없는 목록입니다' using errcode = '22023';
  end if;

  select array_agg(b.id order by b.name_key, b.id), max(b.total) into ids, tot
    from (select r.id, r.name_key, count(*) over () as total
            from registry.import_rows r
           where case p_view
                   when 'link'    then r.applied_at is null and r.decision is null and r.suggestion = 'link'
                   when 'review'  then r.applied_at is null and r.decision is null and r.suggestion = 'review'
                   when 'new'     then r.applied_at is null and r.decision is null and r.suggestion = 'new'
                   when 'decided' then r.applied_at is null and r.decision in ('link', 'new')
                   when 'skipped' then r.decision = 'skip'
                   when 'applied' then r.applied_at is not null
                   when 'diffs'   then r.applied_at is not null
                                       and jsonb_array_length(coalesce(r.result -> 'diffs', '[]')) > 0
                 end
           order by r.name_key, r.id
           limit least(greatest(coalesce(p_limit, 100), 1), 500)
          offset greatest(coalesce(p_offset, 0), 0)) b;

  select array_agg(distinct x) into targets
    from (select (e ->> 'person_id')::uuid as x
            from registry.import_rows r, jsonb_array_elements(r.candidates) e where r.id = any (coalesce(ids, '{}'))
          union all
          select r.person_id from registry.import_rows r where r.id = any (coalesce(ids, '{}')) and r.person_id is not null) y;
  perform privacy.log_access('view', 'registry_import_list', coalesce(targets, '{}'),
    jsonb_build_object('view', p_view, 'rows', coalesce(cardinality(ids), 0), 'offset', p_offset));

  return query
    select r.id, r.src_id, r.sheet, r.data, r.memo is not null,
           (select coalesce(jsonb_agg(jsonb_build_object(
                     'person_id', cu.id, 'kind', e ->> 'kind', 'name', cu.name, 'gender', cu.gender,
                     'birth_date', cu.birth_date, 'phone', cu.phone, 'office', cu.office,
                     'has_account', exists (select 1 from auth.users a where a.id = cu.auth_id),
                     'in_registry', s.person_id is not null, 'status', s.status,
                     'group_name', (select sg.name from public.small_group_members m
                                      join public.small_groups sg on sg.id = m.small_group_id
                                     where m.user_id = cu.id and m.active and sg.active order by sg.sort_order limit 1))
                     order by ord), '[]')
              from jsonb_array_elements(r.candidates) with ordinality as c(e, ord)
              join public.custom_users cu on cu.id = (e ->> 'person_id')::uuid
              left join registry.summary s on s.person_id = cu.id),
           r.suggestion, r.decision, r.person_id, pu.name, r.applied_at, r.result, coalesce(tot, 0)
      from registry.import_rows r
      left join public.custom_users pu on pu.id = r.person_id
     where r.id = any (coalesce(ids, '{}'))
     order by array_position(ids, r.id);
end
$fn$;

-- 한 행 정하기. p_decision: link(p_person_id 필요) | new | skip | null(되돌리기)
create function public.registry_import_decide(p_row_id bigint, p_decision text, p_person_id uuid default null)
returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  r registry.import_rows;
begin
  perform registry.require('edit');
  select * into r from registry.import_rows x where x.id = p_row_id for update;
  if r.id is null then
    raise exception '행을 찾지 못했습니다' using errcode = 'P0002';
  end if;
  if r.applied_at is not null then
    raise exception '이미 반영한 행입니다. 교적 카드에서 고쳐 주세요' using errcode = '22023';
  end if;
  if p_decision is not null and p_decision not in ('link', 'new', 'skip') then
    raise exception '알 수 없는 처리입니다' using errcode = '22023';
  end if;
  if p_decision = 'new' and r.sheet = 'deceased' then
    raise exception '별세자는 새 교적으로 만들 수 없습니다' using errcode = '22023';
  end if;
  if p_decision = 'link' then
    if p_person_id is null or not exists (select 1 from public.custom_users u where u.id = p_person_id) then
      raise exception '연결할 사람을 골라 주세요' using errcode = '22023';
    end if;
    if exists (select 1 from registry.import_rows x
                where x.person_id = p_person_id and x.id <> p_row_id and x.decision in ('link', 'new')) then
      raise exception '그 사람은 이미 다른 디모데 행과 연결돼 있습니다' using errcode = '23505';
    end if;
    if exists (select 1 from registry.legacy_links l where l.person_id = p_person_id and l.source = r.source) then
      raise exception '그 사람은 이미 디모데 자료를 반영했습니다' using errcode = '23505';
    end if;
  end if;

  update registry.import_rows
     set decision = p_decision,
         person_id = case when p_decision = 'link' then p_person_id end,
         decided_by = case when p_decision is null then null else public.app_current_user_id() end,
         decided_at = case when p_decision is null then null else now() end
   where id = p_row_id;
  perform privacy.log_access('update', 'registry_import_decide',
    case when p_person_id is null then '{}'::uuid[] else array[p_person_id] end,
    jsonb_build_object('row_id', p_row_id, 'decision', p_decision));
end
$fn$;

-- 연결 제안을 한꺼번에 확정한다 (p_ids 를 주면 그 행만)
create function public.registry_import_accept(p_ids bigint[] default null) returns integer
language plpgsql security definer set search_path = '' as $fn$
declare
  pids uuid[];
begin
  perform registry.require('edit');
  with picked as (
    select r.id, (r.candidates -> 0 ->> 'person_id')::uuid as pid
      from registry.import_rows r
     where r.applied_at is null and r.decision is null and r.suggestion = 'link'
       and (p_ids is null or r.id = any (p_ids))
  ),
  ok as (
    select p.* from picked p
     where not exists (select 1 from registry.import_rows x
                        where x.person_id = p.pid and x.decision in ('link', 'new'))
       and not exists (select 1 from registry.legacy_links l where l.person_id = p.pid and l.source = 'dimode')
  ),
  upd as (
    update registry.import_rows r
       set decision = 'link', person_id = ok.pid, decided_by = public.app_current_user_id(), decided_at = now()
      from ok where ok.id = r.id
    returning r.person_id
  )
  select array_agg(person_id) into pids from upd;
  perform privacy.log_access('update', 'registry_import_accept', coalesce(pids, '{}'),
    jsonb_build_object('rows', coalesce(cardinality(pids), 0)));
  return coalesce(cardinality(pids), 0);
end
$fn$;

-- 반영 결과 여러 건을 건수로 묶는다
create function registry.import_stats(p_results jsonb) returns jsonb
language sql immutable set search_path = '' as $fn$
  select jsonb_build_object(
    'rows', jsonb_array_length(coalesce(p_results, '[]')),
    'created', (select count(*) from jsonb_array_elements(coalesce(p_results, '[]')) x where (x ->> 'created')::boolean),
    'filled', (select coalesce(jsonb_object_agg(k, c), '{}')
                 from (select f as k, count(*) as c
                         from jsonb_array_elements(coalesce(p_results, '[]')) x, jsonb_array_elements_text(x -> 'filled') f
                        group by f) z),
    'diffs', (select coalesce(jsonb_object_agg(k, c), '{}')
                from (select e ->> 'field' as k, count(*) as c
                        from jsonb_array_elements(coalesce(p_results, '[]')) x, jsonb_array_elements(x -> 'diffs') e
                       group by 1) z))
$fn$;

revoke all on function registry.import_stats(jsonb) from public;

-- 확정한 행을 반영한다. 한 번에 p_limit 행까지 (요청 시간 제한 8초 때문). 남은 행 수를 돌려준다
-- p_dry_run = true: 확정한 행 전부를 반영해 보고 결과 건수만 돌려준 뒤 모두 되돌린다 (미리보기)
create function public.registry_import_apply(p_limit integer default 100, p_dry_run boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare
  r       registry.import_rows;
  res     jsonb;
  results jsonb := '[]';
  pids    uuid[] := '{}';
  left_n  integer;
  stats   jsonb;
begin
  perform registry.require('edit');

  if p_dry_run then
    begin
      for r in
        select * from registry.import_rows x
         where x.applied_at is null and x.decision in ('link', 'new')
         order by (x.data ->> 'head_src' is distinct from x.src_id), x.id
      loop
        res := registry.import_apply_row(r);
        update registry.import_rows set applied_at = now(), person_id = (res ->> 'person_id')::uuid where id = r.id;
        results := results || jsonb_build_array(res);
      end loop;
      raise exception 'registry_import_dry_run' using errcode = 'P0001';
    exception when raise_exception then
      if sqlerrm <> 'registry_import_dry_run' then
        raise;
      end if;
    end;
    stats := registry.import_stats(results);
    perform privacy.log_access('view', 'registry_import_apply', '{}', jsonb_build_object('preview', stats));
    return stats || jsonb_build_object('preview', true);
  end if;

  for r in
    select * from registry.import_rows x
     where x.applied_at is null and x.decision in ('link', 'new')
     order by (x.data ->> 'head_src' is distinct from x.src_id), x.id   -- 세대주를 먼저
     limit least(greatest(coalesce(p_limit, 100), 1), 200)
     for update
  loop
    res := registry.import_apply_row(r);
    update registry.import_rows
       set applied_at = now(), result = res, person_id = (res ->> 'person_id')::uuid
     where id = r.id;
    perform registry.sync_member((res ->> 'person_id')::uuid);
    results := results || jsonb_build_array(res);
    pids := pids || (res ->> 'person_id')::uuid;
  end loop;

  select count(*) into left_n from registry.import_rows x where x.applied_at is null and x.decision in ('link', 'new');
  stats := registry.import_stats(results) || jsonb_build_object('remaining', left_n);
  perform privacy.log_access('update', 'registry_import_apply', pids, stats);
  return stats;
end
$fn$;

-- 가져오기 정리: 올린 행을 모두 지운다 (반영한 내용·옛 ID·옛 메모는 남는다)
create function public.registry_import_close() returns integer
language plpgsql security definer set search_path = '' as $fn$
declare
  n integer;
begin
  perform registry.require('edit');
  perform registry.require_admin();
  -- where true: API 요청에는 WHERE 없는 DELETE 를 막는 safeupdate 가 걸려 있다
  delete from registry.import_rows where true;
  get diagnostics n = row_count;
  delete from registry.import_households where true;
  perform privacy.log_access('delete', 'registry_import_close', '{}', jsonb_build_object('rows', n));
  return n;
end
$fn$;

-- 옛 메모 (교역자만)
create function public.registry_legacy_memos(p_person_id uuid)
returns table (id bigint, source text, body text, created_at timestamptz)
language plpgsql security definer set search_path = '' as $fn$
#variable_conflict use_column
begin
  perform registry.require('pastoral');
  perform registry.assert_person(p_person_id);
  perform privacy.log_access('view', 'registry_legacy_memos', array[p_person_id], null);
  return query
    select m.id, m.source, m.body, m.created_at from registry.legacy_memos m
     where m.person_id = p_person_id order by m.created_at, m.id;
end
$fn$;

do $grants$
declare
  f regprocedure;
begin
  for f in
    select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('registry_import_load', 'registry_import_summary', 'registry_import_list', 'registry_import_decide',
                         'registry_import_accept', 'registry_import_apply', 'registry_import_close', 'registry_legacy_memos')
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$grants$;

revoke all on all functions in schema registry from public;

notify pgrst, 'reload schema';

-- 교적 ⑤: 전출·별세·제적 5년 뒤 인적사항 자동 파기 (설계 §9 결정 6, 개인정보처리방침 7)
--
-- 기준: 지금 재적 상태가 전출·별세·제적이고, 그 상태가 된 날(재적 이벤트 날짜, 비어 있으면 입력한 날)부터 5년이 지난 사람.
--       다시 등록(재등록·전입)하면 대상에서 빠지고, 다시 떠나면 그날부터 5년을 다시 센다.
-- 남기는 것: 이름, 교번, 재적 이력, 신급(학습·세례 기록), 직분 이력과 호칭, 동의 기록(종류·날짜)
-- 지우는 것:
--   registry.people   동명이인 구분, 음력, 주소, 직업, 직장, 결혼, 결혼기념일, 이전 교회, 인도자, 비고
--   세대              이 사람의 세대 연결. 교인이 아무도 남지 않은 세대는 주소·집전화·교인 아닌 가족까지 통째로
--   메모·디모데 메모·가져오기 행
--   동의 기록         법정대리인 이름·비고
--   custom_users      전화, 생년월일, 성별, 이메일, 사진 주소 — 로그인 계정이 없는 사람만.
--                     계정이 있으면 앱 회원 정보라서 둔다. 앱을 탈퇴하면(계정 연결 끊김) 다음 실행 때 지운다
--   변경기록          위 칸의 지난 값(old_data·new_data). 파기하면서 생기는 변경기록에도 값은 남기지 않는다(바뀐 칸 이름만)
-- 기록: 사람마다 변경기록 op 'PURGE' 한 줄(교인 카드 '변경 이력'에 보임) + 접속기록 action 'delete', fn 'registry_purge_departed'
-- 실행: 매일 03:40 KST (pg_cron 'registry-purge-departed'). 화면·API 에서는 부를 수 없다

alter table registry.people add column purged_on date;
comment on column registry.people.purged_on is '전출·별세·제적 5년 뒤 인적사항을 파기한 날 (registry.purge_departed)';

-- 변경기록: 파기 중(privacy.redacting = on)에는 값 없이 무엇을 바꿨는지만 남긴다
create or replace function privacy.log_change() returns trigger
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
      return new;
    end if;
  end if;
  if current_setting('privacy.redacting', true) = 'on' then
    o := null;
    n := null;
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

-- 추가만 하는 기록 표에 예외 하나를 더한다: 파기 중에는 변경기록의 값(old_data·new_data)에서 칸을 빼는 것만 된다
create or replace function privacy.forbid_mutation() returns trigger
language plpgsql set search_path = '' as $fn$
begin
  -- NEW/OLD 는 해당 작업일 때만 읽는다 (DELETE 가 아닌 경우 OLD 가 없을 수 있다)
  if tg_op = 'DELETE' and current_setting('privacy.purging', true) = 'on' then
    if (to_jsonb(old) ->> 'at')::timestamptz < now() - tg_argv[0]::interval then
      return old;
    end if;
  end if;
  if tg_op = 'UPDATE' and tg_table_name = 'change_logs' and current_setting('privacy.redacting', true) = 'on' then
    if (to_jsonb(new) - 'old_data' - 'new_data') = (to_jsonb(old) - 'old_data' - 'new_data')
       and (new.old_data is null or new.old_data <@ old.old_data)
       and (new.new_data is null or new.new_data <@ old.new_data) then
      return new;
    end if;
  end if;
  raise exception '%.% 은(는) 추가만 할 수 있습니다', tg_table_schema, tg_table_name using errcode = '42501';
end
$fn$;

-- 변경기록 한 줄의 값에서 파기할 칸을 뺀다
create function registry.purge_redact(p_table text, p_data jsonb) returns jsonb
language sql immutable set search_path = '' as $fn$
  select case
    when p_data is null then null
    when p_table in ('registry.notes', 'registry.household_members', 'registry.households') then null
    when p_table = 'public.custom_users' then p_data - array['phone', 'birth_date', 'gender', 'email', 'profile_picture']
    when p_table = 'registry.people' then p_data - array['name_note', 'birth_lunar', 'address_zip', 'address1', 'address2',
      'occupation', 'workplace', 'marital_status', 'wedding_date', 'previous_church', 'guide_person_id', 'guide_name', 'note']
    when p_table = 'registry.consents' then p_data - array['guardian_name', 'note']
    else p_data
  end
$fn$;

create function registry.purge_departed(p_today date default (now() at time zone 'Asia/Seoul')::date) returns integer
language plpgsql security definer set search_path = '' as $fn$
declare
  cutoff date := (p_today - interval '5 years')::date;
  ids    uuid[];
  merged uuid[];
  hh     bigint[];
  gone   text[];
begin
  -- 1. 대상: 떠난 지 5년이 지났고 아직 지울 것이 남은 사람
  select array_agg(p.person_id) into ids
    from registry.people p
    cross join lateral (
      select e.kind, coalesce(e.event_date, (e.created_at at time zone 'Asia/Seoul')::date) as on_date
        from registry.status_events e
       where e.person_id = p.person_id
       order by e.event_date desc nulls last, e.id desc     -- registry.summary 의 현재 상태와 같은 순서
       limit 1) last
   where last.kind in ('transfer_out', 'deceased', 'removed')
     and last.on_date <= cutoff
     and (num_nonnulls(p.name_note, p.address_zip, p.address1, p.address2, p.occupation, p.workplace, p.marital_status,
                       p.wedding_date, p.previous_church, p.guide_person_id, p.guide_name, p.note) > 0
          or p.birth_lunar
          or exists (select 1 from registry.household_members m where m.person_id = p.person_id)
          or exists (select 1 from registry.notes n where n.person_id = p.person_id)
          or exists (select 1 from registry.legacy_memos m where m.person_id = p.person_id)
          or exists (select 1 from registry.import_rows r where r.person_id = p.person_id)
          or exists (select 1 from registry.consents c
                      where c.person_id = p.person_id and num_nonnulls(c.guardian_name, c.note) > 0)
          or exists (select 1 from public.custom_users u
                      where u.id = p.person_id
                        and not exists (select 1 from auth.users a where a.id = u.auth_id)
                        and num_nonnulls(u.phone, u.birth_date, u.gender, u.email, u.profile_picture) > 0));
  if ids is null then
    return 0;
  end if;

  perform set_config('privacy.redacting', 'on', true);

  -- 2. 세대: 연결을 끊고, 교인이 아무도 남지 않은 세대는 통째로 지운다(교인 아닌 가족 행은 CASCADE)
  select array_agg(distinct m.household_id) into hh from registry.household_members m where m.person_id = any (ids);
  delete from registry.household_members m where m.person_id = any (ids);
  with d as (
    delete from registry.households h
     where h.id = any (coalesce(hh, '{}'))
       and not exists (select 1 from registry.household_members m where m.household_id = h.id and m.person_id is not null)
    returning h.id)
  select array_agg(d.id::text) into gone from d;

  -- 3. 메모·디모데 메모·가져오기 행
  delete from registry.notes n where n.person_id = any (ids);
  delete from registry.legacy_memos m where m.person_id = any (ids);
  delete from registry.import_rows r where r.person_id = any (ids);

  -- 4. 동의 기록은 남기고 법정대리인 이름·비고만
  update registry.consents c set guardian_name = null, note = null
   where c.person_id = any (ids) and num_nonnulls(c.guardian_name, c.note) > 0;

  -- 5. 교적의 인적사항
  update registry.people p
     set name_note = null, birth_lunar = false, address_zip = null, address1 = null, address2 = null,
         occupation = null, workplace = null, marital_status = null, wedding_date = null, previous_church = null,
         guide_person_id = null, guide_name = null, note = null, purged_on = p_today
   where p.person_id = any (ids);

  -- 6. 앱 프로필(계정 없는 사람만). 사람마다 'PURGE' 한 줄: 바뀐 칸은 custom_users 에서 지운 칸
  insert into privacy.change_logs (table_name, op, person_id, record_id, changed_fields)
  select 'public.custom_users', 'PURGE', u.id, u.id::text,
         case when exists (select 1 from auth.users a where a.id = u.auth_id) then '{}'::text[]
              else array_remove(array[
                     case when u.phone is not null then 'phone' end,
                     case when u.birth_date is not null then 'birth_date' end,
                     case when u.gender is not null then 'gender' end,
                     case when u.email is not null then 'email' end,
                     case when u.profile_picture is not null then 'profile_picture' end], null) end
    from public.custom_users u
   where u.id = any (ids);
  update public.custom_users u
     set phone = null, birth_date = null, gender = null, email = null, profile_picture = null
   where u.id = any (ids)
     and not exists (select 1 from auth.users a where a.id = u.auth_id)
     and num_nonnulls(u.phone, u.birth_date, u.gender, u.email, u.profile_picture) > 0;

  -- 7. 지난 변경기록의 값. 가입 병합으로 합쳐진 옛 프로필의 기록과 지운 세대의 기록까지
  select array_agg(distinct (l.old_data ->> 'profile_id')::uuid) into merged
    from privacy.change_logs l
   where l.person_id = any (ids) and l.op = 'MERGE';
  update privacy.change_logs l
     set old_data = registry.purge_redact(l.table_name, l.old_data),
         new_data = registry.purge_redact(l.table_name, l.new_data)
   where (l.person_id = any (ids)
          or l.person_id = any (coalesce(merged, '{}'))
          or (l.table_name = 'registry.households' and l.record_id = any (coalesce(gone, '{}')))
          or (l.table_name = 'registry.household_members'
              and coalesce(l.old_data, l.new_data) ->> 'household_id' = any (coalesce(gone, '{}'))))
     and (l.old_data is distinct from registry.purge_redact(l.table_name, l.old_data)
          or l.new_data is distinct from registry.purge_redact(l.table_name, l.new_data));

  perform privacy.log_access('delete', 'registry_purge_departed', ids,
    jsonb_build_object('rule', '전출·별세·제적 후 5년', 'cutoff', cutoff, 'count', cardinality(ids),
                       'households', coalesce(cardinality(gone), 0)));
  perform set_config('privacy.redacting', 'off', true);
  return cardinality(ids);
end
$fn$;

revoke all on all functions in schema registry from public;

-- 매일 03:40 KST
select cron.schedule('registry-purge-departed', '40 18 * * *', 'select registry.purge_departed()');

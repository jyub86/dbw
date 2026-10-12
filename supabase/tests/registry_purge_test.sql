-- 교적 ⑤ 5년 뒤 자동 파기(20261012_registry_purge) 테스트
--
-- 운영 DB에서 실행해도 된다. 마지막에 예외를 던져 모두 되돌린다. 결과는 'TEST_RESULT ...' 오류 메시지로 나온다.
-- 적용 전에는 마이그레이션 SQL 바로 뒤에 이 파일을 붙여 한 번에 실행한다.
-- 테스트 사람·세대는 '테스트파기…' 이름으로 테스트 안에서 만든다.
--   A 6년 전 전출, 계정 없음, 세대(B·교인 아닌 자녀와 같이)·메모·디모데 메모·가져오기 행·동의(대리인)
--   B 재적, A 와 같은 세대          C 4년 11개월 전 별세          D 6년 전 제적 → 1년 전 재등록
--   E 5년 1일 전 전출, 앱 계정 있음, 혼자 세대 + 교인 아닌 가족 → 첫 실행 뒤 앱 탈퇴(계정 연결 끊김)
--   F 정확히 5년 전 전출              G 5년에서 하루 모자람

do $test$
declare
  tests text[] := array[
    -- 대상
    ['대상: 6년·5년 1일·정확히 5년', 'pg', $q$select (':A'::uuid = any (l.target_ids) and ':E'::uuid = any (l.target_ids) and ':F'::uuid = any (l.target_ids))::text from privacy.access_logs l where l.fn = 'registry_purge_departed' and l.id > :a0 order by l.id limit 1$q$, 'true'],
    ['대상 아님: 재적·4년 11개월·재등록·하루 모자람', 'pg', $q$select (not exists (select 1 from privacy.access_logs l where l.fn = 'registry_purge_departed' and l.id > :a0 and l.target_ids && array[':B', ':C', ':D', ':G']::uuid[]))::text$q$, 'true'],
    ['두 번째 실행은 0명', 'pg', $q$select ':n2'$q$, '0'],
    ['파기 안 한 사람은 그대로', 'pg', $q$select count(*) filter (where p.purged_on is null) || '/' || (select phone from public.custom_users where id = ':B') from registry.people p where p.person_id in (':B', ':C', ':D', ':G')$q$, '4/010-9400-0002'],
    -- 지우는 것·남기는 것
    ['A 교적 칸 비움, 교번·파기일', 'pg', $q$select concat_ws('/', coalesce(p.name_note, '-'), p.birth_lunar, coalesce(p.address1, '-'), coalesce(p.occupation, '-'), coalesce(p.guide_name, '-'), coalesce(p.note, '-'), p.reg_no, (p.purged_on = ':today'::date)) from registry.people p where p.person_id = ':A'$q$, '-/f/-/-/-/-/TEST-PURGE-A/t'],
    ['A 앱 프로필: 이름·호칭만', 'pg', $q$select concat_ws('/', u.name, u.office, coalesce(u.phone, '-'), coalesce(u.birth_date::text, '-'), coalesce(u.gender, '-'), coalesce(u.email, '-')) from public.custom_users u where u.id = ':A'$q$, '테스트파기가/성도/-/-/-/-'],
    ['A 재적·신급·직분 이력 남음', 'pg', $q$select (select count(*) from registry.status_events where person_id = ':A') || '/' || (select count(*) from registry.faith_events where person_id = ':A') || '/' || (select count(*) from registry.office_terms where person_id = ':A')$q$, '2/1/1'],
    ['A 메모·디모데 메모·가져오기 행 지움', 'pg', $q$select (select count(*) from registry.notes where person_id = ':A') || '/' || (select count(*) from registry.legacy_memos where person_id = ':A') || '/' || (select count(*) from registry.import_rows where person_id = ':A')$q$, '0/0/0'],
    ['A 동의 기록 남고 대리인·비고만 지움', 'pg', $q$select count(*) || '/' || count(guardian_name) || '/' || count(note) from registry.consents where person_id = ':A'$q$, '1/0/0'],
    -- 세대
    ['같은 세대: A 연결만 끊김, 가족·주소 남음', 'pg', $q$select (select count(*) from registry.household_members where person_id = ':A') || '/' || (select string_agg(coalesce(cu.name, m.name), ',' order by m.sort_order) from registry.household_members m left join public.custom_users cu on cu.id = m.person_id where m.household_id = :h1) || '/' || (select address1 from registry.households where id = :h1)$q$, '0/테스트파기나,테스트자녀일/테스트시 세대로 1'],
    ['교인이 남지 않은 세대는 통째로', 'pg', $q$select (select count(*) from registry.households where id = :h2) || '/' || (select count(*) from registry.household_members where household_id = :h2)$q$, '0/0'],
    -- 앱 계정
    ['E 계정 있을 때: 교적 칸만, 전화는 둠', 'pg', $q$select ':e_mid'$q$, '-/010-9400-0005'],
    ['E 앱 탈퇴 뒤 다음 실행에서 전화 지움', 'pg', $q$select coalesce(phone, '-') || '/' || ':n3' from public.custom_users where id = ':E'$q$, '-/1'],
    -- 변경기록
    ['지난 변경기록에서 값 지움', 'pg', $q$select count(*)::text from privacy.change_logs l where l.person_id = ':A' and l.table_name not in ('registry.faith_events', 'registry.office_terms') and (l.old_data ?| array['phone', 'birth_date', 'address1', 'occupation', 'note', 'guardian_name', 'body'] or l.new_data ?| array['phone', 'birth_date', 'address1', 'occupation', 'note', 'guardian_name', 'body'])$q$, '0'],
    ['지난 변경기록의 남길 칸은 그대로', 'pg', $q$select (select count(*) from privacy.change_logs l where l.person_id = ':A' and l.table_name = 'registry.status_events' and l.new_data ->> 'kind' = 'transfer_out') || '/' || (select count(*) from privacy.change_logs l where l.person_id = ':A' and l.table_name in ('registry.faith_events', 'registry.office_terms') and l.new_data ? 'note') || '/' || (select count(*) from privacy.change_logs l where l.person_id = ':A' and l.table_name = 'public.custom_users' and l.op = 'UPDATE' and l.new_data = '{}')$q$, '1/2/1'],
    ['지운 세대의 변경기록도 값 지움', 'pg', $q$select count(*)::text from privacy.change_logs l where ((l.table_name = 'registry.households' and l.record_id = ':h2') or (l.table_name = 'registry.household_members' and coalesce(l.old_data, l.new_data) ->> 'household_id' = ':h2')) and (l.old_data is not null or l.new_data is not null)$q$, '0'],
    ['남은 세대의 변경기록은 그대로', 'pg', $q$select (select count(*) from privacy.change_logs l where l.table_name = 'registry.households' and l.record_id = ':h1' and l.new_data ->> 'address1' = '테스트시 세대로 1') || '/' || (select count(*) from privacy.change_logs l where l.person_id = ':B' and l.table_name = 'registry.household_members' and l.new_data is not null)$q$, '1/1'],
    ['파기하며 생긴 변경기록에는 값 없음', 'pg', $q$select count(*) filter (where l.old_data is not null or l.new_data is not null)::text from privacy.change_logs l where l.id > :c0$q$, '0'],
    ['A 파기 줄: 지운 앱 프로필 칸', 'pg', $q$select array_to_string(l.changed_fields, ',') from privacy.change_logs l where l.person_id = ':A' and l.op = 'PURGE'$q$, 'phone,birth_date,gender,email'],
    ['E 파기 줄 둘: 계정 있을 때 빈 칸, 탈퇴 뒤 전화', 'pg', $q$select string_agg(coalesce(nullif(array_to_string(l.changed_fields, ','), ''), '-'), '|' order by l.id) from privacy.change_logs l where l.person_id = ':E' and l.op = 'PURGE'$q$, '-|phone'],
    ['접속기록: delete·규칙·인원', 'pg', $q$select l.action || '/' || (l.detail ->> 'rule') || '/' || ((l.detail ->> 'count')::int = l.target_count) from privacy.access_logs l where l.fn = 'registry_purge_departed' and l.id > :a0 order by l.id limit 1$q$, 'delete/전출·별세·제적 후 5년/true'],
    -- 교인 카드
    ['카드: 파기일·빈 전화·세대 없음·재적 이력', 'viewer', $q$select ((c -> 'person' ->> 'purged_on') = ':today') || '/' || coalesce(c -> 'person' ->> 'phone', '-') || '/' || coalesce(c ->> 'household', '-') || '/' || jsonb_array_length(c -> 'status_events') from public.registry_card(':A') c$q$, 'true/-/-/2'],
    ['카드 변경 이력에 파기 줄', 'viewer', $q$select count(*)::text from jsonb_array_elements(public.registry_card(':A') -> 'history') h where h ->> 'op' = 'PURGE'$q$, '1'],
    -- 막는 것
    ['API 로 못 부름', 'pg', $q$select has_function_privilege('authenticated', 'registry.purge_departed(date)', 'execute')::text$q$, 'false'],
    ['매일 실행 예약', 'pg', $q$select schedule from cron.job where jobname = 'registry-purge-departed'$q$, '40 18 * * *'],
    ['변경기록 수정은 여전히 거절', 'pg', $q$with u as (update privacy.change_logs set old_data = null where id = (select max(id) from privacy.change_logs where person_id = ':B') returning 1) select count(*)::text from u$q$, 'ERR:추가만 할 수 있습니다'],
    ['파기 중이라도 다른 칸은 거절', 'pg', $q$with s as (select set_config('privacy.redacting', 'on', true) v), u as (update privacy.change_logs set table_name = 'x' where id = (select max(id) from privacy.change_logs where person_id = ':B') and (select v from s) = 'on' returning 1) select count(*)::text from u$q$, 'ERR:추가만 할 수 있습니다'],
    ['파기 중이라도 값 더하기는 거절', 'pg', $q$with s as (select set_config('privacy.redacting', 'on', true) v), u as (update privacy.change_logs set new_data = new_data || '{"x": 1}' where id = (select max(id) from privacy.change_logs where person_id = ':B' and new_data is not null) and (select v from s) = 'on' returning 1) select count(*)::text from u$q$, 'ERR:추가만 할 수 있습니다']
  ];
  t       text[];
  tok     jsonb := '{}';
  who     jsonb := '{}';
  sql     text;
  expect  text;
  got     text;
  k       text;
  sub     text;
  persona text;
  pass    int := 0;
  fail    int := 0;
  res     text := '';
  today   date := (now() at time zone 'Asia/Seoul')::date;
  v_view  record;
  e_auth  uuid := gen_random_uuid();
  v_a uuid; v_b uuid; v_c uuid; v_d uuid; v_e uuid; v_f uuid; v_g uuid;
  v_h1 bigint; v_h2 bigint;
begin
  alter table public.messages disable trigger "send-notification";

  -- 카드를 볼 교적 열람자: 교적 권한이 없는 가입 계정 하나
  select x.id, x.auth_id into v_view from public.custom_users x join public.roles r on r.id = x.role
   where r.level < 50 and x.active
     and exists (select 1 from auth.users a where a.id = x.auth_id)
     and not exists (select 1 from registry.staff s where s.user_id = x.id)
   order by x.id limit 1;
  if v_view.id is null then
    raise exception 'TEST_SETUP 대상을 고르지 못했습니다';
  end if;
  who := jsonb_build_object('viewer', v_view.auth_id::text);
  insert into registry.staff (user_id, note) values (v_view.id, 'TEST');

  insert into auth.users (id, aud, role, email) values (e_auth, 'authenticated', 'authenticated', 'purge-test@example.invalid');

  -- A
  insert into public.custom_users (name, phone, birth_date, gender, email, member, active)
  values ('테스트파기가', '010-9400-0001', '1970-01-01', '남', 'a@example.invalid', false, false) returning id into v_a;
  insert into registry.people (person_id, reg_no, name_note, birth_lunar, address1, occupation, guide_name, note)
  values (v_a, 'TEST-PURGE-A', '(큰)', true, '테스트시 파기로 1', '테스트직업', '테스트인도자', '테스트비고');
  insert into registry.status_events (person_id, kind, event_date)
  values (v_a, 'register', null), (v_a, 'transfer_out', (today - interval '6 years')::date);
  insert into registry.faith_events (person_id, kind, event_date) values (v_a, 'baptism', '1990-01-01');
  insert into registry.office_terms (person_id, office) values (v_a, 'deacon');
  insert into registry.notes (person_id, body) values (v_a, '테스트 메모 하나'), (v_a, '테스트 메모 둘');
  insert into registry.legacy_memos (person_id, source, src_id, body) values (v_a, 'dimode', 'TEST-PURGE-A', '테스트 디모데 메모');
  insert into registry.import_rows (src_id, data, name_key, person_id) values ('TEST-PURGE-A', '{"name": "테스트파기가"}', '테스트파기가', v_a);
  insert into registry.consents (person_id, kind, guardian_name, note) values (v_a, 'registry', '테스트대리인', '테스트동의비고');

  -- B, 그리고 A·B·교인 아닌 자녀의 세대
  insert into public.custom_users (name, phone, member, active) values ('테스트파기나', '010-9400-0002', true, false) returning id into v_b;
  insert into registry.people (person_id) values (v_b);
  insert into registry.status_events (person_id, kind) values (v_b, 'register');
  insert into registry.households (address1, home_phone) values ('테스트시 세대로 1', '032-000-0001') returning id into v_h1;
  insert into registry.household_members (household_id, person_id, relation, sort_order) values (v_h1, v_a, 'self', 1), (v_h1, v_b, 'spouse', 2);
  insert into registry.household_members (household_id, name, birth_year, relation, sort_order) values (v_h1, '테스트자녀일', 2000, 'child', 3);

  -- A 의 변경기록에 값 남기기: 주소 수정, 전화 수정
  update registry.people set address1 = '테스트시 파기로 2' where person_id = v_a;
  perform registry.log_profile_change(v_a, 'UPDATE', '{"phone": "010-9400-0009"}', '{"phone": "010-9400-0001"}');

  -- C, D
  insert into public.custom_users (name, phone, member, active) values ('테스트파기다', '010-9400-0003', false, false) returning id into v_c;
  insert into registry.people (person_id, address1) values (v_c, '테스트시 별세로 3');
  insert into registry.status_events (person_id, kind, event_date)
  values (v_c, 'register', null), (v_c, 'deceased', (today - interval '4 years 11 months')::date);
  insert into public.custom_users (name, phone, member, active) values ('테스트파기라', '010-9400-0004', true, false) returning id into v_d;
  insert into registry.people (person_id, address1) values (v_d, '테스트시 재등록로 4');
  insert into registry.status_events (person_id, kind, event_date)
  values (v_d, 'register', null), (v_d, 'removed', (today - interval '6 years')::date), (v_d, 'restore', (today - interval '1 year')::date);

  -- E: 앱 계정 있음, 혼자 세대 + 교인 아닌 가족
  insert into public.custom_users (name, phone, auth_id, member, active) values ('테스트파기마', '010-9400-0005', e_auth, false, true) returning id into v_e;
  insert into registry.people (person_id, occupation) values (v_e, '테스트직업마');
  insert into registry.status_events (person_id, kind, event_date)
  values (v_e, 'register', null), (v_e, 'transfer_out', (today - interval '5 years 1 day')::date);
  insert into registry.households (address1) values ('테스트시 혼자로 5') returning id into v_h2;
  insert into registry.household_members (household_id, person_id, relation) values (v_h2, v_e, 'self');
  insert into registry.household_members (household_id, name, relation) values (v_h2, '테스트가족마', 'parent');

  -- F, G: 5년 경계
  insert into public.custom_users (name, phone, member, active) values ('테스트파기바', '010-9400-0006', false, false) returning id into v_f;
  insert into registry.people (person_id) values (v_f);
  insert into registry.status_events (person_id, kind, event_date)
  values (v_f, 'register', null), (v_f, 'transfer_out', (today - interval '5 years')::date);
  insert into public.custom_users (name, phone, member, active) values ('테스트파기사', '010-9400-0007', false, false) returning id into v_g;
  insert into registry.people (person_id) values (v_g);
  insert into registry.status_events (person_id, kind, event_date)
  values (v_g, 'register', null), (v_g, 'transfer_out', (today - interval '5 years' + interval '1 day')::date);

  tok := jsonb_build_object(':A', v_a, ':B', v_b, ':C', v_c, ':D', v_d, ':E', v_e, ':F', v_f, ':G', v_g,
                            ':h1', v_h1::text, ':h2', v_h2::text, ':today', today::text,
                            ':a0', (select coalesce(max(l.id), 0)::text from privacy.access_logs l),
                            ':c0', (select coalesce(max(l.id), 0)::text from privacy.change_logs l));

  perform registry.purge_departed(today);
  tok := tok || jsonb_build_object(':n2', registry.purge_departed(today)::text);
  tok := tok || jsonb_build_object(':e_mid', (select coalesce(p.occupation, '-') || '/' || u.phone
                                                from registry.people p join public.custom_users u on u.id = p.person_id
                                               where p.person_id = v_e));
  -- E 앱 탈퇴: account_delete_prepare 처럼 계정 연결을 끊는다
  update public.custom_users set auth_id = gen_random_uuid() where id = v_e;
  tok := tok || jsonb_build_object(':n3', registry.purge_departed(today)::text);

  foreach t slice 1 in array tests loop
    sql := t[3];
    expect := t[4];
    for k in select key from jsonb_each_text(tok) order by length(key) desc loop
      sql := replace(sql, k, tok ->> k);
      expect := replace(expect, k, tok ->> k);
    end loop;
    persona := t[2];
    sub := who ->> 'viewer';
    got := null;
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', sub, 'role', 'authenticated', 'aal', 'aal2')::text, true);
      perform set_config('request.jwt.claim.sub', sub, true);
      if persona <> 'pg' then
        perform set_config('role', 'authenticated', true);
      end if;
      execute sql into got;
      perform set_config('role', 'none', true);
    exception when others then
      got := 'ERR:' || sqlerrm;
    end;
    got := coalesce(got, '(null)');
    if (expect = '*' and got not like 'ERR:%')
       or (left(expect, 4) = 'ERR:' and got like 'ERR:%' and position(substr(expect, 5) in got) > 0)
       or got = expect then
      pass := pass + 1;
    else
      fail := fail + 1;
      res := res || E'\n  FAIL ' || t[1] || ' — 기대 ' || expect || ' / 결과 ' || got;
    end if;
  end loop;

  perform set_config('role', 'none', true);
  raise exception 'TEST_RESULT (rolled back) pass=% fail=% %', pass, fail, res;
end
$test$;

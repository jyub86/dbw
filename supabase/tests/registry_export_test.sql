-- 교적 ④ 내려받기(20261012_registry_export) 테스트
--
-- 운영 DB에서 실행해도 된다. 마지막에 예외를 던져 모두 되돌린다. 결과는 'TEST_RESULT ...' 오류 메시지로 나온다.
-- 적용 전에는 마이그레이션 SQL 바로 뒤에 이 파일을 붙여 한 번에 실행한다.
-- 테스트 사람·세대는 '테스트…' 이름으로 테스트 안에서 만든다.

do $test$
declare
  tests text[] := array[
    -- 권한
    ['교적 권한 없음 → 거절', 'outsider', 'aal2', $q$select count(*)::text from public.registry_export('{}', array['phone'], '연락처 명단')$q$, 'ERR:교적 권한이 없습니다', ''],
    ['열람만 → 거절', 'viewer', 'aal2', $q$select count(*)::text from public.registry_export('{}', array['phone'], '연락처 명단')$q$, 'ERR:이 작업을 할 권한이 없습니다', ''],
    ['2단계 인증 전 → 거절', 'exporter', 'aal1', $q$select count(*)::text from public.registry_export('{}', array['phone'], '연락처 명단')$q$, 'ERR:2단계 인증이 필요합니다', ''],
    ['anon 실행 권한 없음', 'pg', '', $q$select has_function_privilege('anon', 'public.registry_export(jsonb,text[],text)', 'execute')::text$q$, 'false', ''],
    ['헬퍼는 API 로 못 부름', 'pg', '', $q$select has_function_privilege('authenticated', 'registry.filter_people(jsonb)', 'execute')::text$q$, 'false', ''],
    -- 입력 확인
    ['용도 없음 → 거절', 'exporter', 'aal2', $q$select count(*)::text from public.registry_export('{}', array['phone'], '  ')$q$, 'ERR:내려받는 용도를', ''],
    ['항목 없음 → 거절', 'exporter', 'aal2', $q$select count(*)::text from public.registry_export('{}', '{}', '연락처 명단')$q$, 'ERR:내려받을 항목을 골라', ''],
    ['없는 항목(메모) → 거절', 'exporter', 'aal2', $q$select count(*)::text from public.registry_export('{}', array['phone', 'note'], '연락처 명단')$q$, 'ERR:내려받을 수 없는 항목입니다: note', ''],
    ['빈 항목 → 거절', 'exporter', 'aal2', $q$select count(*)::text from public.registry_export('{}', array['phone', null], '연락처 명단')$q$, 'ERR:(빈 값)', ''],
    -- 내려받기
    ['고른 항목만 + 이름, 주소는 개인 > 세대', 'exporter', 'aal2', $q$select string_agg(j::text, '|' order by j ->> 'name') from public.registry_export('{"q":"테스트내보"}', array['phone', 'address'], '연락처 명단') j$q$,
      '{"name": "테스트내보가", "phone": "010-9300-0001", "address": "테스트시 가로 1 101호"}|{"name": "테스트내보나", "phone": "010-9300-0002", "address": "테스트구 개인로 2"}', ''],
    ['접속기록: 용도·인원·항목', 'pg', '', $q$select l.action || '/' || (l.detail ->> 'purpose') || '/' || (l.detail ->> 'count') || '/' || l.target_count || '/' || (l.detail -> 'columns')::text from privacy.access_logs l where l.fn = 'registry_export' and l.id > :a0 order by l.id desc limit 1$q$,
      'export/연락처 명단/2/2/["name", "phone", "address"]', ''],
    ['같은 항목 두 번 → 한 번', 'exporter', 'aal2', $q$select string_agg(k, ',' order by k) from (select distinct jsonb_object_keys(j) k from public.registry_export('{"q":"테스트내보"}', array['phone', 'phone'], '연락처 명단') j) x$q$, 'name,phone', ''],
    ['세대주·관계·우편번호·집전화', 'exporter', 'aal2', $q$select string_agg(concat_ws('/', j ->> 'name', j ->> 'head', j ->> 'relation', coalesce(j ->> 'zip', '-'), j ->> 'home_phone'), '|' order by j ->> 'name') from public.registry_export('{"q":"테스트내보"}', array['head', 'relation', 'zip', 'home_phone'], '세대 확인') j$q$,
      '테스트내보가/테스트내보가/self/12345/032-000-0000|테스트내보나/테스트내보가/spouse/-/032-000-0000', ''],
    ['나이·음력·생년월일', 'exporter', 'aal2', $q$select ((j ->> 'age')::int = extract(year from age(current_date, date '1980-05-05'))::int) || '/' || (j ->> 'birth_lunar') || '/' || (j ->> 'birth_date') from public.registry_export('{"q":"테스트내보가"}', array['age', 'birth_lunar', 'birth_date'], '나이 확인') j$q$,
      'true/true/1980-05-05', ''],
    ['조건에 맞는 사람이 없으면 0행, 기록은 남음', 'exporter', 'aal2', $q$select count(*)::text from public.registry_export('{"q":"테스트내보","status":["hold"]}', array['phone'], '빈 명단 확인') j$q$, '0', ''],
    ['빈 명단 기록', 'pg', '', $q$select (l.detail ->> 'count') || '/' || l.target_count from privacy.access_logs l where l.fn = 'registry_export' and l.id > :a0 order by l.id desc limit 1$q$, '0/0', ''],
    -- 목록(registry_search)은 헬퍼로 바꿔도 그대로
    ['검색: 이름 순·전체 수', 'viewer', 'aal2', $q$select string_agg(name, ',' order by name) || '/' || max(total) from public.registry_search('{"q":"테스트내보"}', 50, 0)$q$, '테스트내보가,테스트내보나/2', ''],
    ['검색: 쪽 나누기', 'viewer', 'aal2', $q$select string_agg(name, ',') || '/' || max(total) from public.registry_search('{"q":"테스트내보"}', 1, 1)$q$, '테스트내보나/2', ''],
    ['검색: 전화 숫자', 'viewer', 'aal2', $q$select string_agg(name, ',') from public.registry_search('{"q":"010-9300-0002"}', 50, 0)$q$, '테스트내보나', ''],
    ['검색: 상태 조건', 'viewer', 'aal2', $q$select count(*)::text from public.registry_search('{"q":"테스트내보","status":["hold"]}', 50, 0)$q$, '0', ''],
    ['검색: 성별 조건', 'viewer', 'aal2', $q$select string_agg(name, ',') from public.registry_search('{"q":"테스트내보","gender":"여"}', 50, 0)$q$, '테스트내보나', ''],
    ['검색: 기록은 search', 'pg', '', $q$select l.action || '/' || l.target_count from privacy.access_logs l where l.fn = 'registry_search' and l.id > :a0 order by l.id desc limit 1$q$, 'search/1', '']
  ];
  t      text[];
  tok    jsonb := '{}';
  who    jsonb := '{}';
  rec    record;
  sql    text;
  expect text;
  got    text;
  k      text;
  sub    text;
  persona text;
  pass   int := 0;
  fail   int := 0;
  res    text := '';
  i      int := 0;
  v_a    uuid;
  v_b    uuid;
  v_h    bigint;
begin
  alter table public.messages disable trigger "send-notification";

  -- 교적 권한이 없는 가입 계정 셋: 열람만 / 내려받기 / 권한 없음
  for rec in
    select x.id, x.auth_id from public.custom_users x join public.roles r on r.id = x.role
     where r.level < 50 and x.active
       and exists (select 1 from auth.users a where a.id = x.auth_id)
       and not exists (select 1 from registry.staff s where s.user_id = x.id)
     order by x.id limit 3
  loop
    i := i + 1;
    persona := (array['viewer', 'exporter', 'outsider'])[i];
    tok := tok || jsonb_build_object(':' || persona, rec.id::text);
    who := who || jsonb_build_object(persona, rec.auth_id::text);
  end loop;
  if i < 3 then
    raise exception 'TEST_SETUP 대상을 고르지 못했습니다';
  end if;

  -- 테스트 사람 둘과 세대: 가는 세대 주소를 쓰고, 나는 개인 주소가 있다
  insert into public.custom_users (name, phone, birth_date, gender, office, member, active)
  values ('테스트내보가', '010-9300-0001', '1980-05-05', '남', '집사', true, false) returning id into v_a;
  insert into registry.people (person_id, birth_lunar) values (v_a, true);
  insert into registry.status_events (person_id, kind, event_date) values (v_a, 'register', null);
  insert into public.custom_users (name, phone, gender, office, member, active)
  values ('테스트내보나', '010-9300-0002', '여', '성도', true, false) returning id into v_b;
  insert into registry.people (person_id, address1) values (v_b, '테스트구 개인로 2');
  insert into registry.status_events (person_id, kind, event_date) values (v_b, 'register', null);
  insert into registry.households (address_zip, address1, address2, home_phone)
  values ('12345', '테스트시 가로 1', '101호', '032-000-0000') returning id into v_h;
  insert into registry.household_members (household_id, person_id, relation, sort_order)
  values (v_h, v_a, 'self', 1), (v_h, v_b, 'spouse', 2);

  tok := tok || jsonb_build_object(':a0', (select coalesce(max(l.id), 0)::text from privacy.access_logs l));

  insert into registry.staff (user_id, can_export, note)
  values ((tok ->> ':viewer')::uuid, false, 'TEST'), ((tok ->> ':exporter')::uuid, true, 'TEST');

  foreach t slice 1 in array tests loop
    sql := t[4];
    expect := t[5];
    for k in select key from jsonb_each_text(tok) order by length(key) desc loop
      sql := replace(sql, k, tok ->> k);
      expect := replace(expect, k, tok ->> k);
    end loop;
    persona := t[2];
    sub := who ->> (case when persona = 'pg' then 'viewer' else persona end);
    got := null;
    begin
      perform set_config('request.jwt.claims',
        json_build_object('sub', sub, 'role', 'authenticated', 'aal', coalesce(nullif(t[3], ''), 'aal2'))::text, true);
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
    if t[6] <> '' and got not like 'ERR:%' then
      tok := tok || jsonb_build_object(t[6], got);
    end if;
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

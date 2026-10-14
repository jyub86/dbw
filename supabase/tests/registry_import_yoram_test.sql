-- 교적 ③-2 디모데 가져오기 + 요람 반영(20261012_registry_import_yoram) 테스트
--
-- 운영 DB에서 실행해도 된다. 마지막에 예외를 던져 모두 되돌린다. 결과는 'TEST_RESULT ...' 오류 메시지로 나온다.
-- 적용 전에는 마이그레이션 SQL 바로 뒤에 이 파일을 붙여 한 번에 실행한다.
-- 테스트 사람·행은 '테스트…' 이름으로 테스트 안에서 만든다. :gname 은 실제 목장 이름(사람 정보 아님)이다.

do $test$
declare
  rows_json text := $j$[
    {"src_id":"Y1","sheet":"main","data":{"name":"테스트일","status":"예배출석","mobile":"010-9200-0001","office_detail":"서리집사","yoram":{"group":":gname","office":"서리집사(여)","mobile":"01092000001"}}},
    {"src_id":"Y2","sheet":"main","data":{"name":"테스트이","status":"예배출석","yoram":{"group":":gname"}}},
    {"src_id":"Y3","sheet":"main","data":{"name":"테스트삼","status":"불출석","office_detail":"전입은퇴권사","yoram":{"group":":gname","office":"전입은퇴권사"}}},
    {"src_id":"Y4","sheet":"main","data":{"name":"테스트사"}},
    {"src_id":"Y5","sheet":"main","data":{"name":"테스트오","status":"예배출석","mobile":"010-9200-0055","mobile_dimode":"011-920-0005"}}
  ]$j$;
  tests text[] := array[
    ['admin: 올리기', 'admin', 'aal2', $q$select public.registry_import_load(:rows)::text$q$, '5', ''],
    ['요람 목장이 같으면 이름만 같아도 strong (생일·전화 없는 프로필)', 'pg', '', $q$select (candidates -> 0 ->> 'kind') || '/' || suggestion || '/' || ((candidates -> 0 ->> 'person_id') = ':p1') from registry.import_rows where src_id = 'Y1'$q$, 'strong/link/true', ''],
    ['목장이 다르면 이름만 → 확인 필요', 'pg', '', $q$select (candidates -> 0 ->> 'kind') || '/' || suggestion from registry.import_rows where src_id = 'Y2'$q$, 'name/review', ''],
    ['후보 없고 요람에 있으면 새 교적 후보 (디모데 불출석이어도)', 'pg', '', $q$select suggestion from registry.import_rows where src_id = 'Y3'$q$, 'new', ''],
    ['후보 없고 요람에도 없고 출석도 아니면 확인 필요', 'pg', '', $q$select suggestion from registry.import_rows where src_id = 'Y4'$q$, 'review', ''],
    ['디모데 옛 휴대폰으로도 전화 대조', 'pg', '', $q$select (candidates -> 0 ->> 'kind') || '/' || suggestion || '/' || ((candidates -> 0 ->> 'person_id') = ':p5') from registry.import_rows where src_id = 'Y5'$q$, 'strong/link/true', ''],
    ['행 번호 Y3', 'pg', '', $q$select id::text from registry.import_rows where src_id = 'Y3'$q$, '*', ':r3'],
    ['editor: 제안 확정', 'editor', 'aal2', $q$select public.registry_import_accept()::text$q$, '2', ''],
    ['editor: Y3 새 교적', 'editor', 'aal2', $q$select 'ok' from (select public.registry_import_decide(:r3, 'new')) x$q$, 'ok', ''],
    ['editor: 반영', 'editor', 'aal2', $q$select (j ->> 'rows') || '/' || (j ->> 'created') from (select public.registry_import_apply(100) j) x$q$, '3/1', ''],
    ['Y1: 미가입 프로필의 빈 전화를 요람 번호로 채움', 'pg', '', $q$select phone from public.custom_users where id = ':p1'$q$, '010-9200-0001', ''],
    ['Y3: 전입은퇴권사 → 권사(은퇴), 호칭 은퇴권사', 'pg', '', $q$select t.office || ':' || t.standing || '/' || u.office from public.custom_users u join registry.office_terms t on t.person_id = u.id where u.name = '테스트삼'$q$, 'kwonsa:retired/은퇴권사', ''],
    ['변환: 요람 직분 표기', 'pg', '', $q$select string_agg(coalesce(o.code, '-') || ':' || coalesce(o.standing, '-'), ',' order by v.i) from (values (1, '서리집사(여)'), (2, '은퇴집사'), (3, '전입은퇴권사'), (4, '은퇴협동장로'), (5, '휴직장로'), (6, '명예집사(남)'), (7, '전입안수집사'), (8, '은퇴전도사')) v(i, a), lateral registry.dimode_office(null, v.a) o$q$, 'deacon:serving,ordained_deacon:retired,kwonsa:retired,elder:retired,-:-,deacon:honorary,ordained_deacon:serving,evangelist:retired', '']
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
  picked uuid[] := '{}';
  v_id   uuid;
  v_gid  bigint;
  v_gname text;
begin
  alter table public.messages disable trigger "send-notification";

  select tok || jsonb_build_object(':admin', u.id::text), who || jsonb_build_object('admin', u.auth_id::text), picked || u.id
    into tok, who, picked
    from public.custom_users u join public.roles r on r.id = u.role
   where r.level >= 100 and u.active and exists (select 1 from auth.users a where a.id = u.auth_id)
   order by u.id limit 1;
  for rec in
    select x.id, x.auth_id from public.custom_users x join public.roles r on r.id = x.role
     where r.level < 50 and x.active
       and exists (select 1 from auth.users a where a.id = x.auth_id)
       and not exists (select 1 from registry.staff s where s.user_id = x.id)
     order by x.id limit 1
  loop
    tok := tok || jsonb_build_object(':editor', rec.id::text);
    who := who || jsonb_build_object('editor', rec.auth_id::text);
  end loop;
  select s.id, s.name into v_gid, v_gname from public.small_groups s where s.active order by s.id limit 1;
  if tok ->> ':admin' is null or tok ->> ':editor' is null or v_gid is null then
    raise exception 'TEST_SETUP 대상을 고르지 못했습니다';
  end if;

  -- 테스트 사람: 목장에 있는 미가입 교적(전화·생일 없음) / 다른 목장의 같은 이름 계열 / 옛 번호를 가진 사람
  insert into public.custom_users (name, office, member, active) values ('테스트일', '집사', true, false) returning id into v_id;
  insert into registry.people (person_id) values (v_id);
  insert into registry.status_events (person_id, kind, event_date) values (v_id, 'register', null);
  perform registry.office_from_profile(v_id);
  insert into public.small_group_members (small_group_id, user_id) values (v_gid, v_id);
  tok := tok || jsonb_build_object(':p1', v_id::text);
  insert into public.custom_users (name, office, member, active) values ('테스트이', '성도', true, false) returning id into v_id;
  insert into registry.people (person_id) values (v_id);
  insert into registry.status_events (person_id, kind, event_date) values (v_id, 'register', null);
  tok := tok || jsonb_build_object(':p2', v_id::text);
  insert into public.custom_users (name, phone, office, member, active) values ('테스트오', '011-920-0005', '성도', true, false) returning id into v_id;
  insert into registry.people (person_id) values (v_id);
  insert into registry.status_events (person_id, kind, event_date) values (v_id, 'register', null);
  tok := tok || jsonb_build_object(':p5', v_id::text);

  rows_json := replace(rows_json, ':gname', v_gname);
  tok := tok || jsonb_build_object(':a0', (select coalesce(max(l.id), 0)::text from privacy.access_logs l),
                                   ':rows', quote_literal(rows_json));

  insert into registry.staff (user_id, can_edit, note)
  values ((tok ->> ':editor')::uuid, true, 'TEST'), ((tok ->> ':admin')::uuid, true, 'TEST')
  on conflict (user_id) do update set can_edit = true;

  -- 교적 비밀번호(20261014_registry_password): 세션 칸이 aal2 면 비밀번호로 연 세션, aal1 이면 열지 않은 세션
  insert into registry.unlocks (session_id, auth_id)
  select md5(w.value || 'aal2')::uuid, w.value::uuid from jsonb_each_text(who) w
   where exists (select 1 from auth.users a where a.id = w.value::uuid);

  foreach t slice 1 in array tests loop
    sql := t[4];
    expect := t[5];
    for k in select key from jsonb_each_text(tok) order by length(key) desc loop
      sql := replace(sql, k, tok ->> k);
      expect := replace(expect, k, tok ->> k);
    end loop;
    persona := t[2];
    sub := who ->> (case when persona = 'pg' then 'editor' else persona end);
    got := null;
    begin
      perform set_config('request.jwt.claims',
        json_build_object('sub', sub, 'role', 'authenticated', 'session_id', md5(sub || coalesce(nullif(t[3], ''), 'aal2'))::uuid)::text, true);
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

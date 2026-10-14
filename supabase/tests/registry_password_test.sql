-- 교적 비밀번호(20261014_registry_password) 테스트
--
-- 운영 DB에서 실행해도 된다. 마지막에 예외를 던져 모두 되돌린다. 결과는 'TEST_RESULT ...' 오류 메시지로 나온다.
-- 적용 전에는 마이그레이션 SQL 바로 뒤에 이 파일을 붙여 한 번에 실행한다.
-- [이름, 사람, 세션, SQL, 기대값]  세션은 JWT session_id = md5(auth_id || 세션) 으로 만든다. 빈 칸이면 session_id 가 없는 토큰.
-- 기대값 '*' 는 오류만 아니면 통과, 'ERR:…' 는 그 문구가 들어간 오류.

do $test$
declare
  tests text[] := array[
    -- 권한 없는 사람
    ['권한 없음: 정하기 거절', 'outsider', 's1', $q$select 'ok' from (select public.registry_password_set('Church2026')) x$q$, 'ERR:교적 권한이 없습니다'],
    ['권한 없음: 넣기 거절', 'outsider', 's1', $q$select public.registry_unlock('Church2026')::text$q$, 'ERR:교적 권한이 없습니다'],
    ['권한 없음: 내 권한', 'outsider', 's1', $q$select concat_ws('/', me ->> 'is_staff', me ->> 'password_set', me ->> 'unlocked') from (select public.registry_me() me) x$q$, 'false/false/false'],

    -- 처음 들어갈 때
    ['처음: 정하지 않음·닫힘', 'viewer', 's1', $q$select concat_ws('/', me ->> 'password_required', me ->> 'password_set', me ->> 'locked_out', me ->> 'unlocked') from (select public.registry_me() me) x$q$, 'true/false/false/false'],
    ['처음: 교적 함수 거절', 'viewer', 's1', $q$select count(*)::text from public.registry_search('{}', 1, 0)$q$, 'ERR:교적 비밀번호를 넣어 주세요'],
    ['처음: 넣기 → 정하지 않음', 'viewer', 's1', $q$select public.registry_unlock('Church2026') ->> 'reason'$q$, 'not_set'],
    ['규칙: 7자', 'viewer', 's1', $q$select 'ok' from (select public.registry_password_set('Abc1234')) x$q$, 'ERR:8자 이상'],
    ['규칙: 숫자만', 'viewer', 's1', $q$select 'ok' from (select public.registry_password_set('12345678')) x$q$, 'ERR:영문과 숫자를'],
    ['규칙: 영문만', 'viewer', 's1', $q$select 'ok' from (select public.registry_password_set('abcdefgh')) x$q$, 'ERR:영문과 숫자를'],
    ['규칙: 빈 값', 'viewer', 's1', $q$select 'ok' from (select public.registry_password_set(null)) x$q$, 'ERR:8자 이상'],
    ['규칙: 66자', 'viewer', 's1', $q$select 'ok' from (select public.registry_password_set(repeat('a1', 33))) x$q$, 'ERR:64자까지'],
    ['세션 없는 토큰: 정하기 거절', 'viewer', '', $q$select 'ok' from (select public.registry_password_set('Church2026')) x$q$, 'ERR:로그인을 다시 해 주세요'],
    ['세션 없는 토큰: 저장 안 됨', 'pg', '', $q$select count(*)::text from registry.passwords where auth_id = ':viewer_auth'$q$, '0'],
    ['정하기', 'viewer', 's1', $q$select 'ok' from (select public.registry_password_set('Church2026')) x$q$, 'ok'],
    ['정한 뒤: 열림', 'viewer', 's1', $q$select concat_ws('/', me ->> 'password_required', me ->> 'password_set', me ->> 'locked_out', me ->> 'unlocked') from (select public.registry_me() me) x$q$, 'true/true/false/true'],
    ['정한 뒤: 교적 함수 허용', 'viewer', 's1', $q$select count(*)::text from public.registry_search('{}', 1, 0)$q$, '*'],
    ['다시 정하기 거절', 'viewer', 's1', $q$select 'ok' from (select public.registry_password_set('Other2026')) x$q$, 'ERR:이미 교적 비밀번호를 정했습니다'],
    ['저장: bcrypt, 원문 없음', 'pg', '', $q$select (hash like '$2a$10$%' and position('Church2026' in hash) = 0)::text from registry.passwords where auth_id = ':viewer_auth'$q$, 'true'],

    -- 다른 로그인 세션
    ['다른 세션: 닫힘', 'viewer', 's2', $q$select count(*)::text from public.registry_search('{}', 1, 0)$q$, 'ERR:교적 비밀번호를 넣어 주세요'],
    ['다른 세션: 틀림 → 4번 남음', 'viewer', 's2', $q$select concat_ws('/', r ->> 'ok', r ->> 'reason', r ->> 'left') from (select public.registry_unlock('church2026') r) x$q$, 'false/wrong/4'],
    ['다른 세션: 맞힘', 'viewer', 's2', $q$select public.registry_unlock('Church2026') ->> 'ok'$q$, 'true'],
    ['맞히면 틀린 횟수 0', 'pg', '', $q$select failed::text from registry.passwords where auth_id = ':viewer_auth'$q$, '0'],
    ['다른 세션: 허용', 'viewer', 's2', $q$select count(*)::text from public.registry_search('{}', 1, 0)$q$, '*'],
    ['쓰는 중: 늘리기', 'viewer', 's2', $q$select public.registry_touch()::text$q$, 'true'],

    -- 쓰지 않고 30분
    ['30분 지남', 'pg', '', $q$with u as (update registry.unlocks set last_seen = now() - interval '31 minutes' where session_id = md5(':viewer_auth' || 's2')::uuid returning 1) select count(*)::text from u$q$, '1'],
    ['30분 지남: 거절', 'viewer', 's2', $q$select count(*)::text from public.registry_search('{}', 1, 0)$q$, 'ERR:교적 비밀번호를 넣어 주세요'],
    ['30분 지남: 늘리기로 못 살림', 'viewer', 's2', $q$select public.registry_touch()::text$q$, 'false'],
    ['30분 지남: 내 권한 닫힘', 'viewer', 's2', $q$select public.registry_me() ->> 'unlocked'$q$, 'false'],
    ['처음 세션은 그대로 열림', 'viewer', 's1', $q$select count(*)::text from public.registry_search('{}', 1, 0)$q$, '*'],

    -- 잠그기
    ['잠그기', 'viewer', 's1', $q$select 'ok' from (select public.registry_lock()) x$q$, 'ok'],
    ['잠근 뒤 거절', 'viewer', 's1', $q$select count(*)::text from public.registry_search('{}', 1, 0)$q$, 'ERR:교적 비밀번호를 넣어 주세요'],
    ['다시 열기', 'viewer', 's1', $q$select public.registry_unlock('Church2026') ->> 'ok'$q$, 'true'],

    -- 5번 틀리면 잠김
    ['틀림 1', 'viewer', 's3', $q$select concat_ws('/', r ->> 'ok', r ->> 'reason', r ->> 'left') from (select public.registry_unlock('wrong1') r) x$q$, 'false/wrong/4'],
    ['틀림 2', 'viewer', 's3', $q$select concat_ws('/', r ->> 'ok', r ->> 'reason', r ->> 'left') from (select public.registry_unlock('wrong2') r) x$q$, 'false/wrong/3'],
    ['틀림 3', 'viewer', 's3', $q$select concat_ws('/', r ->> 'ok', r ->> 'reason', r ->> 'left') from (select public.registry_unlock('wrong3') r) x$q$, 'false/wrong/2'],
    ['틀림 4', 'viewer', 's3', $q$select concat_ws('/', r ->> 'ok', r ->> 'reason', r ->> 'left') from (select public.registry_unlock(null) r) x$q$, 'false/wrong/1'],
    ['틀림 5 → 잠김', 'viewer', 's3', $q$select concat_ws('/', r ->> 'ok', r ->> 'reason', r ->> 'left') from (select public.registry_unlock('wrong5') r) x$q$, 'false/locked/0'],
    ['잠긴 뒤: 맞는 비밀번호도 거절', 'viewer', 's3', $q$select concat_ws('/', r ->> 'ok', r ->> 'reason', r ->> 'left') from (select public.registry_unlock('Church2026') r) x$q$, 'false/locked/0'],
    ['잠기면 열려 있던 세션도 닫힘', 'viewer', 's1', $q$select count(*)::text from public.registry_search('{}', 1, 0)$q$, 'ERR:교적 비밀번호를 넣어 주세요'],
    ['잠긴 상태: 내 권한', 'viewer', 's1', $q$select concat_ws('/', me ->> 'password_required', me ->> 'password_set', me ->> 'locked_out', me ->> 'unlocked') from (select public.registry_me() me) x$q$, 'true/true/true/false'],

    -- 사이트 관리자 초기화
    ['관리자: 비밀번호 전에는 초기화 거절', 'admin', 'a1', $q$select 'ok' from (select public.registry_password_reset(':viewer')) x$q$, 'ERR:교적 비밀번호를 넣어 주세요'],
    ['관리자: 비밀번호 전에는 목록 거절', 'admin', 'a1', $q$select count(*)::text from public.registry_staff_list()$q$, 'ERR:교적 비밀번호를 넣어 주세요'],
    ['관리자: 정하기', 'admin', 'a1', $q$select 'ok' from (select public.registry_password_set('Admin2026x')) x$q$, 'ok'],
    ['관리자: 목록에 잠김 표시', 'admin', 'a1', $q$select password from public.registry_staff_list() where user_id = ':viewer'$q$, 'locked'],
    ['권한 없음: 초기화 거절', 'outsider', 's1', $q$select 'ok' from (select public.registry_password_reset(':viewer')) x$q$, 'ERR:사이트 관리자만'],
    ['담당자: 초기화 거절', 'viewer', 's1', $q$select 'ok' from (select public.registry_password_reset(':viewer')) x$q$, 'ERR:사이트 관리자만'],
    ['관리자: 없는 대상 거절', 'admin', 'a1', $q$select 'ok' from (select public.registry_password_reset(gen_random_uuid())) x$q$, 'ERR:대상을 찾지 못했습니다'],
    ['관리자: 초기화', 'admin', 'a1', $q$select 'ok' from (select public.registry_password_reset(':viewer')) x$q$, 'ok'],
    ['초기화 뒤: 목록에 안 정함', 'admin', 'a1', $q$select password from public.registry_staff_list() where user_id = ':viewer'$q$, 'none'],
    ['초기화 뒤: 다시 정하기', 'viewer', 's4', $q$select 'ok' from (select public.registry_password_set('NewPass2026')) x$q$, 'ok'],
    ['초기화 뒤: 새 비밀번호로 열림', 'viewer', 's4', $q$select concat_ws('/', me ->> 'password_set', me ->> 'locked_out', me ->> 'unlocked') from (select public.registry_me() me) x$q$, 'true/false/true'],
    ['초기화 뒤: 옛 비밀번호 틀림', 'viewer', 's5', $q$select public.registry_unlock('Church2026') ->> 'reason'$q$, 'wrong'],

    -- 장애 대응 스위치
    ['스위치 끄기', 'pg', '', $q$with u as (update registry.settings set require_password = false returning 1) select count(*)::text from u$q$, '1'],
    ['스위치 꺼지면 비밀번호 없이 허용', 'viewer', 's9', $q$select count(*)::text from public.registry_search('{}', 1, 0)$q$, '*'],
    ['스위치 켜기', 'pg', '', $q$with u as (update registry.settings set require_password = true returning 1) select count(*)::text from u$q$, '1'],
    ['스위치 켜면 다시 거절', 'viewer', 's9', $q$select count(*)::text from public.registry_search('{}', 1, 0)$q$, 'ERR:교적 비밀번호를 넣어 주세요'],

    -- 기록과 노출
    ['접속기록: 정하기·맞힘·틀림·잠김·초기화', 'pg', '', $q$select string_agg(replace(fn, 'registry_', '') || ':' || (detail ->> 'result'), ',' order by id) from privacy.access_logs where id > :a0 and action = 'auth'$q$,
     'password_set:set,unlock:wrong,unlock:ok,unlock:ok,unlock:wrong,unlock:wrong,unlock:wrong,unlock:wrong,unlock:locked,unlock:blocked,password_set:set,password_reset:reset,password_set:set,unlock:wrong'],
    ['접속기록: 초기화 대상·처리자', 'pg', '', $q$select (target_ids = array[':viewer'::uuid] and actor_user_id = ':admin')::text from privacy.access_logs where id > :a0 and fn = 'registry_password_reset'$q$, 'true'],
    ['접속기록: 비밀번호 원문 없음', 'pg', '', $q$select count(*)::text from privacy.access_logs where id > :a0 and (detail::text like '%Church2026%' or detail::text like '%wrong1%')$q$, '0'],
    ['API: 비밀번호 표 직접 조회 불가', 'viewer', 's4', $q$select count(*)::text from registry.passwords$q$, 'ERR:permission denied for schema registry'],
    ['anon: 넣기 실행 불가', 'anon', '', $q$select public.registry_unlock('Church2026')::text$q$, 'ERR:permission denied for function registry_unlock'],
    ['anon: 초기화 실행 불가', 'anon', '', $q$select 'ok' from (select public.registry_password_reset(':viewer')) x$q$, 'ERR:permission denied for function registry_password_reset'],
    ['2단계 인증 함수 없어짐', 'pg', '', $q$select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'registry' and p.proname = 'require_mfa'$q$, '0'],
    ['기존 데이터 영향 없음: 사람 수', 'pg', '', $q$select count(*)::text from public.custom_users$q$, ':cu0']
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
  claims jsonb;
  pass   int := 0;
  fail   int := 0;
  res    text := '';
  i      int := 0;
begin
  -- 대상 계정 (ID 만): 사이트 관리자 하나, 교적 권한이 없는 가입 계정 둘
  select tok || jsonb_build_object(':admin', u.id::text, ':admin_auth', u.auth_id::text), who || jsonb_build_object('admin', u.auth_id::text)
    into tok, who
    from public.custom_users u join public.roles r on r.id = u.role
   where r.level >= 100 and u.active and exists (select 1 from auth.users a where a.id = u.auth_id)
   order by u.id limit 1;
  for rec in
    select x.id, x.auth_id from public.custom_users x join public.roles r on r.id = x.role
     where r.level < 50 and x.active
       and exists (select 1 from auth.users a where a.id = x.auth_id)
       and not exists (select 1 from registry.staff s where s.user_id = x.id)
     order by x.id limit 2
  loop
    i := i + 1;
    k := (array['viewer', 'outsider'])[i];
    tok := tok || jsonb_build_object(':' || k, rec.id::text, ':' || k || '_auth', rec.auth_id::text);
    who := who || jsonb_build_object(k, rec.auth_id::text);
  end loop;
  if i < 2 or tok ->> ':admin' is null then
    raise exception 'TEST_SETUP 대상 계정을 고르지 못했습니다';
  end if;
  tok := tok || jsonb_build_object(
    ':a0',  (select coalesce(max(l.id), 0)::text from privacy.access_logs l),
    ':cu0', (select count(*)::text from public.custom_users));

  insert into registry.staff (user_id, note) values ((tok ->> ':viewer')::uuid, 'TEST');

  foreach t slice 1 in array tests loop
    sql := t[4];
    expect := t[5];
    for k in select key from jsonb_each_text(tok) order by length(key) desc loop
      sql := replace(sql, k, tok ->> k);
      expect := replace(expect, k, tok ->> k);
    end loop;
    sub := who ->> (case when t[2] in ('pg', 'anon') then 'viewer' else t[2] end);
    got := null;
    begin
      if t[2] = 'anon' then
        perform set_config('request.jwt.claims', '{"role":"anon"}', true);
        perform set_config('request.jwt.claim.sub', '', true);
        perform set_config('role', 'anon', true);
      else
        -- aal 은 이제 보지 않는다 (인증 앱 없이 aal1)
        claims := jsonb_build_object('sub', sub, 'role', 'authenticated', 'aal', 'aal1');
        if t[3] <> '' then
          claims := claims || jsonb_build_object('session_id', md5(sub || t[3])::uuid);
        end if;
        perform set_config('request.jwt.claims', claims::text, true);
        perform set_config('request.jwt.claim.sub', sub, true);
        if t[2] <> 'pg' then
          perform set_config('role', 'authenticated', true);
        end if;
      end if;
      perform set_config('request.headers', '{"cf-connecting-ip":"203.0.113.7","user-agent":"registry-test"}', true);
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

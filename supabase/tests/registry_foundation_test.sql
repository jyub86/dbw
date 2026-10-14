-- 교적 기반(20261010_registry_foundation) 역할별 테스트
--
-- 운영 DB에서 실행해도 된다. 마지막에 예외를 던져 테스트 중 바뀐 것을 모두 되돌린다.
-- 결과는 오류 메시지 'TEST_RESULT ...' 로 나온다.
-- 마이그레이션 적용 전에는 마이그레이션 SQL 바로 뒤에 이 파일을 붙여 한 번에 실행한다(함께 되돌려진다).
--
-- 대상 계정은 ID 로만 고른다(교인 데이터의 내용은 읽지 않는다).
--   admin    : 사이트 관리자 1명
--   editor   : 일반 계정 → 테스트 중 '수정·내려받기' 교적 권한을 받음
--   viewer   : 일반 계정 → 테스트 중 '열람' 교적 권한을 받았다가 해제됨
--   outsider : 일반 계정, 교적 권한 없음 (교적 테스트 대상 교인으로도 쓴다)
--   pg       : DB 소유자(postgres). 로그인 토큰은 editor 로 둔다
--   anon     : 비로그인

do $test$
declare
  -- [이름, 역할, aal, SQL, 기대값]  기대값이 'ERR:…' 이면 그 문구가 들어간 오류를 기대한다
  tests text[] := array[
    ['anon: 내 권한 함수 실행 불가', 'anon', '', $q$select public.registry_me()::text$q$, 'ERR:permission denied'],
    ['anon: 권한 부여 함수 실행 불가', 'anon', '', $q$select 'ok' from (select public.registry_staff_set(':editor', true, true, true)) x$q$, 'ERR:permission denied'],
    ['anon: 접속기록 함수 실행 불가', 'anon', '', $q$select count(*)::text from public.privacy_access_logs()$q$, 'ERR:permission denied'],
    ['outsider: 내 권한 = 담당자 아님', 'outsider', 'aal1', $q$select public.registry_me() ->> 'is_staff'$q$, 'false'],
    ['outsider: registry 테이블 직접 조회 불가', 'outsider', 'aal2', $q$select count(*)::text from registry.staff$q$, 'ERR:permission denied for schema registry'],
    ['outsider: privacy 테이블 직접 조회 불가', 'outsider', 'aal2', $q$select count(*)::text from privacy.access_logs$q$, 'ERR:permission denied for schema privacy'],
    ['outsider: 교적 함수 거절', 'outsider', 'aal2', $q$select public._t_registry('view', ':outsider')$q$, 'ERR:교적 권한이 없습니다'],
    ['outsider: 권한 부여 거절', 'outsider', 'aal2', $q$select 'ok' from (select public.registry_staff_set(':outsider', true, true, true)) x$q$, 'ERR:사이트 관리자만'],
    ['outsider: 담당자 목록 거절', 'outsider', 'aal2', $q$select count(*)::text from public.registry_staff_list()$q$, 'ERR:사이트 관리자만'],
    ['admin aal1: 권한 부여 → 교적 비밀번호 요구', 'admin', 'aal1', $q$select 'ok' from (select public.registry_staff_set(':editor', true, true, false)) x$q$, 'ERR:교적 비밀번호를 넣어 주세요'],
    ['admin: 관리자라도 교적 권한은 자동으로 없음', 'admin', 'aal2', $q$select public._t_registry('view', ':outsider')$q$, 'ERR:교적 권한이 없습니다'],
    ['admin: editor 에게 수정·내려받기 부여', 'admin', 'aal2', $q$select 'ok' from (select public.registry_staff_set(':editor', true, true, false, 'TEST')) x$q$, 'ok'],
    ['admin: viewer 에게 열람 부여', 'admin', 'aal2', $q$select 'ok' from (select public.registry_staff_set(':viewer', false, false, false, 'TEST')) x$q$, 'ok'],
    ['admin: 미가입 프로필에 부여 거절', 'admin', 'aal2', $q$select 'ok' from (select public.registry_staff_set(':placeholder', false, false, false, 'TEST')) x$q$, 'ERR:가입한 계정에만'],
    ['admin: 같은 값으로 다시 저장', 'admin', 'aal2', $q$select 'ok' from (select public.registry_staff_set(':viewer', false, false, false, 'TEST')) x$q$, 'ok'],
    ['권한 이력: 부여 2건 (같은 값 재저장은 안 남음)', 'pg', '', $q$select count(*) filter (where op = 'grant') || '/' || count(*) from privacy.permission_logs where id > :p0$q$, '2/2'],
    ['권한 이력: 처리자 = admin', 'pg', '', $q$select count(*)::text from privacy.permission_logs where id > :p0 and actor_user_id = ':admin'$q$, '2'],
    ['admin: 담당자 목록', 'admin', 'aal2', $q$select count(*)::text from public.registry_staff_list() where note = 'TEST'$q$, '2'],
    ['viewer: 내 권한', 'viewer', 'aal1', $q$select (public.registry_me() ->> 'is_staff') || '/' || (public.registry_me() ->> 'can_edit') || '/' || (public.registry_me() ->> 'unlocked')$q$, 'true/false/false'],
    ['viewer aal1: 열람 → 교적 비밀번호 요구', 'viewer', 'aal1', $q$select public._t_registry('view', ':outsider')$q$, 'ERR:교적 비밀번호를 넣어 주세요'],
    ['viewer: 열람', 'viewer', 'aal2', $q$select public._t_registry('view', ':outsider')$q$, 'ok'],
    ['viewer: 수정 거절', 'viewer', 'aal2', $q$select public._t_registry('edit', ':outsider')$q$, 'ERR:이 작업을 할 권한이 없습니다'],
    ['viewer: 내려받기 거절', 'viewer', 'aal2', $q$select public._t_registry('export', ':outsider')$q$, 'ERR:이 작업을 할 권한이 없습니다'],
    ['editor: 수정', 'editor', 'aal2', $q$select public._t_registry('edit', ':outsider')$q$, 'ok'],
    ['editor: 내려받기', 'editor', 'aal2', $q$select public._t_registry('export', ':outsider')$q$, 'ok'],
    ['editor: 심방 거절', 'editor', 'aal2', $q$select public._t_registry('pastoral', ':outsider')$q$, 'ERR:이 작업을 할 권한이 없습니다'],
    ['접속기록: 성공한 3건만 남음', 'pg', '', $q$select count(*)::text from privacy.access_logs where id > :a0$q$, '3'],
    ['접속기록: IP·브라우저·처리자·대상', 'pg', '', $q$select string_agg(distinct ip, ',') || '/' || string_agg(distinct user_agent, ',') || '/' || count(actor_name) || '/' || sum(target_count) from privacy.access_logs where id > :a0$q$, '203.0.113.7/registry-test/3/3'],
    ['접속기록: 작업 종류', 'pg', '', $q$select string_agg(action, ',' order by id) from privacy.access_logs where id > :a0$q$, 'view,update,export'],
    ['접속기록: 수정 불가 (DB 소유자도)', 'pg', '', $q$with u as (update privacy.access_logs set fn = fn where id > :a0 returning 1) select count(*)::text from u$q$, 'ERR:추가만'],
    ['접속기록: 삭제 불가', 'pg', '', $q$with d as (delete from privacy.access_logs where id > :a0 returning 1) select count(*)::text from d$q$, 'ERR:추가만'],
    ['접속기록: 비우기 불가', 'pg', '', $q$EXEC truncate privacy.access_logs$q$, 'ERR:추가만'],
    ['접속기록: 정리 모드여도 보관 기간 안 지난 행은 삭제 불가', 'pg', '', $q$with s as (select set_config('privacy.purging', 'on', true) v), d as (delete from privacy.access_logs where id > :a0 and (select v from s) = 'on' returning 1) select count(*)::text from d$q$, 'ERR:추가만'],
    ['정기 정리 함수 실행', 'pg', '', $q$select 'ok' from (select privacy.purge_expired()) x$q$, 'ok'],
    ['정리 후에도 최근 기록 유지', 'pg', '', $q$select count(*)::text from privacy.access_logs where id > :a0$q$, '3'],
    ['정리 작업 예약됨', 'pg', '', $q$select count(*)::text from cron.job where jobname = 'privacy-purge-expired'$q$, '1'],
    ['viewer: 접속기록 열람 거절', 'viewer', 'aal2', $q$select count(*)::text from public.privacy_access_logs()$q$, 'ERR:사이트 관리자만'],
    ['admin: 접속기록 열람 (기존 3건 + 열람 자체 1건 이상)', 'admin', 'aal2', $q$select (count(*) >= 4)::text from public.privacy_access_logs()$q$, 'true'],
    ['admin: 열람도 기록됨', 'pg', '', $q$select count(*)::text from privacy.access_logs where id > :a0 and fn = 'privacy_access_logs'$q$, '1'],
    ['admin: 대상 교인으로 접속기록 찾기', 'admin', 'aal2', $q$select count(*)::text from public.privacy_access_logs(p_target => ':outsider') where fn = '_t_registry'$q$, '3'],
    ['admin: 권한 변경', 'admin', 'aal2', $q$select 'ok' from (select public.registry_staff_set(':viewer', false, true, false, 'TEST')) x$q$, 'ok'],
    ['admin: 권한 해제', 'admin', 'aal2', $q$select 'ok' from (select public.registry_staff_remove(':viewer')) x$q$, 'ok'],
    ['권한 이력: 부여·부여·변경·해제', 'pg', '', $q$select string_agg(op, ',' order by id) from privacy.permission_logs where id > :p0$q$, 'grant,grant,change,revoke'],
    ['admin: 권한 이력 열람', 'admin', 'aal2', $q$select count(*)::text from public.privacy_permission_logs() where id > :p0$q$, '4'],
    ['권한 이력: 수정 불가', 'pg', '', $q$with u as (update privacy.permission_logs set op = op where id > :p0 returning 1) select count(*)::text from u$q$, 'ERR:추가만'],
    ['viewer: 해제 후 거절', 'viewer', 'aal2', $q$select public._t_registry('view', ':outsider')$q$, 'ERR:교적 권한이 없습니다'],
    ['변경기록: 추가', 'pg', '', $q$with i as (insert into registry._t_change (id, person_id, v) values (1, ':outsider', 'a') returning 1) select count(*)::text from i$q$, '1'],
    ['변경기록: 같은 값으로 수정', 'pg', '', $q$with u as (update registry._t_change set v = 'a', updated_at = now() where id = 1 returning 1) select count(*)::text from u$q$, '1'],
    ['변경기록: 값 수정', 'pg', '', $q$with u as (update registry._t_change set v = 'b' where id = 1 returning 1) select count(*)::text from u$q$, '1'],
    ['변경기록: 삭제', 'pg', '', $q$with d as (delete from registry._t_change where id = 1 returning 1) select count(*)::text from d$q$, '1'],
    ['변경기록: 3건·바뀐 필드·대상·처리자', 'pg', '', $q$select string_agg(op || ':' || coalesce(array_to_string(changed_fields, '+'), '-'), ',' order by id) || '/' || count(*) filter (where person_id = ':outsider') || '/' || count(*) filter (where actor_user_id = ':editor') from privacy.change_logs where table_name = 'registry._t_change'$q$, 'INSERT:-,UPDATE:v,DELETE:-/3/3'],
    ['변경기록: 수정 불가', 'pg', '', $q$with u as (update privacy.change_logs set op = op where table_name = 'registry._t_change' returning 1) select count(*)::text from u$q$, 'ERR:추가만'],
    ['설정: 교적 비밀번호 스위치 끄기', 'pg', '', $q$with u as (update registry.settings set require_password = false returning 1) select count(*)::text from u$q$, '1'],
    ['editor aal1: 스위치 꺼지면 허용', 'editor', 'aal1', $q$select public._t_registry('view', ':outsider')$q$, 'ok'],
    ['설정: 스위치 다시 켜기', 'pg', '', $q$with u as (update registry.settings set require_password = true returning 1) select count(*)::text from u$q$, '1'],
    ['editor aal1: 다시 거절', 'editor', 'aal1', $q$select public._t_registry('view', ':outsider')$q$, 'ERR:교적 비밀번호를 넣어 주세요'],
    ['기존 데이터 영향 없음: 사람 수', 'pg', '', $q$select count(*)::text from public.custom_users$q$, ':cu0']
  ];
  t    text[];
  tok  jsonb := '{}';
  who  jsonb := '{}';
  rec  record;
  sql  text;
  expect text;
  got  text;
  k    text;
  sub  text;
  pass int := 0;
  fail int := 0;
  res  text := '';
begin
  -- 대상 계정 (ID 만)
  select tok || jsonb_build_object(':admin', u.id::text), who || jsonb_build_object('admin', u.auth_id::text)
    into tok, who
    from public.custom_users u join public.roles r on r.id = u.role
   where r.level >= 100 and u.active
     and exists (select 1 from auth.users a where a.id = u.auth_id)
   order by u.id limit 1;
  for rec in
    select x.id, x.auth_id, row_number() over (order by x.id) as rn
      from (select u.id, u.auth_id
              from public.custom_users u join public.roles r on r.id = u.role
             where r.level < 50 and u.active
               and exists (select 1 from auth.users a where a.id = u.auth_id)  -- 교적 비밀번호 세션이 auth.users 를 참조한다
               and not exists (select 1 from registry.staff s where s.user_id = u.id)
             order by u.id limit 3) x
  loop
    k := (array['editor', 'viewer', 'outsider'])[rec.rn];
    tok := tok || jsonb_build_object(':' || k, rec.id::text);
    who := who || jsonb_build_object(k, rec.auth_id::text);
  end loop;
  tok := tok || jsonb_build_object(
    ':placeholder', (select u.id::text from public.custom_users u where not u.active order by u.id limit 1),
    ':a0',  (select coalesce(max(l.id), 0)::text from privacy.access_logs l),
    ':p0',  (select coalesce(max(l.id), 0)::text from privacy.permission_logs l),
    ':cu0', (select count(*)::text from public.custom_users));
  if (select count(*) from jsonb_object_keys(tok)) <> 8 or tok ->> ':outsider' is null then
    raise exception 'TEST_SETUP 대상 계정을 고르지 못했습니다: %', (select array_agg(k2) from jsonb_object_keys(tok) k2);
  end if;

  -- 테스트용 교적 함수와 교적 테이블 (함께 되돌려진다)
  create function public._t_registry(p text, target uuid) returns text
  language plpgsql security definer set search_path = '' as $f$
  begin
    perform registry.require(p);
    perform privacy.log_access(case p when 'edit' then 'update' when 'export' then 'export' else 'view' end,
                               '_t_registry', array[target], jsonb_build_object('need', p));
    return 'ok';
  end
  $f$;
  revoke all on function public._t_registry(text, uuid) from public, anon;
  grant execute on function public._t_registry(text, uuid) to authenticated;

  create table registry._t_change (id int primary key, person_id uuid, v text, updated_at timestamptz default now());
  create trigger log_change after insert or update or delete on registry._t_change
    for each row execute function privacy.log_change();

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
    sub := who ->> (case when t[2] = 'pg' then 'editor' else t[2] end);

    begin
      if t[2] = 'anon' then
        perform set_config('request.jwt.claims', '{"role":"anon"}', true);
        perform set_config('request.jwt.claim.sub', '', true);
        perform set_config('role', 'anon', true);
      else
        perform set_config('request.jwt.claims',
          json_build_object('sub', sub, 'role', 'authenticated', 'session_id', md5(sub || coalesce(nullif(t[3], ''), 'aal2'))::uuid)::text, true);
        perform set_config('request.jwt.claim.sub', sub, true);
        if t[2] <> 'pg' then
          perform set_config('role', 'authenticated', true);
        end if;
      end if;
      perform set_config('request.headers', '{"cf-connecting-ip":"203.0.113.7","user-agent":"registry-test"}', true);
      if left(sql, 5) = 'EXEC ' then
        execute substr(sql, 6);
        got := 'ok';
      else
        execute sql into got;
      end if;
      perform set_config('role', 'none', true);
    exception when others then
      got := 'ERR:' || sqlerrm;
    end;

    got := coalesce(got, '(null)');
    if (left(expect, 4) = 'ERR:' and got like 'ERR:%' and position(substr(expect, 5) in got) > 0)
       or got = expect then
      pass := pass + 1;
      res := res || E'\n  PASS ' || t[1];
    else
      fail := fail + 1;
      res := res || E'\n  FAIL ' || t[1] || ' — 기대 ' || expect || ' / 결과 ' || got;
    end if;
  end loop;

  perform set_config('role', 'none', true);
  raise exception 'TEST_RESULT (rolled back) pass=% fail=% %', pass, fail, res;
end
$test$;

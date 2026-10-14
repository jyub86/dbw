-- 교적 ③ 디모데 가져오기(20261012_registry_import) 역할별 테스트
--
-- 운영 DB에서 실행해도 된다. 마지막에 예외를 던져 테스트 중 바뀐 것을 모두 되돌린다. 결과는 'TEST_RESULT ...' 오류 메시지로 나온다.
-- 적용 전에는 마이그레이션 SQL 바로 뒤에 이 파일을 붙여 한 번에 실행한다(함께 되돌려진다).
-- 테스트가 쓰는 사람·디모데 행은 모두 '테스트…' 이름으로 테스트 안에서 만든다. 실제 교인 정보는 읽지 않는다.
--
-- 열: [이름, 역할, aal, SQL, 기대값, 결과를 담을 토큰]
--   기대값 'ERR:문구' = 그 문구가 들어간 오류, '*' = 무엇이든 통과(값을 결과에 적는다)
--   역할: viewer(열람) / editor(수정, 관리자 아님) / admin(사이트 관리자 + 교적 수정) / pg(DB 소유자, 토큰은 editor)

do $test$
declare
  rows_json text := $j$[
    {"src_id":"T1","sheet":"main","memo":"테스트 메모","data":{"name":"테스트일","gender":"남","birth_date":"1970-01-01","mobile":"010-9100-0001","home_phone":"032-000-0001","status":"예배출석","kind":"교인","office":"집사","office_detail":"서리집사","office_started_on":"2015-05-05","registered_on":"2001-01-01","baptism":"세례","baptism_date":"2003-03-03","baptism_church":"부평동부교회","officiant":"테스트목사","head_src":"T1","relation":"본인","address":"테스트시 1","zip":"111-111","family":"테스트일 테스트육","offering_no":"12345","occupation":"회사원"}},
    {"src_id":"T6","sheet":"main","data":{"name":"테스트육","gender":"여","birth_date":"1972-06-06","status":"예배출석","kind":"교인","head_src":"T1","relation":"처","address":"테스트시 1","baptism":"유세"}},
    {"src_id":"T2","sheet":"main","data":{"name":"테스트이","gender":"여","birth_date":"1999-09-09","status":"예배출석","kind":"교인"}},
    {"src_id":"T3","sheet":"main","data":{"name":"테스트삼","gender":"남","birth_date":"1980-03-03","status":"불출석","kind":"교인","registered_on":"2010-10-10"}},
    {"src_id":"T4","sheet":"main","data":{"name":"테스트사","gender":"남","status":"가끔출석","kind":"새가족","office":"권사","office_detail":"명예권사","mobile":"010-9100-0004","baptism":"영세"}},
    {"src_id":"T5","sheet":"deceased","data":{"name":"테스트이","gender":"여","birth_date":"1971-02-02","deceased_on":"2020-02-02"}},
    {"src_id":"T7","sheet":"main","data":{"name":"테스트칠a","status":"예배출석"}},
    {"src_id":"T8","sheet":"main","data":{"name":"테스트팔","mobile":"010-9100-0001","status":"불출석"}}
  ]$j$;
  tests text[] := array[
    -- 올리기 권한
    ['viewer: 올리기 거절', 'viewer', 'aal2', $q$select public.registry_import_load(:rows)::text$q$, 'ERR:이 작업을 할 권한이 없습니다', ''],
    ['editor(관리자 아님): 올리기 거절', 'editor', 'aal2', $q$select public.registry_import_load(:rows)::text$q$, 'ERR:사이트 관리자만', ''],
    ['admin aal1: 올리기 → 교적 비밀번호 요구', 'admin', 'aal1', $q$select public.registry_import_load(:rows)::text$q$, 'ERR:교적 비밀번호를 넣어 주세요', ''],
    ['admin: 형식이 틀린 파일 거절', 'admin', 'aal2', $q$select public.registry_import_load('[{"src_id":"X","data":"x"}]')::text$q$, 'ERR:파일 형식이 맞지 않습니다', ''],
    ['admin: 빈 파일 거절', 'admin', 'aal2', $q$select public.registry_import_load('[]')::text$q$, 'ERR:올릴 행이 없습니다', ''],
    ['admin: 올리기', 'admin', 'aal2', $q$select public.registry_import_load(:rows)::text$q$, '8', ''],
    ['올리기 기록 (행 수만)', 'pg', '', $q$select (detail ->> 'rows') || '/' || target_count from privacy.access_logs where fn = 'registry_import_load' and id > :a0$q$, '8/0', ''],
    -- 대조
    ['요약: 연결 제안/새 교적/확인 필요', 'editor', 'aal2', $q$select (s ->> 'link') || '/' || (s ->> 'new') || '/' || (s ->> 'review') from public.registry_import_summary() s$q$, '2/3/3', ''],
    ['대조: T1 = 테스트일 (이름+생일+전화)', 'pg', '', $q$select (candidates -> 0 ->> 'kind') || '/' || ((candidates -> 0 ->> 'person_id') = ':p1') from registry.import_rows where src_id = 'T1'$q$, 'strong/true', ''],
    ['대조: T8 전화만 같음', 'pg', '', $q$select string_agg(e ->> 'kind', ',') from registry.import_rows r, jsonb_array_elements(r.candidates) e where r.src_id = 'T8'$q$, 'phone', ''],
    ['대조: 별세자 행은 연결 제안 안 함, 이름만 같으면 확인, 구분기호 뗀 이름', 'pg', '', $q$select string_agg(src_id || '=' || suggestion, ',' order by src_id) from registry.import_rows where src_id in ('T2', 'T5', 'T7')$q$, 'T2=review,T5=review,T7=new', ''],
    ['행 번호 T2', 'pg', '', $q$select id::text from registry.import_rows where src_id = 'T2'$q$, '*', ':r2'],
    ['행 번호 T4', 'pg', '', $q$select id::text from registry.import_rows where src_id = 'T4'$q$, '*', ':r4'],
    ['행 번호 T5', 'pg', '', $q$select id::text from registry.import_rows where src_id = 'T5'$q$, '*', ':r5'],
    ['행 번호 T6', 'pg', '', $q$select id::text from registry.import_rows where src_id = 'T6'$q$, '*', ':r6'],
    ['행 번호 T7', 'pg', '', $q$select id::text from registry.import_rows where src_id = 'T7'$q$, '*', ':r7'],
    ['행 번호 T8', 'pg', '', $q$select id::text from registry.import_rows where src_id = 'T8'$q$, '*', ':r8'],
    ['viewer: 목록 거절', 'viewer', 'aal2', $q$select count(*)::text from public.registry_import_list('link')$q$, 'ERR:이 작업을 할 권한이 없습니다', ''],
    ['editor: 연결 제안 목록 (메모 있음 표시, 후보의 교적 여부)', 'editor', 'aal2', $q$select string_agg(src_id || ':' || has_memo || ':' || (candidates -> 0 ->> 'in_registry'), ',' order by src_id) from public.registry_import_list('link')$q$, 'T1:true:true,T3:false:false', ''],
    ['목록 열람 기록 (대상 = 후보 2명)', 'pg', '', $q$select target_count::text from privacy.access_logs where fn = 'registry_import_list' and id > :a0 order by id limit 1$q$, '2', ''],
    ['editor: 목록에 메모 본문 없음', 'editor', 'aal2', $q$select (position('테스트 메모' in (select string_agg(x::text, '') from public.registry_import_list('link') x)) = 0)::text$q$, 'true', ''],
    ['editor: 확인 필요 목록', 'editor', 'aal2', $q$select string_agg(src_id, ',' order by src_id) from public.registry_import_list('review')$q$, 'T2,T5,T8', ''],
    ['editor: 없는 목록 거절', 'editor', 'aal2', $q$select count(*)::text from public.registry_import_list('xx')$q$, 'ERR:알 수 없는 목록', ''],
    -- 정하기
    ['editor: 연결 제안 일괄 확정', 'editor', 'aal2', $q$select public.registry_import_accept()::text$q$, '2', ''],
    ['editor: 이미 연결된 사람에게 또 연결 거절', 'editor', 'aal2', $q$select 'ok' from (select public.registry_import_decide(:r8, 'link', ':p1')) x$q$, 'ERR:이미 다른 디모데 행과 연결', ''],
    ['editor: 별세자를 새 교적으로 거절', 'editor', 'aal2', $q$select 'ok' from (select public.registry_import_decide(:r5, 'new')) x$q$, 'ERR:별세자는 새 교적으로', ''],
    ['editor: 사람 없이 연결 거절', 'editor', 'aal2', $q$select 'ok' from (select public.registry_import_decide(:r2, 'link')) x$q$, 'ERR:연결할 사람을 골라 주세요', ''],
    ['editor: 없는 처리 거절', 'editor', 'aal2', $q$select 'ok' from (select public.registry_import_decide(:r2, 'xx')) x$q$, 'ERR:알 수 없는 처리', ''],
    ['editor: T5 가져오지 않음', 'editor', 'aal2', $q$select 'ok' from (select public.registry_import_decide(:r5, 'skip')) x$q$, 'ok', ''],
    ['editor: T8 가져오지 않음', 'editor', 'aal2', $q$select 'ok' from (select public.registry_import_decide(:r8, 'skip')) x$q$, 'ok', ''],
    ['editor: T2 → 테스트이 연결', 'editor', 'aal2', $q$select 'ok' from (select public.registry_import_decide(:r2, 'link', ':p2')) x$q$, 'ok', ''],
    ['editor: T4 새 교적', 'editor', 'aal2', $q$select 'ok' from (select public.registry_import_decide(:r4, 'new')) x$q$, 'ok', ''],
    ['editor: T6 새 교적', 'editor', 'aal2', $q$select 'ok' from (select public.registry_import_decide(:r6, 'new')) x$q$, 'ok', ''],
    ['editor: T7 새 교적', 'editor', 'aal2', $q$select 'ok' from (select public.registry_import_decide(:r7, 'new')) x$q$, 'ok', ''],
    ['요약: 확정 6, 제외 2', 'editor', 'aal2', $q$select (s ->> 'decided') || '/' || (s ->> 'skipped') from public.registry_import_summary() s$q$, '6/2', ''],
    -- 미리보기·반영
    ['viewer: 반영 거절', 'viewer', 'aal2', $q$select public.registry_import_apply()::text$q$, 'ERR:이 작업을 할 권한이 없습니다', ''],
    ['editor: 미리보기 (행/새로 만듦/생일 차이)', 'editor', 'aal2', $q$select (j ->> 'rows') || '/' || (j ->> 'created') || '/' || coalesce(j -> 'diffs' ->> 'birth_date', '0') || '/' || (j ->> 'preview') from (select public.registry_import_apply(100, true) j) x$q$, '6/3/1/true', ''],
    ['미리보기 내역', 'editor', 'aal2', $q$select public.registry_import_apply(100, true)::text$q$, '*', ''],
    ['미리보기 뒤 아무것도 안 바뀜', 'pg', '', $q$select (select count(*) from public.custom_users where name in ('테스트사', '테스트육', '테스트칠')) || '/' || (select count(*) from registry.import_rows where applied_at is not null) || '/' || (select count(*) from registry.households where note like '디모데 가족: 테스트%') || '/' || (select count(*) from registry.legacy_memos where src_id = 'T1')$q$, '0/0/0/0', ''],
    ['미리보기 기록 (열람으로)', 'pg', '', $q$select count(*)::text from privacy.access_logs where fn = 'registry_import_apply' and action = 'view' and id > :a0$q$, '2', ''],
    ['editor: 반영 (행/새로 만듦/남은 행)', 'editor', 'aal2', $q$select (j ->> 'rows') || '/' || (j ->> 'created') || '/' || (j ->> 'remaining') from (select public.registry_import_apply(100) j) x$q$, '6/3/0', ''],
    ['테스트일: 등록일·임명일·세례·직업 채움, 전화 그대로', 'pg', '', $q$select s.registered_on || '/' || (select started_on from registry.office_terms where person_id = ':p1' and office = 'deacon') || '/' || (select kind || ':' || event_date || ':' || coalesce(church_name, '본교회') || ':' || officiant from registry.faith_events where person_id = ':p1') || '/' || p.occupation || '/' || u.phone from registry.summary s join registry.people p on p.person_id = s.person_id join public.custom_users u on u.id = p.person_id where s.person_id = ':p1'$q$, '2001-01-01/2015-05-05/baptism:2003-03-03:본교회:테스트목사/회사원/010-9100-0001', ''],
    ['테스트일 반영 내역 (차이 없음)', 'pg', '', $q$select (select string_agg(f, ',' order by f) from jsonb_array_elements_text(result -> 'filled') f) || '/' || jsonb_array_length(result -> 'diffs') from registry.import_rows where src_id = 'T1'$q$, 'faith,household,household_member,memo,office_started_on,registered_on,registry/0', ''],
    ['테스트일·테스트육 한 세대 (본인·배우자), 세대 주소·전화', 'pg', '', $q$select string_agg(coalesce(u.name, m.name) || ':' || m.relation, ',' order by m.sort_order) || '/' || h.address1 || '/' || h.home_phone from registry.household_members m join registry.households h on h.id = m.household_id left join public.custom_users u on u.id = m.person_id where m.household_id = (select household_id from registry.household_members where person_id = ':p1') group by h.address1, h.home_phone$q$, '테스트일:self,테스트육:spouse/테스트시 1/032-000-0001', ''],
    ['테스트육: 새 미가입 교인, 개인 주소 없음(세대 주소), 유아세례', 'pg', '', $q$select u.active || '/' || u.member || '/' || u.office || '/' || coalesce(p.address1, '-') || '/' || s.faith || '/' || s.status from public.custom_users u join registry.people p on p.person_id = u.id join registry.summary s on s.person_id = u.id where u.name = '테스트육'$q$, 'false/true/성도/-/infant_baptized/active', ''],
    ['테스트칠: 구분기호 뗀 이름으로 만듦', 'pg', '', $q$select count(*)::text from public.custom_users where name = '테스트칠'$q$, '1', ''],
    ['테스트사: 명예권사 호칭, 영세는 차이로', 'pg', '', $q$select u.office || '/' || u.phone || '/' || (select string_agg(e ->> 'field', ',') from registry.import_rows r, jsonb_array_elements(r.result -> 'diffs') e where r.src_id = 'T4') from public.custom_users u where u.name = '테스트사'$q$, '명예권사/010-9100-0004/faith', ''],
    ['테스트이: 생일은 그대로 두고 차이로', 'pg', '', $q$select u.birth_date || '/' || (select string_agg(e ->> 'field', ',') from registry.import_rows r, jsonb_array_elements(r.result -> 'diffs') e where r.src_id = 'T2') from public.custom_users u where u.id = ':p2'$q$, '1971-02-02/birth_date', ''],
    ['테스트삼: 교적 등록·교인 인증, 불출석은 차이로', 'pg', '', $q$select s.status || '/' || u.member || '/' || s.registered_on || '/' || (select string_agg(e ->> 'field', ',') from registry.import_rows r, jsonb_array_elements(r.result -> 'diffs') e where r.src_id = 'T3') from registry.summary s join public.custom_users u on u.id = s.person_id where s.person_id = ':p3'$q$, 'active/true/2010-10-10/status', ''],
    ['옛 ID·헌금번호', 'pg', '', $q$select string_agg(src_id || ':' || coalesce(offering_no, '-'), ',' order by src_id) from registry.legacy_links where source = 'dimode' and src_id like 'T%'$q$, 'T1:12345,T2:-,T3:-,T4:-,T6:-,T7:-', ''],
    ['editor: 차이 목록', 'editor', 'aal2', $q$select string_agg(src_id, ',' order by src_id) from public.registry_import_list('diffs')$q$, 'T2,T3,T4', ''],
    ['editor: 반영한 행 다시 정하기 거절', 'editor', 'aal2', $q$select 'ok' from (select public.registry_import_decide(:r2, 'skip')) x$q$, 'ERR:이미 반영한 행', ''],
    ['editor: 반영한 사람에게 다른 행 연결 거절', 'editor', 'aal2', $q$select 'ok' from (select public.registry_import_decide(:r8, 'link', ':p2')) x$q$, 'ERR:이미 다른 디모데 행과 연결', ''],
    ['admin: 다시 올리기 → 반영 전 행만 바뀜', 'admin', 'aal2', $q$select public.registry_import_load(:rows)::text$q$, '2', ''],
    -- 옛 메모 (교역자만)
    ['옛 메모는 변경기록에 남기지 않음', 'pg', '', $q$select count(*)::text from privacy.change_logs where table_name = 'registry.legacy_memos'$q$, '0', ''],
    ['editor: 교적 카드에 메모 본문 없음', 'editor', 'aal2', $q$select (position('테스트 메모' in public.registry_card(':p1')::text) = 0)::text$q$, 'true', ''],
    ['viewer: 옛 메모 거절', 'viewer', 'aal2', $q$select count(*)::text from public.registry_legacy_memos(':p1')$q$, 'ERR:이 작업을 할 권한이 없습니다', ''],
    ['editor(심방 권한 없음): 옛 메모 거절', 'editor', 'aal2', $q$select count(*)::text from public.registry_legacy_memos(':p1')$q$, 'ERR:이 작업을 할 권한이 없습니다', ''],
    ['editor에게 심방 권한', 'pg', '', $q$update registry.staff set can_pastoral = true where user_id = ':editor' returning 'ok'$q$, 'ok', ''],
    ['editor(심방): 옛 메모', 'editor', 'aal2', $q$select string_agg(body, ',') from public.registry_legacy_memos(':p1')$q$, '테스트 메모', ''],
    ['옛 메모 열람 기록', 'pg', '', $q$select count(*)::text from privacy.access_logs where fn = 'registry_legacy_memos' and id > :a0$q$, '1', ''],
    -- 계정 연결(병합) 때 옛 ID 따라감
    ['editor: 테스트삼을 가입 계정과 연결', 'editor', 'aal2', $q$select 'ok' from (select public.registry_link_account(':p3', ':link_acct')) x$q$, 'ok', ''],
    ['병합: 옛 ID가 가입 계정으로', 'pg', '', $q$select (person_id = ':link_acct')::text from registry.legacy_links where src_id = 'T3'$q$, 'true', ''],
    -- 정리
    ['editor: 정리 거절', 'editor', 'aal2', $q$select public.registry_import_close()::text$q$, 'ERR:사이트 관리자만', ''],
    ['admin: 정리', 'admin', 'aal2', $q$select public.registry_import_close()::text$q$, '8', ''],
    ['정리 뒤: 올린 행 0, 옛 메모·옛 ID는 남음', 'pg', '', $q$select (select count(*) from registry.import_rows) || '/' || (select count(*) from registry.legacy_memos where src_id = 'T1') || '/' || (select count(*) from registry.legacy_links where src_id like 'T%')$q$, '0/1/6', ''],
    ['접속기록: 가져오기 함수', 'pg', '', $q$select string_agg(distinct fn, ',' order by fn) from privacy.access_logs where id > :a0 and fn like 'registry_import%'$q$, 'registry_import_accept,registry_import_apply,registry_import_close,registry_import_decide,registry_import_list,registry_import_load', ''],
    ['접속기록: 모든 기록에 처리자', 'pg', '', $q$select count(*) filter (where actor_user_id is null)::text from privacy.access_logs where id > :a0$q$, '0', ''],
    -- 변환
    ['변환: 관계', 'pg', '', $q$select string_agg(coalesce(registry.dimode_relation(x), 'null'), ',' order by i) from unnest(array['본인', '처', '아들1', '장녀', '3남', '1자부', '손녀2', '1손자', '사위1', '모', '남동생', '조카', null]) with ordinality t(x, i)$q$, 'self,spouse,child,child,child,daughter_in_law,grandchild,grandchild,son_in_law,parent,sibling,other,null', ''],
    ['변환: 직분', 'pg', '', $q$select string_agg(coalesce(o.code, '-') || ':' || coalesce(o.standing, '-'), ',' order by v.i) from (values (1, '집사', '서리집사'), (2, '권사', '명예권사'), (3, '장로', '원로장로'), (4, '안수집사', '은퇴안수집사'), (5, '권사', '휴직권사'), (6, '집사', null), (7, '성도', '성도')) v(i, a, b), lateral registry.dimode_office(v.a, v.b) o$q$, 'deacon:serving,kwonsa:honorary,elder:emeritus,ordained_deacon:retired,-:-,deacon:serving,-:-', ''],
    ['변환: 이름 키', 'pg', '', $q$select string_agg(registry.name_key(x), ',' order by i) from unnest(array['홍길동a', '홍 길동', '홍길동(큰)', 'John', '홍길동 B']) with ordinality t(x, i)$q$, '홍길동,홍길동,홍길동,John,홍길동', ''],
    ['변환: 세례', 'pg', '', $q$select string_agg(coalesce(registry.dimode_faith(x), '-'), ',' order by i) from unnest(array['세례', '유세', '유아세례', '입교', '학습', '침례', '영세']) with ordinality t(x, i)$q$, 'baptism,infant_baptism,infant_baptism,confirmation,catechumen,baptism,-', ''],
    -- 성능 (요청 시간 제한 8초)
    ['성능 준비: 새 교적 600행 (세 명씩 한 세대)', 'pg', '', $q$with ins as (insert into registry.import_rows (src_id, sheet, data, name_key, decision, suggestion) select 'P' || i, 'main', jsonb_build_object('name', '테스트성능' || i, 'status', '예배출석', 'gender', case when i % 2 = 0 then '남' else '여' end, 'birth_date', '1980-01-01', 'head_src', 'P' || (i / 3 * 3), 'relation', case i % 3 when 0 then '본인' when 1 then '처' else '아들1' end, 'address', '테스트시 ' || (i / 3), 'baptism', '세례', 'registered_on', '2010-01-01', 'office', '집사', 'office_detail', '서리집사'), registry.name_key('테스트성능' || i), 'new', 'new' from generate_series(1, 600) i returning 1) select count(*)::text from ins$q$, '600', ''],
    ['성능: 미리보기 600행', 'editor', 'aal2', $q$with t0 as materialized (select clock_timestamp() as s), r as materialized (select public.registry_import_apply(100, true) as j from t0) select (r.j ->> 'rows') || '행 ' || round(extract(epoch from clock_timestamp() - t0.s) * 1000) || 'ms' from r, t0$q$, '*', ''],
    ['성능: 반영 200행', 'editor', 'aal2', $q$with t0 as materialized (select clock_timestamp() as s), r as materialized (select public.registry_import_apply(200) as j from t0) select (r.j ->> 'rows') || '행 ' || round(extract(epoch from clock_timestamp() - t0.s) * 1000) || 'ms' from r, t0$q$, '*', '']
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
begin
  -- 푸시 알림 webhook 은 테스트 동안 끈다 (되돌려진다)
  alter table public.messages disable trigger "send-notification";

  -- 대상 계정 (ID 만)
  select tok || jsonb_build_object(':admin', u.id::text), who || jsonb_build_object('admin', u.auth_id::text), picked || u.id
    into tok, who, picked
    from public.custom_users u join public.roles r on r.id = u.role
   where r.level >= 100 and u.active and exists (select 1 from auth.users a where a.id = u.auth_id)
   order by u.id limit 1;
  for rec in
    select x.id, x.auth_id, row_number() over (order by x.id) as rn
      from (select u.id, u.auth_id from public.custom_users u join public.roles r on r.id = u.role
             where r.level < 50 and u.active
               and exists (select 1 from auth.users a where a.id = u.auth_id)
               and not exists (select 1 from registry.staff s where s.user_id = u.id)
             order by u.id limit 2) x
  loop
    k := (array['editor', 'viewer'])[rec.rn];
    tok := tok || jsonb_build_object(':' || k, rec.id::text);
    who := who || jsonb_build_object(k, rec.auth_id::text);
    picked := picked || rec.id;
  end loop;
  -- 계정 연결용: 로그인 계정, 교적 없음
  select tok || jsonb_build_object(':link_acct', u.id::text) into tok
    from public.custom_users u join public.roles r on r.id = u.role
   where r.level < 100
     and exists (select 1 from auth.users a where a.id = u.auth_id)
     and not exists (select 1 from registry.people p where p.person_id = u.id)
     and not exists (select 1 from registry.staff s where s.user_id = u.id)
     and u.id <> all (picked)
   order by u.id limit 1;
  if tok ->> ':admin' is null or tok ->> ':viewer' is null or tok ->> ':link_acct' is null then
    raise exception 'TEST_SETUP 대상 계정을 고르지 못했습니다: %', (select array_agg(k2) from jsonb_object_keys(tok) k2);
  end if;

  -- 테스트 사람: 교적 있음(등록일 미상, 서리집사) / 교적 있음(등록일 있음) / 교적 없는 미가입 프로필
  insert into public.custom_users (name, phone, gender, birth_date, office, member, active)
  values ('테스트일', '010-9100-0001', '남', '1970-01-01', '집사', true, false) returning id into v_id;
  insert into registry.people (person_id) values (v_id);
  insert into registry.status_events (person_id, kind, event_date) values (v_id, 'register', null);
  perform registry.office_from_profile(v_id);
  tok := tok || jsonb_build_object(':p1', v_id::text);
  insert into public.custom_users (name, gender, birth_date, office, member, active)
  values ('테스트이', '여', '1971-02-02', '성도', true, false) returning id into v_id;
  insert into registry.people (person_id) values (v_id);
  insert into registry.status_events (person_id, kind, event_date) values (v_id, 'register', '2020-01-01');
  tok := tok || jsonb_build_object(':p2', v_id::text);
  insert into public.custom_users (name, gender, birth_date, office, member, active)
  values ('테스트삼', '남', '1980-03-03', '성도', false, false) returning id into v_id;
  tok := tok || jsonb_build_object(':p3', v_id::text);

  tok := tok || jsonb_build_object(
    ':a0', (select coalesce(max(l.id), 0)::text from privacy.access_logs l),
    ':rows', quote_literal(rows_json));

  -- 교적 권한 (테스트 동안만)
  insert into registry.staff (user_id, can_edit, can_export, note)
  values ((tok ->> ':editor')::uuid, true, true, 'TEST'), ((tok ->> ':viewer')::uuid, false, false, 'TEST'),
         ((tok ->> ':admin')::uuid, true, false, 'TEST')
  on conflict (user_id) do update set can_edit = excluded.can_edit, can_pastoral = false;

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
      perform set_config('request.headers', '{"cf-connecting-ip":"203.0.113.7","user-agent":"registry-test"}', true);
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
      if expect = '*' and t[6] = '' then
        res := res || E'\n  INFO ' || t[1] || ' = ' || got;
      end if;
    else
      fail := fail + 1;
      res := res || E'\n  FAIL ' || t[1] || ' — 기대 ' || expect || ' / 결과 ' || got;
    end if;
  end loop;

  perform set_config('role', 'none', true);
  raise exception 'TEST_RESULT (rolled back) pass=% fail=% %', pass, fail, res;
end
$test$;

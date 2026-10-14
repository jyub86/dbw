-- 교적 본체(20261011_registry_core) + 초기 생성(20261011_registry_seed) 역할별 테스트
--
-- 운영 DB에서 실행해도 된다. 마지막에 예외를 던져 테스트 중 바뀐 것을 모두 되돌린다. 결과는 'TEST_RESULT ...' 오류 메시지로 나온다.
-- 적용 전에는 두 마이그레이션 SQL 바로 뒤에 이 파일을 붙여 한 번에 실행한다(함께 되돌려진다).
-- 대상 계정·교인은 ID 로만 고른다. 테스트가 만드는 사람은 '테스트…' 이름을 쓴다.
--
-- 열: [이름, 역할, aal, SQL, 기대값, 결과를 담을 토큰]
--   기대값 'ERR:문구' = 그 문구가 들어간 오류, '*' = 무엇이든 통과(값을 결과에 적는다)
--   역할: anon / outsider(교적 권한 없음) / viewer(열람) / editor(수정·내려받기) / admin(사이트 관리자, 교적 권한 없음)
--         merge_acct(가입 병합을 해 보는 로그인 계정) / pg(DB 소유자, 토큰은 editor) / service(서비스 롤)

do $test$
declare
  tests text[] := array[
    -- 초기 생성
    ['초기 생성: 교적 수 (= 교인 표시 + 지금 목장 명단)', 'pg', '', $q$select count(*)::text from registry.people$q$, ':exp_people', ''],
    ['초기 생성: 교적 수 값', 'pg', '', $q$select count(*)::text from registry.people$q$, '*', ''],
    ['초기 생성: 모두 등록 1건, 날짜 미상', 'pg', '', $q$select count(*) filter (where kind = 'register' and event_date is null)::text from registry.status_events$q$, ':exp_people', ''],
    ['초기 생성: 직분 이력 (호칭이 직분인 사람만)', 'pg', '', $q$select string_agg(office || '=' || n, ',' order by office) from (select office, count(*) n from registry.office_terms group by 1) x$q$, '*', ''],
    ['초기 생성: 직분 이력 수 = 호칭이 직분인 사람 수', 'pg', '', $q$select ((select count(*) from registry.office_terms) = (select count(*) from registry.people p join public.custom_users u on u.id = p.person_id where u.office in ('목사','전도사','장로','시무집사','권사','집사')))::text$q$, 'true', ''],
    ['초기 생성: 프로필(호칭·교인 인증)은 건드리지 않음 (이 트랜잭션의 프로필 변경기록 0)', 'pg', '', $q$select count(*)::text from privacy.change_logs where table_name = 'public.custom_users' and at = now()$q$, '0', ''],
    ['초기 생성: 이 트랜잭션에서 만든 교적 변경기록', 'pg', '', $q$select count(*)::text from privacy.change_logs where table_name = 'registry.people' and op = 'INSERT' and at = now()$q$, '*', ''],
    ['초기 생성: 상태 모두 재적, 신급 모두 미확인', 'pg', '', $q$select string_agg(distinct status || '/' || faith, ',') from registry.summary$q$, 'active/unknown', ''],
    ['초기 생성: 확인 목록 수', 'viewer', 'aal2', $q$select count(*)::text from public.registry_candidates()$q$, ':exp_cand', ''],
    ['초기 생성: 확인 목록 내역', 'viewer', 'aal2', $q$select string_agg(reason || '=' || n, ',' order by reason) from (select reason, count(*) n from public.registry_candidates() group by 1) x$q$, '*', ''],
    -- 권한
    ['anon: 검색 불가', 'anon', '', $q$select count(*)::text from public.registry_search()$q$, 'ERR:permission denied', ''],
    ['outsider: 검색 거절', 'outsider', 'aal2', $q$select count(*)::text from public.registry_search()$q$, 'ERR:교적 권한이 없습니다', ''],
    ['admin: 교적 권한 없으면 카드 거절', 'admin', 'aal2', $q$select public.registry_card(':seeded')::text$q$, 'ERR:교적 권한이 없습니다', ''],
    ['viewer aal1: 검색 → 교적 비밀번호 요구', 'viewer', 'aal1', $q$select count(*)::text from public.registry_search()$q$, 'ERR:교적 비밀번호를 넣어 주세요', ''],
    ['viewer: 코드표', 'viewer', 'aal2', $q$select count(*)::text from public.registry_codes()$q$, '19', ''],
    ['viewer: 검색 (재적, 5명씩)', 'viewer', 'aal2', $q$select count(*) || '/' || max(total) from public.registry_search('{"status":["active"]}', 5, 0)$q$, '5/:exp_people', ''],
    ['viewer: 목장으로 검색', 'viewer', 'aal2', $q$select (count(*) > 0)::text from public.registry_search(jsonb_build_object('group_id', :group_id), 500, 0)$q$, 'true', ''],
    ['viewer: 직분으로 검색 (서리집사)', 'viewer', 'aal2', $q$select (count(*) > 0 and bool_and(office = '집사'))::text from public.registry_search('{"office":["deacon"]}', 500, 0)$q$, 'true', ''],
    ['viewer: 검색 기록 (대상 = 돌려준 사람)', 'pg', '', $q$select target_count::text from privacy.access_logs where fn = 'registry_search' and id > :a0 order by id limit 1$q$, '5', ''],
    ['viewer: 교적 카드', 'viewer', 'aal2', $q$select ((c ? 'person') and (c ? 'status_events') and (c ? 'office_terms') and (c ? 'household') and (c ? 'history'))::text || '/' || (c -> 'summary' ->> 'status') || '/' || (c -> 'summary' ->> 'faith') from (select public.registry_card(':seeded') c) x$q$, 'true/active/unknown', ''],
    ['viewer: 카드 열람 기록', 'pg', '', $q$select count(*)::text from privacy.access_logs where fn = 'registry_card' and id > :a0 and target_ids @> array[':seeded'::uuid]$q$, '1', ''],
    ['viewer: 수정 거절', 'viewer', 'aal2', $q$select 'ok' from (select public.registry_save(':seeded', '{"note":"x"}')) x$q$, 'ERR:이 작업을 할 권한이 없습니다', ''],
    ['viewer: 새가족 등록 거절', 'viewer', 'aal2', $q$select public.registry_register('{"name":"테스트거절"}')::text$q$, 'ERR:이 작업을 할 권한이 없습니다', ''],
    ['viewer: 계정 연결 거절', 'viewer', 'aal2', $q$select 'ok' from (select public.registry_link_account(':seeded', ':link_acct')) x$q$, 'ERR:이 작업을 할 권한이 없습니다', ''],
    -- 새가족 등록
    ['editor: 새가족 등록', 'editor', 'aal2', $q$select public.registry_register('{"name":"테스트새가족","phone":"010-0000-0001","gender":"여","office":"deacon","registered_on":"2026-10-01","address1":"테스트구 1"}')::text$q$, '*', ':new'],
    ['새가족: 미가입·교인·호칭 집사·등록일', 'pg', '', $q$select u.active || '/' || u.member || '/' || u.office || '/' || s.status || '/' || s.registered_on || '/' || s.office from public.custom_users u join registry.summary s on s.person_id = u.id where u.id = ':new'$q$, 'false/true/집사/active/2026-10-01/deacon', ''],
    ['새가족: 환영 메시지 안 보냄 (로그인 계정 없음)', 'pg', '', $q$select count(*)::text from public.messages m join public.custom_users u on u.auth_id = m.receiver_id where u.id = ':new'$q$, '0', ''],
    ['새가족: 비슷한 사람 찾기', 'viewer', 'aal2', $q$select count(*) || '/' || bool_and(in_registry) from public.registry_find_similar('테스트새가족', '01000000001')$q$, '1/true', ''],
    ['editor: 등록 시 이름 없음 거절', 'editor', 'aal2', $q$select public.registry_register('{"phone":"010"}')::text$q$, 'ERR:이름을 넣어 주세요', ''],
    ['editor: 등록 시 없는 직분 거절', 'editor', 'aal2', $q$select public.registry_register('{"name":"테스트","office":"bishop"}')::text$q$, 'ERR:알 수 없는 값', ''],
    -- 인적사항 수정
    ['editor: 인적사항 수정', 'editor', 'aal2', $q$select 'ok' from (select public.registry_save(':new', '{"phone":"010-0000-0002","address1":"테스트구 2","marital_status":"married","occupation":"교사"}')) x$q$, 'ok', ''],
    ['수정: 값 반영', 'pg', '', $q$select u.phone || '/' || p.address1 || '/' || p.marital_status || '/' || p.occupation from public.custom_users u join registry.people p on p.person_id = u.id where u.id = ':new'$q$, '010-0000-0002/테스트구 2/married/교사', ''],
    ['수정: 변경기록 (프로필 전화, 교적 3필드)', 'pg', '', $q$select string_agg(table_name || ':' || array_to_string(changed_fields, '+'), ',' order by id) from privacy.change_logs where person_id = ':new' and op = 'UPDATE'$q$, 'public.custom_users:phone,registry.people:address1+marital_status+occupation', ''],
    ['editor: 전화번호로 검색', 'editor', 'aal2', $q$select count(*)::text from public.registry_search('{"q":"0000-0002"}', 50, 0)$q$, '1', ''],
    ['editor: 고칠 수 없는 항목 거절', 'editor', 'aal2', $q$select 'ok' from (select public.registry_save(':new', '{"role":2}')) x$q$, 'ERR:고칠 수 없는 항목', ''],
    ['editor: 이름 비우기 거절', 'editor', 'aal2', $q$select 'ok' from (select public.registry_save(':new', '{"name":""}')) x$q$, 'ERR:이름은 비울 수 없습니다', ''],
    ['editor: 없는 결혼 상태 거절', 'editor', 'aal2', $q$select 'ok' from (select public.registry_save(':new', '{"marital_status":"xx"}')) x$q$, 'ERR:알 수 없는 값', ''],
    -- 재적 상태 → 교인 인증
    ['editor: 별세 처리', 'editor', 'aal2', $q$select public.registry_add_status(':new', 'deceased', '2026-10-05', '테스트')::text$q$, '*', ''],
    ['별세: 상태·교인 인증 해제', 'pg', '', $q$select s.status || '/' || u.member from registry.summary s join public.custom_users u on u.id = s.person_id where s.person_id = ':new'$q$, 'deceased/false', ''],
    ['editor: 복적', 'editor', 'aal2', $q$select public.registry_add_status(':new', 'restore', '2026-10-06')::text$q$, '*', ':ev_restore'],
    ['복적: 상태·교인 인증', 'pg', '', $q$select s.status || '/' || u.member from registry.summary s join public.custom_users u on u.id = s.person_id where s.person_id = ':new'$q$, 'active/true', ''],
    ['editor: 날짜 없는 상태 거절', 'editor', 'aal2', $q$select public.registry_add_status(':new', 'hold', null)::text$q$, 'ERR:날짜를 넣어 주세요', ''],
    ['editor: 없는 상태 종류 거절', 'editor', 'aal2', $q$select public.registry_add_status(':new', 'xx', '2026-10-06')::text$q$, 'ERR:check constraint', ''],
    ['editor: 상태 기록 지우기 (복적 취소)', 'editor', 'aal2', $q$select 'ok' from (select public.registry_delete_status(:ev_restore)) x$q$, 'ok', ''],
    ['복적 취소: 다시 별세·인증 해제', 'pg', '', $q$select s.status || '/' || u.member from registry.summary s join public.custom_users u on u.id = s.person_id where s.person_id = ':new'$q$, 'deceased/false', ''],
    ['상태 기록 하나뿐인 사람 찾기', 'pg', '', $q$select id::text from registry.status_events where person_id = ':seeded'$q$, '*', ':ev_seeded'],
    ['editor: 마지막 재적 기록 지우기 거절', 'editor', 'aal2', $q$select 'ok' from (select public.registry_delete_status(:ev_seeded)) x$q$, 'ERR:마지막 재적 기록은 지울 수 없습니다', ''],
    -- 신급
    ['신급: 기록 없으면 미확인', 'pg', '', $q$select faith from registry.summary where person_id = ':new'$q$, 'unknown', ''],
    ['editor: 신급 확인일 → 원입', 'editor', 'aal2', $q$select 'ok' from (select public.registry_save(':new', '{"faith_checked_on":"2026-10-01"}')) x$q$, 'ok', ''],
    ['신급: 원입', 'pg', '', $q$select faith from registry.summary where person_id = ':new'$q$, 'seeker', ''],
    ['editor: 학습', 'editor', 'aal2', $q$select public.registry_add_faith(':new', 'catechumen', '2026-10-02')::text$q$, '*', ''],
    ['editor: 세례', 'editor', 'aal2', $q$select public.registry_add_faith(':new', 'baptism', '2026-10-03', null, '테스트목사')::text$q$, '*', ':ev_baptism'],
    ['신급: 세례교인', 'pg', '', $q$select faith from registry.summary where person_id = ':new'$q$, 'baptized', ''],
    ['editor: 세례 기록 지우기', 'editor', 'aal2', $q$select 'ok' from (select public.registry_delete_faith(:ev_baptism)) x$q$, 'ok', ''],
    ['신급: 학습교인', 'pg', '', $q$select faith from registry.summary where person_id = ':new'$q$, 'catechumen', ''],
    ['editor: 없는 신급 종류 거절', 'editor', 'aal2', $q$select public.registry_add_faith(':new', 'xx')::text$q$, 'ERR:check constraint', ''],
    -- 직분 → 표시 호칭
    ['editor: 시무집사 임직', 'editor', 'aal2', $q$select public.registry_add_office(':new', 'ordained_deacon', 'serving', '2026-10-07')::text$q$, '*', ''],
    ['직분: 호칭 시무집사, 서리집사 이력은 임직일로 끝남', 'pg', '', $q$select u.office || '/' || (select string_agg(office || ':' || coalesce(ended_on::text, '-'), ',' order by id) from registry.office_terms where person_id = u.id) from public.custom_users u where u.id = ':new'$q$, '시무집사/deacon:2026-10-07,ordained_deacon:-', ''],
    ['editor: 은퇴 장로', 'editor', 'aal2', $q$select public.registry_add_office(':new', 'elder', 'retired', '2026-10-08')::text$q$, '*', ':term_elder'],
    ['직분: 호칭 은퇴장로', 'pg', '', $q$select office from public.custom_users where id = ':new'$q$, '은퇴장로', ''],
    ['editor: 직분 끝내기', 'editor', 'aal2', $q$select 'ok' from (select public.registry_end_office(:term_elder, '2026-10-09')) x$q$, 'ok', ''],
    ['직분: 맡은 직분 없음 → 성도', 'pg', '', $q$select office from public.custom_users where id = ':new'$q$, '성도', ''],
    ['editor: 없는 직분 거절', 'editor', 'aal2', $q$select public.registry_add_office(':new', 'bishop')::text$q$, 'ERR:알 수 없는 값', ''],
    ['직분: 호칭 변경도 변경기록에', 'pg', '', $q$select count(*)::text from privacy.change_logs where person_id = ':new' and table_name = 'public.custom_users' and op = 'UPDATE' and 'office' = any (changed_fields)$q$, '3', ''],
    -- 메모·동의
    ['editor: 메모', 'editor', 'aal2', $q$select public.registry_add_note(':new', '테스트 메모')::text$q$, '*', ':note'],
    ['카드: 메모와 작성자', 'viewer', 'aal2', $q$select jsonb_array_length(c -> 'notes') || '/' || ((c -> 'notes' -> 0 ->> 'author') is not null) from (select public.registry_card(':new') c) x$q$, '1/true', ''],
    ['editor: 메모 지우기', 'editor', 'aal2', $q$select 'ok' from (select public.registry_delete_note(:note)) x$q$, 'ok', ''],
    ['editor: 동의 기록', 'editor', 'aal2', $q$select public.registry_add_consent(':new', 'registry', '2026-10-01', 'paper', '2026-10')::text$q$, '*', ':consent'],
    ['editor: 동의 철회', 'editor', 'aal2', $q$select 'ok' from (select public.registry_revoke_consent(:consent, '2026-10-09')) x$q$, 'ok', ''],
    ['동의: 철회일', 'pg', '', $q$select revoked_on::text from registry.consents where id = :consent$q$, '2026-10-09', ''],
    -- 세대
    ['editor: 세대 만들기 (세대주 = 새가족)', 'editor', 'aal2', $q$select public.registry_household_create(':new', '{"address1":"테스트구 세대","home_phone":"032-000-0000"}')::text$q$, '*', ':hh'],
    ['editor: 교인 배우자 추가', 'editor', 'aal2', $q$select public.registry_household_add(:hh, ':seeded', 'spouse')::text$q$, '*', ':hm_spouse'],
    ['editor: 교인 아닌 자녀 추가', 'editor', 'aal2', $q$select public.registry_household_add(:hh, null, 'child', '테스트자녀', 2015)::text$q$, '*', ':hm_child'],
    ['editor: 세대주 둘 거절', 'editor', 'aal2', $q$select public.registry_household_add(:hh, ':seeded_b', 'self')::text$q$, 'ERR:세대주(본인)는 한 세대에 한 명', ''],
    ['editor: 이미 세대가 있는 사람으로 새 세대 거절', 'editor', 'aal2', $q$select public.registry_household_create(':seeded')::text$q$, 'ERR:이미 다른 세대에 속해 있습니다', ''],
    ['editor: 없는 관계 거절', 'editor', 'aal2', $q$select public.registry_household_add(:hh, null, 'cousin', '테스트')::text$q$, 'ERR:알 수 없는 값', ''],
    ['카드: 세대원 3명, 주소', 'viewer', 'aal2', $q$select jsonb_array_length(c -> 'household' -> 'members') || '/' || (c -> 'household' ->> 'address1') from (select public.registry_card(':seeded') c) x$q$, '3/테스트구 세대', ''],
    ['카드 열람 기록: 세대원 교인도 대상', 'pg', '', $q$select (target_ids @> array[':new'::uuid, ':seeded'::uuid])::text from privacy.access_logs where fn = 'registry_card' order by id desc limit 1$q$, 'true', ''],
    ['editor: registry 테이블 직접 조회 불가', 'editor', 'aal2', $q$select count(*)::text from registry.household_members$q$, 'ERR:permission denied for schema registry', ''],
    ['pg: 세대주 행 찾기', 'pg', '', $q$select id::text from registry.household_members where household_id = :hh and relation = 'self'$q$, '*', ':hm_self'],
    ['editor: 세대주를 먼저 빼기 거절', 'editor', 'aal2', $q$select 'ok' from (select public.registry_household_remove(:hm_self)) x$q$, 'ERR:세대주는 다른 세대원을 먼저', ''],
    ['editor: 배우자를 세대주로 바꾸기 거절 (세대주 있음)', 'editor', 'aal2', $q$select 'ok' from (select public.registry_household_member_update(:hm_spouse, 'self')) x$q$, 'ERR:세대주(본인)는 한 세대에 한 명', ''],
    ['editor: 다른 세대 만들기 (세대주 = 교인 B)', 'editor', 'aal2', $q$select public.registry_household_create(':seeded_b')::text$q$, '*', ':hh2'],
    ['editor: 배우자를 다른 세대로 옮기기', 'editor', 'aal2', $q$select public.registry_household_add(:hh2, ':seeded', 'spouse')::text$q$, '*', ''],
    ['세대: 옮긴 뒤 각 세대 인원', 'pg', '', $q$select (select count(*) from registry.household_members where household_id = :hh) || '/' || (select count(*) from registry.household_members where household_id = :hh2)$q$, '2/2', ''],
    ['editor: 자녀 빼기', 'editor', 'aal2', $q$select 'ok' from (select public.registry_household_remove(:hm_child)) x$q$, 'ok', ''],
    ['editor: 혼자 남은 세대주 빼기 → 세대도 지워짐', 'editor', 'aal2', $q$select 'ok' from (select public.registry_household_remove(:hm_self)) x$q$, 'ok', ''],
    ['세대: 빈 세대 삭제됨', 'pg', '', $q$select count(*)::text from registry.households where id = :hh$q$, '0', ''],
    -- 기존 사람을 교적에 등록 / 잘못 만든 교적 지우기
    ['확인 목록 첫 사람', 'pg', '', $q$select u.id::text from public.custom_users u where not exists (select 1 from registry.people p where p.person_id = u.id) and u.member and not exists (select 1 from public.small_group_members g where g.user_id = u.id) order by u.id limit 1$q$, '*', ':cand1'],
    ['editor: 교적에 등록', 'editor', 'aal2', $q$select 'ok' from (select public.registry_enroll(':cand1')) x$q$, 'ok', ''],
    ['등록: 상태 재적·날짜 미상, 확인 목록에서 빠짐', 'viewer', 'aal2', $q$select (c -> 'summary' ->> 'status') || '/' || coalesce(c -> 'status_events' -> 0 ->> 'event_date', '미상') || '/' || (select count(*) from public.registry_candidates()) from (select public.registry_card(':cand1') c) x$q$, 'active/미상/:exp_cand_minus1', ''],
    ['editor: 두 번 등록 거절', 'editor', 'aal2', $q$select 'ok' from (select public.registry_enroll(':cand1')) x$q$, 'ERR:이미 교적에 있습니다', ''],
    ['editor: 이유 없이 교적 지우기 거절', 'editor', 'aal2', $q$select 'ok' from (select public.registry_unenroll(':cand1', '')) x$q$, 'ERR:지우는 이유를 넣어 주세요', ''],
    ['editor: 잘못 만든 교적 지우기', 'editor', 'aal2', $q$select 'ok' from (select public.registry_unenroll(':cand1', '테스트')) x$q$, 'ok', ''],
    ['지우기: 교적 없음, 사람 행은 남음, 삭제 기록', 'pg', '', $q$select (select count(*) from registry.people where person_id = ':cand1') || '/' || (select count(*) from public.custom_users where id = ':cand1') || '/' || (select count(*) from privacy.change_logs where person_id = ':cand1' and op = 'DELETE' and table_name = 'registry.people')$q$, '0/1/1', ''],
    -- 가입 병합
    ['editor: 병합용 미가입 교인 등록', 'editor', 'aal2', $q$select public.registry_register('{"name":"테스트병합","phone":"010-9999-0001","office":"kwonsa"}')::text$q$, '*', ':ph_merge'],
    ['merge_acct: 가입자가 자기 이름·전화를 같게 저장', 'merge_acct', 'aal1', $q$with u as (update public.custom_users set name = '테스트병합', phone = '010-9999-0001' where auth_id = auth.uid() returning 1) select count(*)::text from u$q$, '1', ''],
    ['병합: 미가입 프로필 삭제, 교적·이력·호칭이 가입자에게', 'pg', '', $q$select (select count(*) from public.custom_users where id = ':ph_merge') || '/' || (select count(*) from registry.people where person_id = ':merge_acct') || '/' || (select count(*) from registry.status_events where person_id = ':merge_acct') || '/' || (select office || ':' || member || ':' || active from public.custom_users where id = ':merge_acct')$q$, '0/1/1/권사:true:true', ''],
    ['병합: 병합 기록, 가입 완료 메시지', 'pg', '', $q$select (select count(*) from privacy.change_logs where person_id = ':merge_acct' and op = 'MERGE') || '/' || (select count(*) from public.messages m join public.custom_users u on u.auth_id = m.receiver_id where u.id = ':merge_acct' and m.title = '가입 완료' and m.created_at >= now() - interval '1 minute')$q$, '1/1', ''],
    ['카드: 병합 전 기록도 이어서 보임', 'viewer', 'aal2', $q$select (jsonb_array_length(c -> 'history') >= 3)::text from (select public.registry_card(':merge_acct') c) x$q$, 'true', ''],
    ['editor: 미가입 프로필 둘 등록', 'editor', 'aal2', $q$select (public.registry_register('{"name":"테스트중복","phone":"010-9999-0003"}') is not null and public.registry_register('{"name":"테스트중복","phone":"010-9999-0004"}') is not null)::text$q$, 'true', ''],
    ['pg: 둘째 프로필 찾기', 'pg', '', $q$select id::text from public.custom_users where name = '테스트중복' and phone = '010-9999-0004'$q$, '*', ':dup2'],
    ['editor: 미가입 프로필의 전화를 다른 프로필과 같게 수정', 'editor', 'aal2', $q$select 'ok' from (select public.registry_save(':dup2', '{"phone":"010-9999-0003"}')) x$q$, 'ok', ''],
    ['미가입끼리는 합쳐지지 않음', 'pg', '', $q$select count(*)::text from public.custom_users where name = '테스트중복'$q$, '2', ''],
    ['editor: 충돌용 미가입 교인 등록', 'editor', 'aal2', $q$select public.registry_register('{"name":"테스트충돌","phone":"010-9999-0002"}')::text$q$, '*', ':ph_conflict'],
    ['merge_acct: 교적이 있는 가입자가 다른 교적 프로필과 같게 저장', 'merge_acct', 'aal1', $q$with u as (update public.custom_users set name = '테스트충돌', phone = '010-9999-0002' where auth_id = auth.uid() returning 1) select count(*)::text from u$q$, '1', ''],
    ['충돌: 합치지 않고 기록', 'pg', '', $q$select (select count(*) from public.custom_users where id in (':ph_conflict', ':merge_acct')) || '/' || (select count(*) from registry.merge_conflicts where account_id = ':merge_acct' and profile_id = ':ph_conflict')$q$, '2/1', ''],
    ['viewer: 충돌 목록', 'viewer', 'aal2', $q$select count(*)::text from public.registry_merge_conflicts() where profile_id = ':ph_conflict'$q$, '1', ''],
    -- 계정 연결 (수동)
    ['editor: 연결할 미가입 교인 등록 (전화 없음)', 'editor', 'aal2', $q$select public.registry_register('{"name":"테스트연결"}')::text$q$, '*', ':ph_link'],
    ['editor: 가입 계정끼리 연결 거절', 'editor', 'aal2', $q$select 'ok' from (select public.registry_link_account(':merge_acct', ':link_acct')) x$q$, 'ERR:두 사람 모두 가입한 계정', ''],
    ['editor: 계정 연결', 'editor', 'aal2', $q$select 'ok' from (select public.registry_link_account(':ph_link', ':link_acct')) x$q$, 'ok', ''],
    ['연결: 프로필 삭제, 교적이 가입 계정에게', 'pg', '', $q$select (select count(*) from public.custom_users where id = ':ph_link') || '/' || (select count(*) from registry.people where person_id = ':link_acct')$q$, '0/1', ''],
    -- 앱 탈퇴
    ['authenticated: 탈퇴 준비 함수 실행 불가', 'outsider', 'aal2', $q$select public.account_delete_prepare(auth.uid())$q$, 'ERR:permission denied', ''],
    ['service: 교적 있는 계정 탈퇴 → 연결만 끊음', 'service', '', $q$select public.account_delete_prepare(':merge_acct_auth')$q$, 'unlinked', ''],
    ['탈퇴(연결 끊기): 행·교적 남음, 미가입으로, 로그인 연결 없음', 'pg', '', $q$select (select count(*) from public.custom_users where id = ':merge_acct' and not active and auth_id <> ':merge_acct_auth' and email is null and role = 4) || '/' || (select count(*) from registry.people where person_id = ':merge_acct') || '/' || (select count(*) from public.posts where user_id = ':merge_acct_auth')$q$, '1/1/0', ''],
    ['service: 교적·목장·출석 없는 계정 탈퇴 → 삭제', 'service', '', $q$select public.account_delete_prepare(':plain_acct_auth')$q$, 'deleted', ''],
    ['탈퇴(삭제): 행 없음', 'pg', '', $q$select count(*)::text from public.custom_users where id = ':plain_acct'$q$, '0', ''],
    ['service: 없는 계정', 'service', '', $q$select public.account_delete_prepare(gen_random_uuid())$q$, 'none', ''],
    -- 기록과 기존 기능
    ['접속기록: 쓴 함수 종류', 'pg', '', $q$select count(distinct fn)::text from privacy.access_logs where id > :a0$q$, '*', ''],
    ['접속기록: 모든 기록에 처리자', 'pg', '', $q$select count(*) filter (where actor_user_id is null)::text from privacy.access_logs where id > :a0$q$, '0', ''],
    ['기존 출석 통계 그대로', 'pg', '', $q$select left(md5(coalesce(public.att_full(null::bigint)::text, 'null')), 8)$q$, ':att0', '']
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
begin
  -- 푸시 알림 webhook 은 테스트 동안 끈다 (되돌려진다)
  alter table public.messages disable trigger "send-notification";

  -- 대상 계정 (ID 만)
  select tok || jsonb_build_object(':admin', u.id::text), who || jsonb_build_object('admin', u.auth_id::text)
    into tok, who
    from public.custom_users u join public.roles r on r.id = u.role
   where r.level >= 100 and u.active order by u.id limit 1;
  for rec in
    select x.id, x.auth_id, row_number() over (order by x.id) as rn
      from (select u.id, u.auth_id from public.custom_users u join public.roles r on r.id = u.role
             where r.level < 50 and u.active
               and exists (select 1 from auth.users a where a.id = u.auth_id)
               and not exists (select 1 from registry.staff s where s.user_id = u.id)
             order by u.id limit 3) x
  loop
    k := (array['editor', 'viewer', 'outsider'])[rec.rn];
    tok := tok || jsonb_build_object(':' || k, rec.id::text);
    who := who || jsonb_build_object(k, rec.auth_id::text);
    picked := picked || rec.id;
  end loop;
  -- 병합·연결용: 로그인 계정, 교적 없음, 위와 다른 사람
  for rec in
    select x.id, x.auth_id, row_number() over (order by x.id) as rn
      from (select u.id, u.auth_id from public.custom_users u join public.roles r on r.id = u.role
             where r.level < 100
               and exists (select 1 from auth.users a where a.id = u.auth_id)
               and not exists (select 1 from registry.people p where p.person_id = u.id)
               and not exists (select 1 from registry.staff s where s.user_id = u.id)
               and u.id <> all (picked)
             order by u.id limit 2) x
  loop
    k := (array['merge_acct', 'link_acct'])[rec.rn];
    tok := tok || jsonb_build_object(':' || k, rec.id::text, ':' || k || '_auth', rec.auth_id::text);
    who := who || jsonb_build_object(k, rec.auth_id::text);
    picked := picked || rec.id;
  end loop;
  -- 탈퇴(삭제)용: 로그인 계정, 교적·목장·출석 기록 없음
  select tok || jsonb_build_object(':plain_acct', u.id::text, ':plain_acct_auth', u.auth_id::text) into tok
    from public.custom_users u join public.roles r on r.id = u.role
   where r.level < 50
     and exists (select 1 from auth.users a where a.id = u.auth_id)
     and not exists (select 1 from registry.people p where p.person_id = u.id)
     and not exists (select 1 from public.small_group_members g where g.user_id = u.id)
     and not exists (select 1 from public.attendance_records x where x.recorded_by = u.id)
     and not exists (select 1 from public.member_notes x where x.created_by = u.id)
     and not exists (select 1 from public.group_session_notes x where x.created_by = u.id)
     and u.id <> all (picked)
   order by u.id limit 1;
  -- 초기 생성된 미가입 교인 둘 (재적 기록 1건)
  for rec in
    select x.person_id, row_number() over (order by x.person_id) as rn
      from (select p.person_id from registry.people p join public.custom_users u on u.id = p.person_id
             where not exists (select 1 from auth.users a where a.id = u.auth_id)
               and (select count(*) from registry.status_events e where e.person_id = p.person_id) = 1
               and not exists (select 1 from registry.household_members m where m.person_id = p.person_id)
             order by p.person_id limit 2) x
  loop
    tok := tok || jsonb_build_object((array[':seeded', ':seeded_b'])[rec.rn], rec.person_id::text);
  end loop;
  tok := tok || jsonb_build_object(
    ':group_id', (select g.small_group_id::text from public.small_group_members g
                    join public.small_groups s on s.id = g.small_group_id
                   where g.active and s.active group by 1 order by count(*) desc limit 1),
    ':exp_people', (select count(*)::text from public.custom_users u
                     where u.member and exists (select 1 from public.small_group_members g
                       join public.small_groups s on s.id = g.small_group_id
                      where g.user_id = u.id and g.active and s.active)),
    ':exp_cand', (select count(*)::text from public.custom_users u
                   where not exists (select 1 from registry.people p where p.person_id = u.id)
                     and u.member <> exists (select 1 from public.small_group_members g
                       join public.small_groups s on s.id = g.small_group_id
                      where g.user_id = u.id and g.active and s.active)),
    ':a0', (select coalesce(max(l.id), 0)::text from privacy.access_logs l),
    ':att0', (select left(md5(coalesce(public.att_full(null::bigint)::text, 'null')), 8)));
  tok := tok || jsonb_build_object(':exp_cand_minus1', ((tok ->> ':exp_cand')::int - 1)::text);
  if tok ->> ':plain_acct' is null or tok ->> ':link_acct' is null or tok ->> ':seeded_b' is null
     or tok ->> ':outsider' is null then
    raise exception 'TEST_SETUP 대상 계정을 고르지 못했습니다: %', (select array_agg(k2) from jsonb_object_keys(tok) k2);
  end if;

  -- 교적 권한 (테스트 동안만)
  insert into registry.staff (user_id, can_edit, can_export, note)
  values ((tok ->> ':editor')::uuid, true, true, 'TEST'), ((tok ->> ':viewer')::uuid, false, false, 'TEST');

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
      if persona = 'anon' then
        perform set_config('request.jwt.claims', '{"role":"anon"}', true);
        perform set_config('request.jwt.claim.sub', '', true);
        perform set_config('role', 'anon', true);
      elsif persona = 'service' then
        perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
        perform set_config('request.jwt.claim.sub', '', true);
        perform set_config('role', 'service_role', true);
      else
        perform set_config('request.jwt.claims',
          json_build_object('sub', sub, 'role', 'authenticated', 'session_id', md5(sub || coalesce(nullif(t[3], ''), 'aal2'))::uuid)::text, true);
        perform set_config('request.jwt.claim.sub', sub, true);
        if persona <> 'pg' then
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

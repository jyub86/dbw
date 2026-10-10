-- 초기 교적 생성 (2026-10-11): 기존 프로필에서 교적을 만든다
--
-- 설계: docs/church-admin/02-registry-design.md §8, §9 결정 7~9
--   대상: 교인 표시(member=true)이고 지금 목장 명단(활성 목장의 활성 소속)에 있는 사람
--   만드는 것: 교적 행(교번 없음), '등록' 이벤트(날짜 미상), 지금 호칭이 직분이면 직분 이력 1건(시무, 임직일 미상)
--   만들지 않는 것: 신급·주소·세대 (자료 없음. 신급은 '미확인'으로 보인다)
--   나머지 사람(목장에 없는 교인, 교인 인증 전 목장 구성원)은 registry_candidates() 확인 목록에 나온다
--
-- 실행 전 조건
--   1. 20261011_registry_core 적용
--   2. Edge Function delete-account 새 버전 배포 (교적이 생기면 사람 행을 지울 수 없어서, 옛 버전은 탈퇴가 실패한다)
--
-- 다시 실행해도 이미 교적이 있는 사람은 건너뛴다. 만든 행은 모두 privacy.change_logs 에 남는다.

insert into registry.people (person_id)
select u.id
  from public.custom_users u
 where u.member
   and exists (select 1 from public.small_group_members g
                 join public.small_groups s on s.id = g.small_group_id
                where g.user_id = u.id and g.active and s.active)
   and not exists (select 1 from registry.people p where p.person_id = u.id);

insert into registry.status_events (person_id, kind, event_date, reason)
select p.person_id, 'register', null, '기존 프로필에서 교적 생성'
  from registry.people p
 where not exists (select 1 from registry.status_events e where e.person_id = p.person_id);

-- 호칭 → 직분: 시무집사 → 시무집사, 집사 → 서리집사, 장로·권사·목사·전도사는 그대로 (codes.title 로 맞춘다)
insert into registry.office_terms (person_id, office, standing, note)
select p.person_id, c.code, 'serving', '기존 프로필 호칭에서 가져옴'
  from registry.people p
  join public.custom_users u on u.id = p.person_id
  join registry.codes c on c.category = 'office' and c.title = u.office
 where not exists (select 1 from registry.office_terms t where t.person_id = p.person_id);

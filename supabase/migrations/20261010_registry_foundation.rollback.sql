-- 20261010_registry_foundation 되돌리기
-- 교적 운영을 시작하기 전에만 쓴다. privacy 스키마를 지우면 접속기록·권한 이력도 함께 사라진다.
-- 운영을 시작한 뒤에는 되돌리지 말고 고치는 마이그레이션을 새로 만든다(기록 보관 의무).

select cron.unschedule('privacy-purge-expired');

drop function if exists public.registry_me();
drop function if exists public.registry_staff_list();
drop function if exists public.registry_staff_set(uuid, boolean, boolean, boolean, text);
drop function if exists public.registry_staff_remove(uuid);
drop function if exists public.privacy_access_logs(timestamptz, timestamptz, uuid, uuid, integer, integer);
drop function if exists public.privacy_permission_logs(integer, integer);

drop schema if exists registry cascade;
drop schema if exists privacy cascade;

notify pgrst, 'reload schema';

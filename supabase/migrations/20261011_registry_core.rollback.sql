-- 20261011_registry_core (+ registry_seed) 되돌리기
-- 교적 운영을 시작하기 전에만 쓴다. 교적 데이터가 모두 지워진다(변경기록은 privacy 에 남는다).
-- 먼저 Edge Function delete-account 를 custom_users 를 직접 지우는 옛 버전으로 되돌린 뒤 실행한다.

do $drop$
declare
  f regprocedure;
begin
  for f in
    select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like 'registry\_%'
       and p.proname not in ('registry_me', 'registry_staff_list', 'registry_staff_set', 'registry_staff_remove')
  loop
    execute format('drop function %s', f);
  end loop;
end
$drop$;
drop function if exists public.account_delete_prepare(uuid);

-- 가입 병합·환영 메시지를 적용 전 정의로
create or replace function public.merge_user_data() returns trigger
language plpgsql security definer set search_path to 'public' as $function$
DECLARE
  inactive_user RECORD;
  new_phone_norm text;
BEGIN
  IF NEW.name IS NOT DISTINCT FROM OLD.name
     AND NEW.phone IS NOT DISTINCT FROM OLD.phone THEN
    RETURN NEW;
  END IF;
  new_phone_norm := regexp_replace(coalesce(NEW.phone, ''), '[^0-9]', '', 'g');
  IF new_phone_norm = '' OR NEW.name IS NULL OR btrim(NEW.name) = '' THEN
    RETURN NEW;
  END IF;
  SELECT * INTO inactive_user
  FROM public.custom_users
  WHERE active = false
    AND id <> NEW.id
    AND btrim(name) = btrim(NEW.name)
    AND regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g') = new_phone_norm
  LIMIT 1;
  IF FOUND THEN
    UPDATE public.small_group_members sgm
       SET user_id = NEW.id
     WHERE sgm.user_id = inactive_user.id
       AND NOT EXISTS (
         SELECT 1 FROM public.small_group_members x
          WHERE x.small_group_id = sgm.small_group_id
            AND x.user_id = NEW.id
       );
    UPDATE public.attendance_records SET recorded_by = NEW.id WHERE recorded_by = inactive_user.id;
    UPDATE public.member_notes        SET created_by  = NEW.id WHERE created_by  = inactive_user.id;
    UPDATE public.user_groups SET user_id = NEW.auth_id WHERE user_id = inactive_user.auth_id;
    DELETE FROM public.custom_users WHERE id = inactive_user.id;
    UPDATE public.custom_users
       SET active = true,
           gender = COALESCE(inactive_user.gender, gender),
           birth_date = COALESCE(inactive_user.birth_date, birth_date),
           office = inactive_user.office,
           member = inactive_user.member
     WHERE id = NEW.id;
    INSERT INTO public.messages(receiver_id, title, message, message_type, sender_id)
    VALUES (NEW.auth_id, '가입 완료', NEW.name || inactive_user.office || '님, 부평동부교회 애플리케이션 가입이 완료되었습니다!', 'personal', 'aaa3a5de-67d1-4e47-80dd-f972407681af');
  END IF;
  RETURN NEW;
END;
$function$;

create or replace function public.welcome_new_user() returns trigger
language plpgsql security definer set search_path to 'public' as $function$
BEGIN
  INSERT INTO public.messages(receiver_id, title, message, message_type, sender_id)
  VALUES (
    NEW.auth_id,
    '환영합니다!',
    COALESCE(NULLIF(btrim(NEW.name), ''), '회원') || '님, 부평동부교회 앱에 가입하신 것을 진심으로 환영합니다. 더보기에서 이름과 전화번호 및 프로필 사진을 업데이트 해주세요. 신속하게 가입 절차를 진행해 드리겠습니다.',
    'personal',
    'aaa3a5de-67d1-4e47-80dd-f972407681af'
  );
  RETURN NEW;
END;
$function$;

alter function public.update_active_status_when_update_user_info() reset search_path;

drop view if exists registry.summary;
drop table if exists registry.household_members, registry.households, registry.status_events, registry.faith_events,
  registry.office_terms, registry.notes, registry.consents, registry.merge_conflicts, registry.people, registry.codes;
drop function if exists registry.touch(), registry.status_of_kind(text), registry.assert_person(uuid),
  registry.assert_code(text, text), registry.log_profile_change(uuid, text, jsonb, jsonb), registry.sync_member(uuid),
  registry.sync_office(uuid), registry.office_from_profile(uuid), registry.merge_people(uuid, uuid);

notify pgrst, 'reload schema';

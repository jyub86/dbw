-- 20261012_registry_purge 되돌리기. 이미 파기한 값은 돌아오지 않는다(purged_on 열만 지운다)

select cron.unschedule('registry-purge-departed');

drop function if exists registry.purge_departed(date);
drop function if exists registry.purge_redact(text, jsonb);

create or replace function privacy.log_change() returns trigger
language plpgsql security definer set search_path = '' as $fn$
declare
  o       jsonb;
  n       jsonb;
  r       jsonb;
  changed text[];
  me      record;
begin
  if tg_op <> 'INSERT' then o := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then n := to_jsonb(new); end if;
  r := coalesce(n, o);
  if tg_op = 'UPDATE' then
    select array_agg(k order by k) into changed
      from jsonb_object_keys(n) as k
     where k <> 'updated_at' and n -> k is distinct from o -> k;
    if changed is null then
      return new;
    end if;
  end if;
  select u.id, u.name into me from public.custom_users u where u.auth_id = auth.uid();
  insert into privacy.change_logs
    (table_name, op, person_id, record_id, actor_auth_id, actor_user_id, actor_name, old_data, new_data, changed_fields)
  values
    (tg_table_schema || '.' || tg_table_name, tg_op, (r ->> 'person_id')::uuid,
     coalesce(r ->> 'id', r ->> 'person_id'), auth.uid(), me.id, me.name, o, n, changed);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$fn$;

create or replace function privacy.forbid_mutation() returns trigger
language plpgsql set search_path = '' as $fn$
begin
  -- NEW/OLD 는 해당 작업일 때만 읽는다 (DELETE 가 아닌 경우 OLD 가 없을 수 있다)
  if tg_op = 'DELETE' and current_setting('privacy.purging', true) = 'on' then
    if (to_jsonb(old) ->> 'at')::timestamptz < now() - tg_argv[0]::interval then
      return old;
    end if;
  end if;
  raise exception '%.% 은(는) 추가만 할 수 있습니다', tg_table_schema, tg_table_name using errcode = '42501';
end
$fn$;

alter table registry.people drop column if exists purged_on;

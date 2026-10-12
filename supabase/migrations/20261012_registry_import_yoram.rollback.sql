-- 교적 ③-2(요람 반영) 되돌리기: 세 함수를 20261012_registry_import.sql 의 정의로 되돌린다

create or replace function registry.dimode_office(p_office text, p_detail text, out code text, out standing text)
language sql immutable set search_path = '' as $fn$
  select m[1], m[2]
    from (select case coalesce(nullif(btrim(p_detail), ''), btrim(p_office))
      when '서리집사'     then array['deacon', 'serving']
      when '집사'         then array['deacon', 'serving']
      when '명예집사'     then array['deacon', 'honorary']
      when '안수집사'     then array['ordained_deacon', 'serving']
      when '시무집사'     then array['ordained_deacon', 'serving']
      when '은퇴안수집사' then array['ordained_deacon', 'retired']
      when '협동안수집사' then array['ordained_deacon', 'cooperating']
      when '권사'         then array['kwonsa', 'serving']
      when '시무권사'     then array['kwonsa', 'serving']
      when '명예권사'     then array['kwonsa', 'honorary']
      when '은퇴권사'     then array['kwonsa', 'retired']
      when '협동권사'     then array['kwonsa', 'cooperating']
      when '장로'         then array['elder', 'serving']
      when '시무장로'     then array['elder', 'serving']
      when '은퇴장로'     then array['elder', 'retired']
      when '전입은퇴장로' then array['elder', 'retired']
      when '원로장로'     then array['elder', 'emeritus']
      when '목사'         then array['pastor', 'serving']
      when '담임목사'     then array['pastor', 'serving']
      when '부목사'       then array['pastor', 'serving']
      when '협동목사'     then array['pastor', 'cooperating']
      when '전도사'       then array['evangelist', 'serving']
      when '교육전도사'   then array['evangelist', 'serving']
      when '전임전도사'   then array['evangelist', 'serving']
      when '심방전도사'   then array['evangelist', 'serving']
    end as m) x
$fn$;

create or replace function registry.import_rematch() returns void
language plpgsql security definer set search_path = '' as $fn$
begin
  with u as (
    select u.id, registry.name_key(u.name) as nk, u.birth_date as b, registry.digits(u.phone) as ph
      from public.custom_users u
  ),
  c as (
    select r.id as row_id, u.id as person_id,
           case when u.nk = r.name_key
                 and ((r.birth_date is not null and u.b = r.birth_date) or u.ph = any (r.phones)) then 'strong'
                when u.nk = r.name_key then 'name'
                else 'phone' end as kind
      from registry.import_rows r
      join u on (u.nk = r.name_key and r.name_key <> '') or (u.ph is not null and u.ph = r.mobile)
     where r.applied_at is null
  )
  update registry.import_rows r
     set candidates = coalesce((
           select jsonb_agg(jsonb_build_object('person_id', c.person_id, 'kind', c.kind)
                            order by case c.kind when 'strong' then 0 when 'name' then 1 else 2 end, c.person_id)
             from c where c.row_id = r.id), '[]')
   where r.applied_at is null;

  with strong as (
    select r.id, (r.candidates -> 0 ->> 'person_id')::uuid as pid
      from registry.import_rows r
     where r.applied_at is null
       and (select count(*) from jsonb_array_elements(r.candidates) e where e ->> 'kind' = 'strong') = 1
  ),
  dup as (select s.pid from strong s group by s.pid having count(*) > 1)
  update registry.import_rows r
     set suggestion = case
           when r.sheet = 'main' and s.pid is not null and not exists (select 1 from dup where dup.pid = s.pid) then 'link'
           when jsonb_array_length(r.candidates) = 0 and r.sheet = 'main'
                and r.data ->> 'status' in ('예배출석', '가끔출석') then 'new'
           else 'review'
         end
    from (select r2.id, s.pid from registry.import_rows r2 left join strong s on s.id = r2.id
           where r2.applied_at is null) s
   where s.id = r.id;
end
$fn$;

create or replace function public.registry_import_load(p_rows jsonb) returns integer
language plpgsql security definer set search_path = '' as $fn$
declare
  n integer;
begin
  perform registry.require('edit');
  perform registry.require_admin();
  if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception '올릴 행이 없습니다' using errcode = '22023';
  end if;
  if jsonb_array_length(p_rows) > 500 then
    raise exception '한 번에 500행까지 올릴 수 있습니다' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(p_rows) x
              where jsonb_typeof(x -> 'data') is distinct from 'object'
                 or coalesce(x ->> 'sheet', 'main') not in ('main', 'deceased')) then
    raise exception '파일 형식이 맞지 않습니다' using errcode = '22023';
  end if;

  insert into registry.import_rows (source, src_id, sheet, data, memo, name_key, birth_date, phones, mobile, uploaded_by)
  select 'dimode', x ->> 'src_id', coalesce(x ->> 'sheet', 'main'), x -> 'data', nullif(btrim(x ->> 'memo'), ''),
         registry.name_key(x -> 'data' ->> 'name'),
         case when x -> 'data' ->> 'birth_date' ~ '^\d{4}-\d{2}-\d{2}$' then (x -> 'data' ->> 'birth_date')::date end,
         array_remove(array[registry.digits(x -> 'data' ->> 'mobile'), registry.digits(x -> 'data' ->> 'home_phone')], null),
         registry.digits(x -> 'data' ->> 'mobile'),
         public.app_current_user_id()
    from jsonb_array_elements(p_rows) x
   where nullif(btrim(x ->> 'src_id'), '') is not null
     and nullif(btrim(x -> 'data' ->> 'name'), '') is not null
  on conflict (source, src_id) do update
     set sheet = excluded.sheet, data = excluded.data, memo = excluded.memo, name_key = excluded.name_key,
         birth_date = excluded.birth_date, phones = excluded.phones, mobile = excluded.mobile,
         uploaded_by = excluded.uploaded_by, uploaded_at = now()
   where registry.import_rows.applied_at is null;
  get diagnostics n = row_count;

  perform registry.import_rematch();
  perform privacy.log_access('create', 'registry_import_load', '{}', jsonb_build_object('rows', n));
  return n;
end
$fn$;

revoke all on all functions in schema registry from public;

revoke all on function public.registry_import_load(jsonb) from public, anon;

grant execute on function public.registry_import_load(jsonb) to authenticated;

notify pgrst, 'reload schema';

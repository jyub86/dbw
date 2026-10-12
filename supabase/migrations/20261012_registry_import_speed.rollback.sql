-- 20261012_registry_import_speed 되돌리기: 요람 반영판(20261012_registry_import_yoram) 의 import_rematch 로 되돌린다

create or replace function registry.import_rematch() returns void
language plpgsql security definer set search_path = '' as $fn$
begin
  with u as (
    select u.id, registry.name_key(u.name) as nk, u.birth_date as b, registry.digits(u.phone) as ph,
           (select array_agg(sg.name) from public.small_group_members m
              join public.small_groups sg on sg.id = m.small_group_id
             where m.user_id = u.id and m.active and sg.active) as groups
      from public.custom_users u
  ),
  c as (
    select r.id as row_id, u.id as person_id,
           case when u.nk = r.name_key
                 and ((r.birth_date is not null and u.b = r.birth_date)
                      or u.ph = any (r.phones)
                      or (r.data -> 'yoram' ->> 'group') = any (u.groups)) then 'strong'
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
                and (r.data ->> 'status' in ('예배출석', '가끔출석') or r.data ? 'yoram') then 'new'
           else 'review'
         end
    from (select r2.id, s.pid from registry.import_rows r2 left join strong s on s.id = r2.id
           where r2.applied_at is null) s
   where s.id = r.id;
end
$fn$;

-- 교적 ③-3: 디모데 가져오기 대조(import_rematch)를 빠르게 (2026-10-12)
--
-- 증상: 파일을 150행씩 올리다가 두 번째 묶음(300행)에서 '올리지 못했습니다' — authenticated 의 8초 제한.
-- 원인: 후보 목록을 행마다 상관 하위 질의로 붙여서, 한 번만 쓰인 CTE 가 행마다 다시 계산됐다
--       (사람 633명의 name_key·digits 와 목장 목록을 올린 행 수만큼 반복 → 행이 늘수록 제곱으로 느려짐).
-- 고침: 사람 쪽 값과 행별 후보를 한 번만 계산(MATERIALIZED)해서 JOIN 으로 붙인다. 결과(candidates·suggestion)는 그대로.

create or replace function registry.import_rematch() returns void
language plpgsql security definer set search_path = '' as $fn$
begin
  with u as materialized (
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
  ),
  agg as materialized (
    select c.row_id,
           jsonb_agg(jsonb_build_object('person_id', c.person_id, 'kind', c.kind)
                     order by case c.kind when 'strong' then 0 when 'name' then 1 else 2 end, c.person_id) as cands
      from c
     group by c.row_id
  )
  update registry.import_rows r
     set candidates = coalesce(x.cands, '[]')
    from (select r2.id, agg.cands
            from registry.import_rows r2
            left join agg on agg.row_id = r2.id
           where r2.applied_at is null) x
   where x.id = r.id;

  with strong as materialized (
    select r.id, (r.candidates -> 0 ->> 'person_id')::uuid as pid
      from registry.import_rows r
     where r.applied_at is null
       and (select count(*) from jsonb_array_elements(r.candidates) e where e ->> 'kind' = 'strong') = 1
  ),
  dup as materialized (select s.pid from strong s group by s.pid having count(*) > 1)
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

revoke all on function registry.import_rematch() from public;

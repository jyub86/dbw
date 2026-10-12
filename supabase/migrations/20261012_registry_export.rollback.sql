-- 교적 ④(내려받기) 되돌리기: registry_export·filter_people 을 지우고 registry_search 를 20261011_registry_core.sql 의 정의로 되돌린다

drop function if exists public.registry_export(jsonb, text[], text);

create or replace function public.registry_search(p_filters jsonb default '{}', p_limit integer default 50, p_offset integer default 0)
returns table (person_id uuid, name text, name_note text, gender text, birth_date date, phone text, office text,
               status text, faith text, community_id bigint, community_name text, group_id bigint, group_name text,
               has_account boolean, registered_on date, total bigint)
language plpgsql security definer set search_path = '' as $fn$
#variable_conflict use_column
declare
  f     jsonb := coalesce(p_filters, '{}');
  terms text[];
  ids   uuid[];
  tot   bigint;
begin
  perform registry.require('view');
  select array_agg(t) into terms
    from (select btrim(x) as t from regexp_split_to_table(coalesce(f ->> 'q', ''), '[,\s]+') x) y
   where t <> '';

  select array_agg(b.person_id order by b.sort_name, b.person_id), max(b.total)
    into ids, tot
    from (
      select s.person_id, coalesce(u.name, '') as sort_name, count(*) over () as total
        from registry.summary s
        join public.custom_users u on u.id = s.person_id
       where (terms is null or exists (
               select 1 from unnest(terms) t
                where u.name ilike '%' || t || '%'
                   or (t ~ '^[0-9-]{4,}$'
                       and regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g') like '%' || replace(t, '-', '') || '%')))
         and (not f ? 'status' or s.status in (select jsonb_array_elements_text(f -> 'status')))
         and (not f ? 'faith' or s.faith in (select jsonb_array_elements_text(f -> 'faith')))
         and (not f ? 'office' or coalesce(s.office, 'none') in (select jsonb_array_elements_text(f -> 'office')))
         and (f ->> 'community_id' is null or s.community_id = (f ->> 'community_id')::bigint)
         and (f ->> 'group_id' is null or s.group_id = (f ->> 'group_id')::bigint)
         and (f ->> 'gender' is null or u.gender = f ->> 'gender')
         and (f ->> 'age_min' is null or extract(year from age(current_date, u.birth_date)) >= (f ->> 'age_min')::int)
         and (f ->> 'age_max' is null or extract(year from age(current_date, u.birth_date)) <= (f ->> 'age_max')::int)
         and (f ->> 'registered_from' is null or s.registered_on >= (f ->> 'registered_from')::date)
         and (f ->> 'registered_to' is null or s.registered_on <= (f ->> 'registered_to')::date)
         and (f ->> 'has_account' is null
              or exists (select 1 from auth.users a where a.id = u.auth_id) = (f ->> 'has_account')::boolean)
       order by coalesce(u.name, ''), s.person_id
       limit least(greatest(coalesce(p_limit, 50), 1), 500)
      offset greatest(coalesce(p_offset, 0), 0)) b;

  perform privacy.log_access('search', 'registry_search', coalesce(ids, '{}'),
    jsonb_build_object('filters', f, 'limit', p_limit, 'offset', p_offset, 'total', coalesce(tot, 0)));

  return query
    select s.person_id, u.name, p.name_note, u.gender, u.birth_date, u.phone, u.office,
           s.status, s.faith, s.community_id, s.community_name, s.group_id, s.group_name,
           exists (select 1 from auth.users a where a.id = u.auth_id), s.registered_on, coalesce(tot, 0)
      from registry.summary s
      join registry.people p on p.person_id = s.person_id
      join public.custom_users u on u.id = s.person_id
     where s.person_id = any (coalesce(ids, '{}'))
     order by array_position(ids, s.person_id);
end
$fn$;

drop function if exists registry.filter_people(jsonb);

notify pgrst, 'reload schema';

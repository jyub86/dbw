-- 교적 ④: 내려받기 — 용도를 적고 고른 항목만 받는다 (설계 §7, §11 4)
--
-- 안전성 확보조치 기준: 출력(파일 생성 포함) 때 용도를 특정하고 용도에 따라 항목을 최소화한다.
--   1. registry.filter_people: 목록 화면(registry_search)과 내려받기가 같은 조건식을 쓰도록 뺀 헬퍼
--   2. registry_search: 조건식을 헬퍼로 바꿨을 뿐 결과·기록은 그대로
--   3. registry_export(조건, 항목, 용도): 내려받기 권한(can_export) + 2단계 인증.
--      용도(2~200자)와 항목 목록은 필수이고, 이름은 늘 들어간다. 메모·디모데 메모는 항목에 없다.
--      접속기록에 action 'export' 로 용도·조건·항목·인원을 남긴다.

create or replace function registry.filter_people(p_filters jsonb)
returns table (person_id uuid, sort_name text)
language plpgsql stable set search_path = '' as $fn$
#variable_conflict use_column
declare
  f     jsonb := coalesce(p_filters, '{}');
  terms text[];
begin
  select array_agg(t) into terms
    from (select btrim(x) as t from regexp_split_to_table(coalesce(f ->> 'q', ''), '[,\s]+') x) y
   where t <> '';
  return query
    select s.person_id, coalesce(u.name, '')
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
            or exists (select 1 from auth.users a where a.id = u.auth_id) = (f ->> 'has_account')::boolean);
end
$fn$;

create or replace function public.registry_search(p_filters jsonb default '{}', p_limit integer default 50, p_offset integer default 0)
returns table (person_id uuid, name text, name_note text, gender text, birth_date date, phone text, office text,
               status text, faith text, community_id bigint, community_name text, group_id bigint, group_name text,
               has_account boolean, registered_on date, total bigint)
language plpgsql security definer set search_path = '' as $fn$
#variable_conflict use_column
declare
  f   jsonb := coalesce(p_filters, '{}');
  ids uuid[];
  tot bigint;
begin
  perform registry.require('view');
  select array_agg(b.person_id order by b.sort_name, b.person_id), max(b.total)
    into ids, tot
    from (
      select fp.person_id, fp.sort_name, count(*) over () as total
        from registry.filter_people(f) fp
       order by fp.sort_name, fp.person_id
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

-- 항목 키는 화면(src/lib/registry.ts EXPORT_COLUMNS)과 같다.
-- 주소는 개인 주소가 있으면 개인 주소, 없으면 세대 주소(설계 §3.2).
create or replace function public.registry_export(p_filters jsonb, p_columns text[], p_purpose text)
returns setof jsonb
language plpgsql security definer set search_path = '' as $fn$
declare
  allowed constant text[] := array[
    'name', 'name_note', 'gender', 'birth_date', 'birth_lunar', 'age', 'phone', 'home_phone', 'zip', 'address',
    'office', 'status', 'faith', 'community', 'group', 'registered_on', 'head', 'relation',
    'occupation', 'workplace', 'marital', 'wedding_date', 'previous_church', 'guide'];
  purpose text := btrim(coalesce(p_purpose, ''));
  cols    text[];
  bad     text[];
  ids     uuid[];
begin
  perform registry.require('export');
  if char_length(purpose) < 2 or char_length(purpose) > 200 then
    raise exception '내려받는 용도를 2~200자로 적어 주세요' using errcode = '22023';
  end if;
  if coalesce(cardinality(p_columns), 0) = 0 then
    raise exception '내려받을 항목을 골라 주세요' using errcode = '22023';
  end if;
  select array_agg(c order by array_position(allowed, c)) into cols
    from (select distinct c from unnest(p_columns || array['name']) c) x;
  select array_agg(c) into bad from unnest(cols) c where c <> all (allowed) or c is null;
  if bad is not null then
    raise exception '내려받을 수 없는 항목입니다: %', array_to_string(bad, ', ', '(빈 값)') using errcode = '22023';
  end if;

  select array_agg(fp.person_id order by fp.sort_name, fp.person_id) into ids
    from registry.filter_people(p_filters) fp;
  ids := coalesce(ids, '{}');

  perform privacy.log_access('export', 'registry_export', ids,
    jsonb_build_object('purpose', purpose, 'filters', coalesce(p_filters, '{}'), 'columns', to_jsonb(cols),
                       'count', cardinality(ids)));

  return query
    select (select jsonb_object_agg(e.key, e.value) from jsonb_each(r.doc) e where e.key = any (cols))
      from (
        select x.ord, jsonb_build_object(
                 'name', u.name,
                 'name_note', p.name_note,
                 'gender', u.gender,
                 'birth_date', u.birth_date,
                 'birth_lunar', p.birth_lunar,
                 'age', extract(year from age(current_date, u.birth_date))::int,
                 'phone', u.phone,
                 'home_phone', h.home_phone,
                 'zip', case when own.has then p.address_zip else h.address_zip end,
                 'address', nullif(case when own.has then concat_ws(' ', p.address1, nullif(btrim(p.address2), ''))
                                        else concat_ws(' ', nullif(btrim(h.address1), ''), nullif(btrim(h.address2), '')) end, ''),
                 'office', u.office,
                 'status', s.status,
                 'faith', s.faith,
                 'community', s.community_name,
                 'group', s.group_name,
                 'registered_on', s.registered_on,
                 'head', hd.name,
                 'relation', hm.relation,
                 'occupation', p.occupation,
                 'workplace', p.workplace,
                 'marital', p.marital_status,
                 'wedding_date', p.wedding_date,
                 'previous_church', p.previous_church,
                 'guide', coalesce(gu.name, p.guide_name)) as doc
          from unnest(ids) with ordinality x(id, ord)
          join registry.summary s on s.person_id = x.id
          join registry.people p on p.person_id = x.id
          join public.custom_users u on u.id = x.id
          cross join lateral (select nullif(btrim(p.address1), '') is not null as has) own
          left join registry.household_members hm on hm.person_id = x.id
          left join registry.households h on h.id = hm.household_id
          left join lateral (
            select coalesce(hu.name, m.name) as name
              from registry.household_members m
              left join public.custom_users hu on hu.id = m.person_id
             where m.household_id = hm.household_id and m.relation = 'self'
          ) hd on true
          left join public.custom_users gu on gu.id = p.guide_person_id
      ) r
     order by r.ord;
end
$fn$;

revoke all on function public.registry_export(jsonb, text[], text) from public, anon;
grant execute on function public.registry_export(jsonb, text[], text) to authenticated;

revoke all on all functions in schema registry from public;

notify pgrst, 'reload schema';

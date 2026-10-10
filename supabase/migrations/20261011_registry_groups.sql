-- 교적 화면용 공동체·목장 목록 (2026-10-11)
--
-- small_groups 는 리더·출석 담당자만 읽을 수 있어서, 출석 담당이 아닌 교적 담당자(사무 간사 등)는
-- 교적 검색의 공동체·목장 필터를 채울 수 없다. 이름만 돌려주므로 접속기록은 남기지 않는다.

create function public.registry_groups()
returns table (community_id bigint, community_name text, group_id bigint, group_name text, group_active boolean)
language plpgsql stable security definer set search_path = '' as $fn$
#variable_conflict use_column
begin
  perform registry.require('view');
  return query
    select c.id, c.name, s.id, s.name, s.active
      from public.communities c
      left join public.small_groups s on s.community_id = c.id
     order by c.sort_order, c.id, s.sort_order, s.id;
end
$fn$;

revoke all on function public.registry_groups() from public, anon;
grant execute on function public.registry_groups() to authenticated;

notify pgrst, 'reload schema';

-- 교적 ③ 디모데 가져오기 되돌리기. 옛 메모(legacy_memos)와 옛 ID(legacy_links)도 함께 지워진다.
-- 반영해서 채운 교적 값(세대·신급·등록일 등)은 그대로 남는다.
drop function if exists public.registry_legacy_memos(uuid);
drop function if exists public.registry_import_close();
drop function if exists public.registry_import_apply(integer, boolean);
drop function if exists public.registry_import_accept(bigint[]);
drop function if exists public.registry_import_decide(bigint, text, uuid);
drop function if exists public.registry_import_list(text, integer, integer);
drop function if exists public.registry_import_summary();
drop function if exists public.registry_import_load(jsonb);
drop function if exists registry.import_stats(jsonb);
drop function if exists registry.import_apply_row(registry.import_rows);
drop function if exists registry.import_place_household(registry.import_rows, uuid);
drop function if exists registry.import_rematch();
drop function if exists registry.relation_rank(text);
drop function if exists registry.dimode_marital(text);
drop function if exists registry.dimode_faith(text);
drop function if exists registry.dimode_office(text, text);
drop function if exists registry.dimode_relation(text);
drop function if exists registry.digits(text);
drop function if exists registry.name_key(text);
drop function if exists registry.strip_mark(text);
drop table if exists registry.legacy_memos;
drop table if exists registry.legacy_links;
drop table if exists registry.import_households;
drop table if exists registry.import_rows;
notify pgrst, 'reload schema';

-- 교회 문서 (교회운영세칙 등)
--
-- 본문(body)은 구조화된 JSON 이다: {preamble[], parts[{no,title,chapters[{no,title,articles[{no,title,paras[]}]}]}], closing, appendices[]}
-- audience = 'member' 인 문서는 교인 인증된 사람(custom_users.member)과 관리자만 읽는다.
-- 저장소가 공개라 본문은 이 파일에 넣지 않는다. 본문은 관리자가 DB에 따로 넣는다.

create table public.church_documents (
  slug         text primary key check (slug ~ '^[a-z0-9-]+$'),
  title        text not null,
  revision     text,                        -- 예: '3차 개정'
  effective_on date,                        -- 시행일
  source       text,                        -- 예: '2026 교회요람'
  body         jsonb not null check (jsonb_typeof(body) = 'object'),
  audience     text not null default 'member' check (audience in ('public', 'member')),
  updated_at   timestamptz not null default now(),
  updated_by   uuid default public.app_current_user_id()
);

alter table public.church_documents enable row level security;

create policy church_documents_read on public.church_documents
  for select to anon, authenticated
  using (audience = 'public' or public.app_is_member() or public.app_is_admin());

create policy church_documents_admin_insert on public.church_documents
  for insert to authenticated with check (public.app_is_admin());
create policy church_documents_admin_update on public.church_documents
  for update to authenticated using (public.app_is_admin()) with check (public.app_is_admin());
create policy church_documents_admin_delete on public.church_documents
  for delete to authenticated using (public.app_is_admin());

grant select on public.church_documents to anon, authenticated;
grant insert, update, delete on public.church_documents to authenticated;

create trigger touch_updated_at before update on public.church_documents
  for each row execute function public.touch_updated_at();
create trigger audit after insert or update or delete on public.church_documents
  for each row execute function public.audit_row();

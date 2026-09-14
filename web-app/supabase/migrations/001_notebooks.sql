-- Run this complete file once in the Supabase SQL Editor.
-- Only the Next.js backend accesses these tables, after checking the signed-in
-- account and ownership. Browser/anonymous Supabase clients have no table access.
begin;

create table if not exists public.mynotes_notebooks (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  document jsonb not null,
  revision bigint not null default 1 check (revision > 0),
  mutation_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  title text generated always as (document->>'title') stored,
  template text generated always as (document->>'template') stored,
  color text generated always as (document->>'color') stored,
  page_count integer generated always as (jsonb_array_length(document->'pages')) stored,
  search_text text generated always as (coalesce(document->>'title', '') || ' ' || coalesce(jsonb_path_query_array(document, '$.pages[*].text')::text, '')) stored,
  constraint mynotes_document_object check (jsonb_typeof(document) = 'object')
);

create index if not exists mynotes_notebooks_owner_updated
  on public.mynotes_notebooks (owner_id, updated_at desc);

alter table public.mynotes_notebooks enable row level security;
revoke all on public.mynotes_notebooks from anon, authenticated;
grant select, insert, update, delete on public.mynotes_notebooks to service_role;

notify pgrst, 'reload schema';
commit;

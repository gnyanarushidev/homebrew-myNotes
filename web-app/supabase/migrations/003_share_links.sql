-- Read-only share links. Run after 002 in the Supabase SQL Editor.
-- A link is an unguessable token owned by one notebook; deleting the row revokes it.
-- Only the Next.js backend (service role) can read or write this table.
begin;
create table if not exists public.cloud_shares (
  token text primary key check (token ~ '^[A-Za-z0-9_-]{43}$'),
  owner_id uuid not null references auth.users(id) on delete cascade,
  notebook_id uuid not null,
  created_at timestamptz not null default now(),
  unique (owner_id, notebook_id),
  foreign key (owner_id, notebook_id) references public.cloud_notebooks(owner_id, id) on delete cascade
);
alter table cloud_shares enable row level security;
revoke all on cloud_shares from anon, authenticated;
grant all on cloud_shares to service_role;
commit;

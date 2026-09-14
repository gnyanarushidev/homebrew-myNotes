-- Metadata-only cloud store. Run after 001; legacy documents remain available
-- for explicit migration. Only the authorized backend can call these functions.
begin;
create table if not exists public.cloud_accounts (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  sequence bigint not null default 0
);
create table if not exists public.cloud_notebooks (
  owner_id uuid not null references auth.users(id) on delete cascade,
  id uuid not null,
  manifest jsonb not null,
  previous_manifest jsonb,
  revision bigint not null check (revision > 0),
  change_seq bigint not null,
  mutation_id uuid not null,
  deleted boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (owner_id, id),
  constraint cloud_metadata_only check (
    jsonb_typeof(manifest->'pages') = 'array'
    and not jsonb_path_exists(manifest, '$.pages[*].strokes')
    and not jsonb_path_exists(manifest, '$.pages[*].text')
    and not jsonb_path_exists(manifest, '$.pages[*].image.data')
  )
);
create index if not exists cloud_notebooks_changes on public.cloud_notebooks(owner_id, change_seq);
create table if not exists public.cloud_objects (
  key text primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  sha256 text not null,
  bytes bigint not null,
  stored_bytes bigint not null,
  kind text not null,
  version_id text,
  state text not null default 'ready' check (state in ('uploading', 'ready', 'deleting')),
  created_at timestamptz not null default now()
);
create index if not exists cloud_objects_owner on public.cloud_objects(owner_id, created_at);
create table if not exists public.cloud_references (
  owner_id uuid not null,
  notebook_id uuid not null,
  key text not null references public.cloud_objects(key),
  primary key(owner_id, notebook_id, key),
  foreign key(owner_id, notebook_id) references public.cloud_notebooks(owner_id, id) on delete cascade
);
create index if not exists cloud_references_key on public.cloud_references(key);
create table if not exists public.cloud_operations (
  owner_id uuid not null references auth.users(id) on delete cascade,
  operation_id uuid not null,
  request_hash text not null,
  receipt jsonb not null,
  created_at timestamptz not null default now(),
  primary key(owner_id, operation_id)
);

create or replace function public.cloud_manifest_keys(m jsonb) returns setof text
language sql immutable set search_path = public as $$
  select p->'content'->>'key' from jsonb_array_elements(coalesce(m->'pages', '[]')) p
  union select p->'image'->>'key' from jsonb_array_elements(coalesce(m->'pages', '[]')) p where p ? 'image'
$$;

create or replace function public.cloud_commit(
  p_owner uuid, p_id uuid, p_operation uuid, p_hash text, p_base bigint,
  p_manifest jsonb, p_deleted boolean, p_keep_both boolean,
  p_conflict_id uuid, p_conflict_manifest jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  existing cloud_notebooks%rowtype;
  prior cloud_operations%rowtype;
  destination uuid := p_id;
  incoming jsonb := p_manifest;
  previous jsonb;
  next_revision bigint := 1;
  next_sequence bigint;
  is_conflict boolean := false;
  object_key text;
  result jsonb;
begin
  insert into cloud_accounts(owner_id) values(p_owner) on conflict do nothing;
  perform 1 from cloud_accounts where owner_id = p_owner for update;
  select * into prior from cloud_operations where owner_id = p_owner and operation_id = p_operation;
  if found then
    if prior.request_hash <> p_hash then raise exception 'OPERATION_REUSED'; end if;
    return prior.receipt || '{"duplicate":true}'::jsonb;
  end if;
  select * into existing from cloud_notebooks where owner_id = p_owner and id = p_id;
  if (found and (existing.revision <> p_base or (existing.deleted and not p_deleted))) or (not found and p_base <> 0) then
    if not p_keep_both or p_deleted then raise exception 'REVISION_CONFLICT'; end if;
    destination := p_conflict_id; incoming := p_conflict_manifest; is_conflict := true;
    if exists(select 1 from cloud_notebooks where owner_id = p_owner and id = destination) then raise exception 'CONFLICT_ID_USED'; end if;
  elsif existing.id is not null then
    next_revision := existing.revision + 1;
    previous := case when p_deleted then null else existing.manifest end;
    if previous is not null then
      -- Metadata-only saves must not discard a page's prior drawing version.
      -- Keep one previous content object and one previous image per live page.
      previous := jsonb_set(previous, '{pages}', coalesce((
        select jsonb_agg(
          (old_page - 'content' - 'image')
          || jsonb_build_object('content', case
            when old_page->'content'->>'sha256' = new_page->'content'->>'sha256'
              then coalesce(prior_page->'content', old_page->'content')
            else old_page->'content' end)
          || case when image_value is null then '{}'::jsonb else jsonb_build_object('image', image_value) end
        ) from (
          select old_page, new_page, prior_page, case
            when (old_page->'image'->>'sha256') is not distinct from (new_page->'image'->>'sha256')
              then coalesce(prior_page->'image', old_page->'image')
            else old_page->'image' end as image_value
          from jsonb_array_elements(existing.manifest->'pages') old_page
          left join lateral (select value as new_page from jsonb_array_elements(incoming->'pages') where value->>'id' = old_page->>'id') n on true
          left join lateral (select value as prior_page from jsonb_array_elements(coalesce(existing.previous_manifest->'pages', '[]')) where value->>'id' = old_page->>'id') p on true
        ) history
      ), '[]'::jsonb));
    end if;
  end if;
  if p_deleted then incoming := jsonb_set(incoming, '{pages}', '[]'); end if;
  for object_key in select cloud_manifest_keys(incoming) loop
    if not exists(select 1 from cloud_objects where key = object_key and owner_id = p_owner and state = 'ready') then raise exception 'OBJECT_UNAVAILABLE'; end if;
  end loop;
  update cloud_accounts set sequence = sequence + 1 where owner_id = p_owner returning sequence into next_sequence;
  insert into cloud_notebooks(owner_id, id, manifest, previous_manifest, revision, change_seq, mutation_id, deleted)
    values(p_owner, destination, incoming, previous, next_revision, next_sequence, p_operation, p_deleted)
    on conflict(owner_id, id) do update set manifest = excluded.manifest, previous_manifest = excluded.previous_manifest,
      revision = excluded.revision, change_seq = excluded.change_seq, mutation_id = excluded.mutation_id,
      deleted = excluded.deleted, updated_at = now();
  delete from cloud_references where owner_id = p_owner and notebook_id = destination;
  insert into cloud_references(owner_id, notebook_id, key)
    select p_owner, destination, k from (select cloud_manifest_keys(incoming) k union select cloud_manifest_keys(previous) k) keys;
  result := jsonb_build_object('id', destination, 'revision', next_revision, 'sequence', next_sequence, 'conflict', is_conflict, 'deleted', p_deleted);
  insert into cloud_operations(owner_id, operation_id, request_hash, receipt) values(p_owner, p_operation, p_hash, result);
  return result;
end $$;

create or replace function public.cloud_cleanup_candidates(p_owner uuid) returns setof cloud_objects
language plpgsql security definer set search_path = public as $$
begin
  insert into cloud_accounts(owner_id) values(p_owner) on conflict do nothing;
  perform 1 from cloud_accounts where owner_id = p_owner for update;
  return query update cloud_objects set state = 'deleting' where key in (
    select o.key from cloud_objects o where o.owner_id = p_owner
      and (o.state = 'deleting' or o.created_at < now() - interval '24 hours')
      and not exists(select 1 from cloud_references r where r.key = o.key)
      order by o.created_at limit 100
  ) returning *;
end $$;

alter table cloud_accounts enable row level security;
create or replace function public.cloud_usage(p_owner uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'storedBytes', (select coalesce(sum(stored_bytes), 0) from cloud_objects where owner_id = p_owner),
    'referencedBytes', (select coalesce(sum(o.stored_bytes), 0) from cloud_objects o where o.owner_id = p_owner and exists(select 1 from cloud_references r where r.key = o.key)),
    'notebooks', (select count(*) from cloud_notebooks where owner_id = p_owner and not deleted)
  )
$$;
alter table cloud_notebooks enable row level security;
alter table cloud_objects enable row level security;
alter table cloud_references enable row level security;
alter table cloud_operations enable row level security;
revoke all on cloud_accounts, cloud_notebooks, cloud_objects, cloud_references, cloud_operations from anon, authenticated;
grant all on cloud_accounts, cloud_notebooks, cloud_objects, cloud_references, cloud_operations to service_role;
revoke all on function cloud_manifest_keys(jsonb), cloud_commit(uuid,uuid,uuid,text,bigint,jsonb,boolean,boolean,uuid,jsonb), cloud_cleanup_candidates(uuid), cloud_usage(uuid) from public, anon, authenticated;
grant execute on function cloud_manifest_keys(jsonb), cloud_commit(uuid,uuid,uuid,text,bigint,jsonb,boolean,boolean,uuid,jsonb), cloud_cleanup_candidates(uuid), cloud_usage(uuid) to service_role;
notify pgrst, 'reload schema';
commit;

-- =============================================================================
-- MISSION CONTROL — Supabase STORAGE schema  (Prompt 7 · user avatar)
-- =============================================================================
-- Creates a public "avatars" bucket and the policies the dashboard needs to
-- upload / replace / read a profile picture using the browser-side ANON key.
--
-- Paste this whole file into the Supabase SQL Editor (or it has already been
-- applied via the Supabase MCP). Safe to re-run — every statement is guarded.
--
-- Security note: this follows the same "public-by-URL" tradeoff as the rest of
-- Mission Control (see memory: mission-control-architecture). The anon key can
-- read/write objects in the avatars bucket. Fine for a single-user private
-- dashboard; revisit with Supabase Auth if it ever needs to be multi-tenant.
-- =============================================================================

-- 1) The bucket (public = served over a plain public URL, no signed token).
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- 2) Policies on storage.objects, scoped to the avatars bucket only.
--    Dropped-then-created so the file is idempotent.

drop policy if exists "avatars public read"  on storage.objects;
drop policy if exists "avatars anon insert"  on storage.objects;
drop policy if exists "avatars anon update"  on storage.objects;
drop policy if exists "avatars anon delete"  on storage.objects;

-- Public read: anyone (anon or authenticated) can fetch an avatar object.
create policy "avatars public read"
  on storage.objects for select
  using ( bucket_id = 'avatars' );

-- Anon insert: the browser can upload a new avatar.
create policy "avatars anon insert"
  on storage.objects for insert to anon
  with check ( bucket_id = 'avatars' );

-- Anon update: the browser can overwrite an existing avatar object.
create policy "avatars anon update"
  on storage.objects for update to anon
  using ( bucket_id = 'avatars' )
  with check ( bucket_id = 'avatars' );

-- Anon delete: when the user changes their avatar we remove the old object.
create policy "avatars anon delete"
  on storage.objects for delete to anon
  using ( bucket_id = 'avatars' );

-- =============================================================================
-- DONE.  Quick check:
--   select id, public from storage.buckets where id = 'avatars';   -- public = t
-- =============================================================================

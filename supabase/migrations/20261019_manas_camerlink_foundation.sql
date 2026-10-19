-- MANAS / CamerLink clean additive foundation
-- Safe to re-run. Does not drop existing tables or user data.
create extension if not exists pgcrypto;

alter table public.profiles
  add column if not exists username text,
  add column if not exists cover_url text,
  add column if not exists website text,
  add column if not exists is_verified boolean not null default false,
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists profiles_username_unique
  on public.profiles (lower(username)) where username is not null;

alter table public.publications
  add column if not exists media_type text not null default 'photo',
  add column if not exists location_name text,
  add column if not exists view_count bigint not null default 0,
  add column if not exists is_archived boolean not null default false;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'publications_media_type_check') then
    alter table public.publications add constraint publications_media_type_check
      check (media_type in ('photo','video','reel','text'));
  end if;
end $$;

create table if not exists public.publication_comments (
  id uuid primary key default gen_random_uuid(),
  publication_id bigint not null references public.publications(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  content text not null check (char_length(btrim(content)) between 1 and 1000),
  status text not null default 'approved' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);

create table if not exists public.profile_views (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references auth.users(id) on delete cascade,
  viewer_id uuid references auth.users(id) on delete set null,
  viewed_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  kind text not null check (kind in ('follow','like','comment','message','system')),
  publication_id bigint references public.publications(id) on delete cascade,
  comment_id uuid references public.publication_comments(id) on delete cascade,
  message text not null check (char_length(message) <= 500),
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists publications_user_created_idx on public.publications(user_id, created_at desc);
create index if not exists publications_media_created_idx on public.publications(media_type, created_at desc);
create index if not exists stories_expiry_idx on public.stories(expires_at);
create index if not exists messages_conversation_idx on public.messages(sender_id, receiver_id, created_at desc);
create index if not exists notifications_recipient_created_idx on public.notifications(recipient_id, created_at desc);
create index if not exists publication_comments_pub_created_idx on public.publication_comments(publication_id, created_at desc);
create index if not exists profile_views_profile_date_idx on public.profile_views(profile_id, viewed_at desc);

alter table public.publication_comments enable row level security;
alter table public.profile_views enable row level security;
alter table public.notifications enable row level security;

drop policy if exists "comments readable approved" on public.publication_comments;
create policy "comments readable approved" on public.publication_comments for select
  using (status = 'approved' or user_id = auth.uid());
drop policy if exists "users create own comments" on public.publication_comments;
create policy "users create own comments" on public.publication_comments for insert
  to authenticated with check (user_id = auth.uid());
drop policy if exists "users delete own comments" on public.publication_comments;
create policy "users delete own comments" on public.publication_comments for delete
  to authenticated using (user_id = auth.uid());

drop policy if exists "profile owner can read views" on public.profile_views;
create policy "profile owner can read views" on public.profile_views for select
  to authenticated using (profile_id = auth.uid());
drop policy if exists "signed in can record profile view" on public.profile_views;
create policy "signed in can record profile view" on public.profile_views for insert
  to authenticated with check (viewer_id = auth.uid() and profile_id <> auth.uid());

drop policy if exists "recipient reads notifications" on public.notifications;
create policy "recipient reads notifications" on public.notifications for select
  to authenticated using (recipient_id = auth.uid());
drop policy if exists "recipient marks notifications read" on public.notifications;
create policy "recipient marks notifications read" on public.notifications for update
  to authenticated using (recipient_id = auth.uid()) with check (recipient_id = auth.uid());

grant select, insert, delete on public.publication_comments to authenticated;
grant select, insert on public.profile_views to authenticated;
grant select, update on public.notifications to authenticated;

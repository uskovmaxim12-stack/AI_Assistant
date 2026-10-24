-- Секретарь Бо: схема для Supabase. Вставьте целиком в SQL Editor и нажмите Run.
create table prefs(user_id uuid primary key references auth.users on delete cascade default auth.uid(), mode text default 'biz', robot_name text default 'Бо', robot_hue text default '#1F4FD8');
create table items(id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users on delete cascade, k text not null, t text not null, h text default '', w text default '', d boolean default false, created_at timestamptz default now());
create table notes(id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users on delete cascade, t text not null, created_at timestamptz default now());
create table guardianship(child_id uuid primary key references auth.users on delete cascade, child_name text default '', code text unique default upper(substr(md5(random()::text),1,8)), parent_id uuid references auth.users, approved boolean default false, ai_enabled boolean default true);
alter table prefs enable row level security; alter table items enable row level security; alter table notes enable row level security; alter table guardianship enable row level security;
create policy own_prefs on prefs for all using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy own_notes on notes for all using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy own_items on items for all using (user_id=auth.uid()) with check (user_id=auth.uid() and not exists(select 1 from guardianship g where g.child_id=auth.uid() and not g.approved));
create policy parent_items on items for select using (exists(select 1 from guardianship g where g.child_id=items.user_id and g.parent_id=auth.uid() and g.approved));
create policy gd_read on guardianship for select using (child_id=auth.uid() or parent_id=auth.uid());
create policy gd_parent_update on guardianship for update using (parent_id=auth.uid());
-- Ребёнок младше 16 лет получает запись опеки автоматически при регистрации (порог зависит от страны, при необходимости измените 16).
create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if (extract(year from now())::int - coalesce((new.raw_user_meta_data->>'birth_year')::int,1990)) < 16 then
    insert into guardianship(child_id,child_name) values(new.id, coalesce(new.raw_user_meta_data->>'name',''));
  end if;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();
-- Родитель вводит код ребёнка и подтверждает опеку.
create function claim_child(_code text) returns boolean language plpgsql security definer set search_path=public as $$
begin
  update guardianship set parent_id=auth.uid(), approved=true where code=upper(trim(_code)) and parent_id is null and child_id<>auth.uid();
  return found;
end $$;

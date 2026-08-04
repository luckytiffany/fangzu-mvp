-- 房租水电管理 MVP · 授权（协作抄表）建表脚本
-- 用法：登录 Supabase 控制台 → SQL Editor → 粘贴本文件全部内容 → Run
-- 前置：需先执行过 supabase_schema.sql（已建 properties/rooms/readings 表）
-- 本脚本幂等，可反复执行。

-- 1) 授权表：房东授权他人临时代抄某楼栋
create table if not exists authorizations(
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  property_id text not null,
  authorized_phone text not null,
  code text not null unique,
  start_at timestamptz not null,
  end_at timestamptz not null,
  created_at timestamptz default now()
);
create index if not exists idx_auth_phone on authorizations(authorized_phone);
create index if not exists idx_auth_owner on authorizations(owner_id);
alter table authorizations enable row level security;

-- 房东可管理自己发出的授权
drop policy if exists "own_authorizations" on authorizations;
create policy "own_authorizations" on authorizations
  for all using (auth.uid()=owner_id) with check (auth.uid()=owner_id);

-- 受托人仅能看到“授权给我、且仍在有效期内”的授权记录
drop policy if exists "auth_see_own_auths" on authorizations;
create policy "auth_see_own_auths" on authorizations
  for select using (
    authorized_phone = split_part(auth.email(),'@',1)
    and start_at <= now() and end_at >= now()
  );

-- 2) 受托人对被授权房源/房间：只读
drop policy if exists "auth_select_properties" on properties;
create policy "auth_select_properties" on properties
  for select using (
    exists (select 1 from authorizations a
      where a.property_id = properties.id
        and a.authorized_phone = split_part(auth.email(),'@',1)
        and a.start_at <= now() and a.end_at >= now())
  );

drop policy if exists "auth_select_rooms" on rooms;
create policy "auth_select_rooms" on rooms
  for select using (
    exists (select 1 from authorizations a
      where a.property_id = rooms.property_id
        and a.authorized_phone = split_part(auth.email(),'@',1)
        and a.start_at <= now() and a.end_at >= now())
  );

-- 受托人对被授权房源的读数：可读 + 可写入（写入归属房东 user_id）
drop policy if exists "auth_select_readings" on readings;
create policy "auth_select_readings" on readings
  for select using (
    exists (select 1 from rooms r join authorizations a on a.property_id = r.property_id
      where r.id = readings.room_id and a.owner_id = readings.user_id
        and a.authorized_phone = split_part(auth.email(),'@',1)
        and a.start_at <= now() and a.end_at >= now())
  );

drop policy if exists "auth_write_readings" on readings;
create policy "auth_write_readings" on readings
  for insert with check (
    exists (select 1 from rooms r join authorizations a on a.property_id = r.property_id
      where r.id = readings.room_id and a.owner_id = readings.user_id
        and a.authorized_phone = split_part(auth.email(),'@',1)
        and a.start_at <= now() and a.end_at >= now())
  );

drop policy if exists "auth_update_readings" on readings;
create policy "auth_update_readings" on readings
  for update using (
    exists (select 1 from rooms r join authorizations a on a.property_id = r.property_id
      where r.id = readings.room_id and a.owner_id = readings.user_id
        and a.authorized_phone = split_part(auth.email(),'@',1)
        and a.start_at <= now() and a.end_at >= now())
  ) with check (
    exists (select 1 from rooms r join authorizations a on a.property_id = r.property_id
      where r.id = readings.room_id and a.owner_id = readings.user_id
        and a.authorized_phone = split_part(auth.email(),'@',1)
        and a.start_at <= now() and a.end_at >= now())
  );

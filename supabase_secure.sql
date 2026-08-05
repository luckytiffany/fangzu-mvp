-- =====================================================================
-- 房租水电管理 MVP · 数据安全 / 多用户隔离 · 总脚本（一次性跑完）
-- =====================================================================
-- 用途：保证 10~20 个用户共用同一个 Supabase 数据库时，
--       每个人的房源/房间/读数/设置【互相看不到、也不会串】。
-- 用法：
--   1) 打开 Supabase 后台 → 左侧「SQL Editor」→「New query」
--   2) 把下面的内容【全部】粘贴进去
--   3) 点「Run」执行一次即可（本脚本幂等，可反复执行）
-- 说明：
--   - 本脚本开启「行级安全 RLS」并写入隔离策略，是数据不串、不泄露的关键。
--   - 即使你以前跑过其中的部分脚本，再跑一次也安全（drop policy if exists）。
--   - 你网页前端用的 anon key 是公开的，但因为有下面的 RLS，别人拿它也只能
--     读写【自己账号】的数据，看不到别人的。请勿把 service_role key 放进网页。
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) 建表（若不存在）。所有业务表都带 user_id，并外键关联到 auth.users
-- ---------------------------------------------------------------------
create table if not exists properties(
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text,
  location text,
  lat numeric,
  lng numeric,
  updated_at timestamptz default now()
);

create table if not exists rooms(
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  property_id text,
  name text,
  tenant text,
  lease_start text,
  lease_end text,
  rent numeric,
  mgmt_fee numeric,
  water_price numeric,
  elec_price numeric,
  gas_price numeric,
  hot_price numeric,
  updated_at timestamptz default now()
);

create table if not exists readings(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  room_id text,
  month text,
  water_start numeric,
  water_end numeric,
  elec_start numeric,
  elec_end numeric,
  gas_start numeric,
  gas_end numeric,
  hot_start numeric,
  hot_end numeric,
  updated_at timestamptz default now(),
  unique(user_id, room_id, month)   -- 同一人同一房间同一月只有一条，防止重复串数据
);

create table if not exists settings(
  user_id uuid primary key references auth.users(id) on delete cascade,
  water numeric,
  elec numeric,
  gas numeric,
  hot numeric,
  mgmt numeric,
  updated_at timestamptz default now()
);

-- ---------------------------------------------------------------------
-- 2) 补列（若你之前没跑过 rooms_init / propdefaults，这里一并补齐）
-- ---------------------------------------------------------------------
alter table public.rooms add column if not exists init_water numeric;
alter table public.rooms add column if not exists init_elec  numeric;
alter table public.rooms add column if not exists init_gas   numeric;
alter table public.rooms add column if not exists init_hot   numeric;
alter table public.settings add column if not exists prop_defaults jsonb;

-- ---------------------------------------------------------------------
-- 3) 开启行级安全（RLS）—— 这是隔离的核心开关
-- ---------------------------------------------------------------------
alter table properties enable row level security;
alter table rooms      enable row level security;
alter table readings   enable row level security;
alter table settings   enable row level security;

-- ---------------------------------------------------------------------
-- 4) 本人隔离策略：每个用户只能看/改/删【自己 user_id】的数据
--    （drop if exists 保证可重复执行）
-- ---------------------------------------------------------------------
drop policy if exists "own_properties" on properties;
drop policy if exists "own_rooms"      on rooms;
drop policy if exists "own_readings"   on readings;
drop policy if exists "own_settings"   on settings;

create policy "own_properties" on properties for all
  using (auth.uid()=user_id) with check (auth.uid()=user_id);
create policy "own_rooms" on rooms for all
  using (auth.uid()=user_id) with check (auth.uid()=user_id);
create policy "own_readings" on readings for all
  using (auth.uid()=user_id) with check (auth.uid()=user_id);
create policy "own_settings" on settings for all
  using (auth.uid()=user_id) with check (auth.uid()=user_id);

-- ---------------------------------------------------------------------
-- 5) 授权（房东授权他人临时代抄某楼栋）—— 仅限被授权范围内可见/可写
-- ---------------------------------------------------------------------
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

-- 房东只能管理自己发出的授权
drop policy if exists "own_authorizations" on authorizations;
create policy "own_authorizations" on authorizations
  for all using (auth.uid()=owner_id) with check (auth.uid()=owner_id);

-- 受托人只能看到“授权给我、且仍在有效期内”的授权记录（手机号 = 登录邮箱前缀）
drop policy if exists "auth_see_own_auths" on authorizations;
create policy "auth_see_own_auths" on authorizations
  for select using (
    authorized_phone = split_part(auth.email(),'@',1)
    and start_at <= now() and end_at >= now()
  );

-- 受托人只读被授权楼栋的房源/房间
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

-- 受托人对被授权楼栋的读数：可读 + 可写（写入归属于房东 user_id）
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

-- ---------------------------------------------------------------------
-- 6) 完成提示
-- ---------------------------------------------------------------------
select 'RLS 隔离策略已就绪：多用户数据互相隔离，仅本人及被授权人可见。' as result;

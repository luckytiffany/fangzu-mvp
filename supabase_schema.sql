-- 房租水电管理 MVP · Supabase 建表脚本
-- 用法：登录 Supabase 控制台 → 打开 SQL Editor → 粘贴本文件全部内容 → Run
-- 注意：以下表依赖 Supabase 内置的 auth.users（注册账号时自动生成）。

-- 1) 房源（楼栋）
create table if not exists properties(
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text,
  location text,
  lat numeric,
  lng numeric,
  updated_at timestamptz default now()
);

-- 2) 房间号
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

-- 3) 每月抄表读数（同一房间同一月份唯一）
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
  unique(user_id, room_id, month)
);

-- 4) 默认费用（每用户一行）
create table if not exists settings(
  user_id uuid primary key references auth.users(id) on delete cascade,
  water numeric,
  elec numeric,
  gas numeric,
  hot numeric,
  mgmt numeric,
  updated_at timestamptz default now()
);

-- 5) 开启行级安全（RLS），保证数据仅本人可见/可改
alter table properties enable row level security;
alter table rooms enable row level security;
alter table readings enable row level security;
alter table settings enable row level security;

-- 6) RLS 策略：只允许操作自己 user_id 的行
-- 先删除可能已存在的同名策略，确保脚本可重复执行
drop policy if exists "own_properties" on properties;
drop policy if exists "own_rooms" on rooms;
drop policy if exists "own_readings" on readings;
drop policy if exists "own_settings" on settings;

create policy "own_properties" on properties for all using (auth.uid()=user_id) with check (auth.uid()=user_id);
create policy "own_rooms" on rooms for all using (auth.uid()=user_id) with check (auth.uid()=user_id);
create policy "own_readings" on readings for all using (auth.uid()=user_id) with check (auth.uid()=user_id);
create policy "own_settings" on settings for all using (auth.uid()=user_id) with check (auth.uid()=user_id);

-- 为 settings 表增加 prop_defaults 列，用于存储「按房源分别设置的水电费用」
-- 幂等：列已存在则自动跳过，可重复执行
alter table public.settings add column if not exists prop_defaults jsonb;

-- 说明：
-- 旧版 settings 只有全局 water/elec/gas/hot/mgmt 五列（标量），代表整租户统一的默认单价。
-- 新版本改为「每个房源各自一套默认单价」，存进 prop_defaults（jsonb 对象），结构示例：
--   {
--     "房源ID_1": {"water":3.5,"elec":0.65,"gas":3.2,"hot":8,"mgmt":100},
--     "房源ID_2": {"water":3.5,"elec":0.65,"gas":3.2,"hot":8,"mgmt":150}
--   }
--
-- 兼容性：
-- 不跑此 SQL 也能正常用 App（本地数据、房间/读数/房源的云同步都不受影响），
-- 仅「按房源设置的水电费用」不会同步到云端。跑完本脚本后，设置过的「水电费用」
-- 会随每次保存自动上传，换手机/换电脑登录同一账号即可恢复。
-- 前端已做容错：若此列暂不存在，设置水费仅保存在本机，不会报错。

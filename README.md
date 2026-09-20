# 校友地图 · Discourse 原生插件

首版试迁移，2026-09-20。后端使用论坛 Rails/PostgreSQL/Sidekiq，前端使用原生 Glimmer 页面。入口 `/alumni-map`，不需要运行原来的 Next.js 服务。

## 安装与配置

将本目录作为 `plugins/discourse-alumni-map` 放入 **测试论坛**，按论坛标准流程安装插件、运行 `db:migrate` 并重新构建资源。验证目标为本机 Discourse `2026.9.0-latest` / `5b59681a8`；未声明兼容其他版本。正式部署应为插件建立独立 Git 仓库并固定经过验证的提交。

1. 插件默认关闭，设置 `alumni_map_enabled` 启用。
2. 设置 `alumni_map_allowed_groups` 选择可访问的校友组；为空时仅管理员可用。
3. `alumni_map_admin_groups` 可委派本应用管理权限，论坛管理员始终可管理；管理入口在插件页面的“管理”标签。
4. 确认论坛 Sidekiq 正常处理计划任务，通知投递每分钟补偿执行。

数据库表前缀为 `river_alumni_map_`，卸载代码不会删除业务表。停用会同时阻止业务 API 与计划任务。

## 数据迁移和验收

`script/export_legacy.mjs` 只读导出旧库；`script/import_legacy.rb` 默认事务回滚演练，正式导入需要插件关闭、业务表为空和已核对的 SHA256。不能直接把旧 Prisma migration 放入论坛运行。

详细功能、迁移命令、行为差异与尚未实现项见 [实施说明](docs/implementation.md)。隔离测试入口见 [集成验收](../discourse-community-test/README.md)。**真实数据已导入隔离的私有测试站，未切换线上入口。** 161 张名片逐条核对通过，其中 123 张公开、38 张未公开。访问入口、验收和剩余差异见 [私有试迁移记录](docs/private-migration-2026-09-20.md)。

真实快照启用 `alumni_map_read_only`，禁止编辑与管理；合成数据演示站允许测试名片修改和公开设置。高德地图需配置 `alumni_map_amap_key` 与 `alumni_map_amap_security_code`；城市自动查询另需服务端 Key。已接入论坛用户删除、匿名化、合并处理，并提供本人的名片数据下载。

最新的旧新版对照、修补结果、测试证据和正式切换步骤见 [上线前复核](docs/release-review-2026-09-20.md)。

## 共用侧栏

插件在“类别”上方提供原生可折叠的“校园生活”分组，使用 `alumni_map_sidebar_section_title` 修改名称。只显示已启用且当前用户有访问权限的原生应用入口；其他应用未安装时不会出现占位链接。桌面和手机共用同样的逻辑，展开状态由论坛记忆。

其他 Riverside 原生插件迁入时，应停止重复注册各自的侧栏分组。当前配套源代码已增加该判断；这不代表那些应用已经切换到生产。

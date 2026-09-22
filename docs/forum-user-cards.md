# 论坛身份展示

公开地图只为勾选「展示论坛用户名」的名片返回论坛身份；隐藏身份的名片不返回用户名、头像模板或论坛用户编号。管理员页面仍受原有权限限制。

使用 Discourse 原生 `DUserLink`、`DUserAvatar` / `dAvatar` 和 `data-user-card`，遵循论坛用户资料可见性设置。只序列化已授权身份的 `id`、`username`、`avatar_template`，不带邮箱等私有字段。无需数据迁移。

2026-09-22 隔离验证：6 项后端身份/匿名边界测试、103 个断言通过；真实 Chromium 在 1440px 与 390px 验证原生名片弹出、页面不跳转、匿名与历史署名无账号链接、排行榜交易详情仍可打开。测试工具位于服务器 `discourse-community-test/forum_identity_test.rb` 和 `forum_identity_browser.cjs`，只使用隔离库及测试账号。

# kernel

本目录**不存放内核源码**，只放配置片段与说明。内核由 GitHub Actions 现场拉取并编译，避免仓库里出现几百 MB 的第三方代码。

| 文件 | 说明 |
|---|---|
| `defconfig.susfs` | 需要追加到 `dipper_user_defconfig` 的配置片段 |
| `../.github/workflows/build-kernel.yml` | 完整构建流水线（补丁全部内联） |

源码基线：小米开源内核 dipper 分支 → 集成 BakaSU `v4.2.0-rc3` → 打 SUSFS 4.9 补丁。

构建与版本串伪装的细节见 [docs/01-kernel-build.md](../docs/01-kernel-build.md)。

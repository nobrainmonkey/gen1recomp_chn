# Gen1Recomp 红／蓝／皮卡丘 简体中文

面向中国大陆简体中文的非官方 Gen1Recomp 翻译模组，支持 Pokémon
Red、Blue 和 Yellow（皮卡丘版）。

## 下载与安装

1. 打开 [最新 Release](https://github.com/nobrainmonkey/gen1recomp_chn/releases/latest)，
   下载附件 `zh_cn-版本号.zip`。不要解压，也不要用 GitHub 自动生成的
   `Source code.zip` 安装。
2. 先启动 Gen1Recomp 并完成程序提供的更新，确认有效引擎版本为 0.1.56 或更高。
   如果仍显示 0.1.50，请先更新，否则模组会拒绝加载。
3. 导入你自己合法持有的美版 Red、Blue 或 Yellow ROM。
4. 进入 `MODS` → `Import mod .zip`，选择第 1 步下载的 ZIP。
5. 启用 `ZH-CN / Simplified Chinese (Mainland)`，然后进入对应游戏。

如果曾在 0.1.50 下导入 Yellow，请升级到 0.1.56+ 后重新导入该 ROM；
0.1.50 生成的 Yellow 缓存缺少新版运行所需的资源。

本项目不提供 ROM。如果曾安装 0.1.0，请确认 MODS 页显示 0.3.0 或更高
版本；旧版会让大木博士开场保持英文，并可能在开场流程崩溃。

## 支持范围

- Gen1Recomp：`>=0.1.56 <1.0.0`。
- 游戏：美版 Pokémon Red、Blue、Yellow；三者使用自己导入的 ROM 数据。
- 剧情、NPC、图鉴、系统、菜单与战斗文本。Red／Blue 与 Yellow 使用
  版本对应的台词覆盖，不会把皮卡丘版专属台词套到红／蓝版。
- 151 种宝可梦名称按中国大陆官方译名表逐项核对；招式、道具、
  训练家类别与关都地名尽可能使用现行官方简体中文术语。
- 不提供繁体中文或自动繁简转换。

Gen1Recomp 小版本更新通常不需要改模组；模组不绑定某个 EXE 哈希，而是
使用版本范围和 Mod API。但引擎新增或改动文本后，仍需要重新执行三版本
覆盖、占位符和实机流程检查。

## Credits 与许可

- 上游运行环境：[bryanthaboi/gen1recomp](https://github.com/bryanthaboi/gen1recomp)，
  Copyright 2026 BOIS CLUB GAMES, LLC，MIT License。
- 默认字体：[QuanPixel／全小素](https://diaowinner.itch.io/galmuri-extended)，
  © Galmuri8、Chill Bitmap、diaowinner 及其他贡献者，SIL OFL 1.1。
- 备用等宽字体：[Fusion Pixel Font／缝合像素字体](https://github.com/TakWolf/fusion-pixel-font)，
  © 2022 TakWolf，SIL OFL 1.1。
- 151 种宝可梦名称依据项目提供者给出的中国大陆官方译名表校对；
  该本地参考表不随仓库或发行包发布。
- Red、Blue、Yellow 没有中国大陆官方简体中文完整剧本。本项目的剧情、
  NPC 和界面句子是非官方新译文，不是官方剧本复制品。

详细署名和法律说明见 [`mods/zh_cn/CREDITS.md`](mods/zh_cn/CREDITS.md)，字体和
上游许可文本见 [`mods/zh_cn/LICENSES/`](mods/zh_cn/LICENSES/)。字体依各自
OFL 单独授权，上游代码依其 MIT 许可授权。除这些第三方内容的现有许可外，
项目其余内容未另行授予项目级许可。

本项目与 Nintendo、Creatures、GAME FREAK、The Pokémon Company 及其关联公司
没有隶属或授权关系。仓库和发行包不包含 ROM、英文 ROM 剧本、提取工作表、
存档或缓存。`lang/strings.lua` 中的英文键是 Gen1Recomp 引擎匹配运行时文本
所必需的查找键，不是 ROM 剧本或提取工作表。

## 开发者文档

- 修改译文：[`mods/zh_cn/TRANSLATING.md`](mods/zh_cn/TRANSLATING.md)
- 术语与来源：[`mods/zh_cn/TERMINOLOGY.md`](mods/zh_cn/TERMINOLOGY.md)
- 生成和替换字体：[`mods/zh_cn/FONT_WORKFLOW.md`](mods/zh_cn/FONT_WORKFLOW.md)
- 版本记录：[`mods/zh_cn/CHANGELOG.md`](mods/zh_cn/CHANGELOG.md)

在仓库根目录重建默认字体：

```powershell
py -3 .\mods\zh_cn\tools\build_zh_cn_font.py
py -3 .\mods\zh_cn\tools\build_zh_cn_font.py --check
```

从自己合法持有的 ROM 生成的英文参考文本只能保留在本机已忽略目录，不能提交。
开发者验证和打包流程见模组内的 `README.md` 和 `FONT_WORKFLOW.md`。

发布前还应执行三版本本地文本检查、Gen1Recomp 严格 modkit 验证和实际
NEW GAME 流程。打包完成后，用仓库自带的白名单工具检查源码树与两种 ZIP：

```powershell
py -3 .\tools\audit_public_tree.py
py -3 .\tools\audit_release_zip.py mod .\dist\zh_cn-0.3.0.zip
py -3 .\tools\audit_release_zip.py source .\dist\gen1recomp_chn-source-0.3.0.zip
```

该门禁只允许明确列出的公开源码和资产，并会检查改名 ROM 的 Game Boy 头校验、
worksheet 路径、个人绝对路径、必需 Credits／许可文件及 ZIP 内容。

# Gen1Recomp 红／蓝／皮卡丘 简体中文

这是面向中国大陆简体中文的非官方翻译模组，支持 Gen1Recomp 的 Pokémon
Red、Blue 和 Yellow（皮卡丘版）。不提供繁体中文或自动繁简转换。

## 下载与安装

1. 在 [Releases](https://github.com/nobrainmonkey/gen1recomp_chn/releases/latest)
   下载附件 `zh_cn-版本号.zip`。不要解压，也不要下载 GitHub 自动生成的
   `Source code.zip` 来安装。
2. 先启动 Gen1Recomp 并完成程序提供的更新，确认有效引擎版本为 0.1.56 或更高。
   如果仍显示 0.1.50，请先更新，否则模组会拒绝加载。
3. 按程序提示导入你自己合法持有的 Red、Blue 或 Yellow
   美版 ROM。本项目不提供 ROM。
4. 打开 `MODS`，选择 `Import mod .zip`，导入刚下载的 ZIP。
5. 启用 `ZH-CN / Simplified Chinese (Mainland)`。开发测试版带有
   `EXPERIMENTAL` 标记，需要确认一次；随后进入对应游戏即可。

如果曾安装旧版，请确认 MODS 页面显示 0.3.1 或更高版本。0.3.1 修复
领取初始／赠送宝可梦时出现英文内部名称，以及属性、状态标签仍显示英文的问题。
更早的 0.1.0 会让大木博士开场保持英文，并可能在尼多力诺出现后崩溃。

## 支持范围

- Gen1Recomp：`>=0.1.56 <1.0.0`。
- 游戏：美版 Pokémon Red、Blue、Yellow；三者分别使用自己导入的 ROM
  数据和存档。
- 系统、菜单和战斗文本：607 / 607。
- 剧情、NPC、图鉴和流程文本使用 2710 条 Yellow／共享目录，再在
  Red／Blue 中加载 318 条独有或同 ID 异文覆盖。
- 对有效引擎 0.1.56 实际导入数据的覆盖为 Red 2585 / 2585、
  Blue 2585 / 2585、Yellow 2695 / 2695；当前源码数据为 2710 / 2710。
- 宝可梦名称：151 / 151，严格采用项目提供者核对的中国大陆官方名称表。
- 招式：165 / 165；训练家类别：47 / 47；异常状态：5 / 5；第一世代
  有效属性：15 / 15。
- 可见道具名称：150 / 150；原数据中两个未使用占位槽保持原样。
- 姓名预设增加“赤红／小智”和“青绿／小茂”。自定义姓名键盘目前仍使用
  拉丁字母。

模组缺少未来新增文本时会回退到英文，不会用空字符串替换。Gen1Recomp
更新后仍建议重新执行开发者检查，确认没有新文本遗漏。

## Dramatic Shape

已与 Dramatic Shape 1.4.0 联合测试。立体世界、移轴景深、体素网格、世界
曲面、水面反射、立体对战、背面图像和昼夜时间选项均有中文。它是可选
模组，不是本翻译的依赖。

## Credits 与许可

- 上游运行环境：[bryanthaboi/gen1recomp](https://github.com/bryanthaboi/gen1recomp)，
  其代码采用 MIT License。
- 默认字体：[QuanPixel／全小素](https://diaowinner.itch.io/galmuri-extended)，
  © Galmuri8、Chill Bitmap、diaowinner 等贡献者，SIL OFL 1.1。
- 备用等宽字体：[Fusion Pixel Font／缝合像素字体](https://github.com/TakWolf/fusion-pixel-font)，
  © 2022 TakWolf，SIL OFL 1.1。
- 151 种宝可梦名称按项目提供者给出的中国大陆官方名称表逐项核对；该参考
  表不随仓库或发行包发布。其他专名参考宝可梦中国大陆官网、52Poké 与
  PokeAPI 数据并交叉检查。
- Red、Blue、Yellow 没有中国大陆官方简体中文完整剧本。本项目的剧情、
  NPC 和引擎界面句子是重新翻译的非官方文本，不是官方剧本的复制品。

完整署名、翻译来源和法律说明见 `CREDITS.md`。字体许可全文位于
`LICENSES/`，上游 Gen1Recomp 的 MIT 许可副本也位于该目录。除这些
第三方内容的现有许可外，项目其余内容未另行授予项目级许可。

本项目与 Nintendo、Creatures、GAME FREAK、The Pokémon Company 及其关联
公司没有隶属或授权关系。仓库和发行包不包含 ROM、英文 ROM 剧本、提取
工作表、存档或缓存。

## 开发者：修改翻译

模组源码位于 `mods/zh_cn/`：

- `lang/dialogue.lua`：以游戏文本 ID 为键的 Yellow／共享剧情目录。
- `lang/dialogue_rb.lua`：Red／Blue 独有文本及同 ID 不同台词的版本覆盖。
- `lang/strings.lua`：引擎界面文本；英文键是运行时查找键，不能翻译或删除。
- `lang/*_names.lua`：宝可梦、招式、道具、训练家等名称。
- `tools/build_zh_cn_font.py`：根据当前译文生成中文字库。

ROM 提取出来的英文参考文本只应保存在本机的
`mods/zh_cn-worksheet/` 等受忽略目录中，绝不能提交或打包。翻译规则见
`TRANSLATING.md`，术语依据见 `TERMINOLOGY.md`。

## 开发者：字体、验证与打包

默认字体输入为 `mods/zh_cn/assets/font/quan.bdf`。在仓库根目录运行：

```powershell
py -3 .\mods\zh_cn\tools\build_zh_cn_font.py
py -3 .\mods\zh_cn\tools\build_zh_cn_font.py --check
```

完整换字体流程和可移植的打包命令见 `FONT_WORKFLOW.md`。发布前至少执行：

1. 三版本文本覆盖、占位符、控制符和每行 18 字符检查。
2. 默认字体重建及 `--check`。
3. `modkit.py validate --strict`。
4. `tests/` 下的动态名称、能力／状态标签和动态界面目录回归测试。
5. Red、Blue、Yellow 的 NEW GAME 开场及游戏内冒烟测试。
6. ZIP 内容白名单检查，确保不存在 ROM、英文工作表、存档、缓存或个人路径。

## Gen1Recomp 更新维护

`manifest.json` 没有绑定单个 EXE 哈希，而是接受 `>=0.1.56 <1.0.0`。
剧情、名称和初始宝可梦／徽章动态值使用 Mod API 2。0.1.56 仍有少量界面
绕过翻译目录，因此 `engine_internals` 兼容层只处理三个精确范围：选项页
`CANCEL` 页脚、升级能力框与动态能力参数、状态页／队伍页的状态缩写。
这些处理同时限定原始值、调用位置或模板参数，避免改写玩家昵称。更新引擎后
应刷新字符串目录，检查这些上游界面是否已改用正式翻译 API，并重跑三版本测试。

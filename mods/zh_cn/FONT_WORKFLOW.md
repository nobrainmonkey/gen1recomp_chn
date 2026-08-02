# 简体中文字体生成、替换与打包

字体生成器位于 `mods/zh_cn/tools/build_zh_cn_font.py`。它扫描当前模组的
`lang/*.lua`、`main.lua` 和 `manifest.json`，只把实际使用的非 ASCII 字符
写入以下生成文件：

- `lang/font.lua`
- `lang/charmap.lua`
- `lang/font/zh_cn_*.png`

脚本不会读取 ROM，也不会把英文参考工作表写入模组。

## 默认字体

不传 `--bdf` 时，脚本根据自身位置读取：

```text
mods/zh_cn/assets/font/quan.bdf
```

在本仓库根目录运行：

```powershell
py -3 .\mods\zh_cn\tools\build_zh_cn_font.py
py -3 .\mods\zh_cn\tools\build_zh_cn_font.py --check
```

若系统使用 `python` 命令，则把 `py -3` 换成 `python`。第一条命令生成或
更新字库；第二条确认输出能由当前译文和默认 BDF 完整、确定地重新生成。

## 临时使用 Fusion Pixel 等宽版

当前渲染器要求每个字形能原生放入固定 8×8 字格，不缩放、不裁切、不抗
锯齿。仓库附带的 Fusion Pixel 等宽版符合要求：

```powershell
$font = '.\mods\zh_cn\assets\font\fusion-pixel-8px-monospaced-zh_hans.bdf'
py -3 .\mods\zh_cn\tools\build_zh_cn_font.py --bdf $font
py -3 .\mods\zh_cn\tools\build_zh_cn_font.py --bdf $font --check
```

生成和检查必须传入同一个 `--bdf`。不带参数再次生成会恢复默认 QuanPixel。

源码目录也保留了 Fusion Pixel 比例版，但它的垂直边界和基线超过固定
8×8 字格，生成器会拒绝它以避免裁坏字形；`.modkitignore` 会把比例版排除
在安装 ZIP 之外。

## 永久更换默认字体

若要让无参数命令使用另一个字体，请将兼容的 BDF 保存为
`mods/zh_cn/assets/font/quan.bdf`，然后重新生成和检查。文件名只是默认入口；
生成器会读取 BDF 内的真实字体家族和版本。

分发替换后的字体前，必须同步更新 `LICENSES/`、`CREDITS.md` 和 README 中
的版权、来源及许可证。仓库现有 QuanPixel 与 Fusion Pixel 均使用 SIL
Open Font License 1.1。

## 严格验证并生成安装 ZIP

内容模组不需要重新编译 Gen1Recomp 的 EXE。准备一个 Gen1Recomp 源码目录，
并确保你已用自己合法持有的 ROM 在本机生成测试数据。假设当前目录是本
汉化仓库根目录：

```powershell
$project = (Resolve-Path '.').Path
$engine = (Resolve-Path '..\gen1recomp-source').Path

Push-Location $engine
try {
  $env:LUA = "$engine\tools\.local\luajit\bin\lua-runner.exe"
  $env:MODKIT_LUAJIT = $env:LUA

  py -3 tools\modkit.py validate "$project\mods\zh_cn" --strict --base imported
  New-Item -ItemType Directory -Path "$project\dist" -Force | Out-Null
  py -3 tools\modkit.py pack "$project\mods\zh_cn" `
    -o "$project\dist\zh_cn-0.3.0.zip" --base imported
}
finally {
  Pop-Location
}
```

如果你的目录布局不同，只需把 `$engine` 改成自己的 Gen1Recomp 源码目录；
不要把本机绝对路径写进仓库。发行前还要检查 ZIP 文件列表，确认不含
`*.gb`、`*.gbc`、英文 worksheet、`pokemon_names.txt`、存档、缓存和测试输出。

## 常见问题

- PowerShell 使用保存了程序路径的变量时，要写 `& $python script.py`；直接
  写 `$python script.py` 会触发 `Unexpected token`。
- `missing glyph`：BDF 缺少译文所需字符；错误会列出字符和使用位置。
- `does not fit ... 8x8`：字形尺寸或基线无法无损放入当前字格。
- 直接修改 `lang/font.lua`、`lang/charmap.lua` 或 PNG 会在下次生成时被覆盖。
- 使用临时 `--bdf` 生成后，不能用默认字体执行 `--check`；二者必须一致。

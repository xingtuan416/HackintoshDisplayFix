# HackintoshDisplayFix

> **修复黑苹果显示问题的工具** —— 专治 macOS / 黑苹果外接显示器的紫屏、绿屏、花屏、黑屏、色彩失真与识别异常。

[![tests](https://github.com/xingtuan416/HackintoshDisplayFix/actions/workflows/test.yml/badge.svg)](https://github.com/xingtuan416/HackintoshDisplayFix/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](#系统要求)
[![Shell](https://img.shields.io/badge/shell-bash%203.2%2B-89e051.svg)](#系统要求)

---

## 这个工具解决什么问题

如果你在黑苹果（或白苹果）上遇到过下面任何一种情况，这个工具就是为你写的：

| 症状 | 典型场景 |
|---|---|
| **紫屏 / 紫红色调** | HDMI 连接外接显示器，画面整体泛紫 |
| **绿屏 / 偏色** | 颜色明显失真，或黑白场偏色 |
| **花屏 / 雪花 / 条纹** | 画面撕裂、闪烁、随机噪点 |
| **黑屏点不亮** | 显示器有信号但不出图，或需要反复插拔 |
| **分辨率异常** | 无法识别到原生分辨率、选项缺失 |
| **识别异常** | 系统识别不到外接显示器，或识别成错误型号 |
| **休眠唤醒后花屏** | 睡眠唤醒后需要重新插拔才能恢复 |

根因通常是 macOS 从显示器读到的 EDID 不完整或有兼容性问题，导致它选错了色彩空间与显示时序。

---

## 工作原理

macOS 允许通过 `Overrides` 目录覆盖单个显示器的 EDID：

```
/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<VID>/DisplayProductID-<PID>
```

本工具读取系统检测到的显示器 EDID，做三处强制修正后写入该文件：

| 字节 | 含义 | 原值 | 修正为 |
|---|---|---|---|
| 19 | EDID 版本 | 不定 | `0x04`（EDID 1.4） |
| 20 | 视频输入定义 | 不定 | `0x90`（强制数字输入） |
| 24 | Feature Support | 不定 | `0xE6` |
| 127 | 校验和 | — | 重新计算，保证 128 字节和为 0 |

**本工具只注入 EDID，不写入任何 HIDPI 分辨率配置**，因此不会和你的分辨率设置冲突。

> Apple Silicon（M 系列）的 macOS 不向外暴露完整 EDID，此时工具退化为注入 VID+PID 标识，效果因机型而异。

---

## 系统要求

- macOS 10.13 及以上（Intel / Apple Silicon 均可）
- 系统自带 `bash` 3.2+、`ioreg`、`xxd`、`base64`（macOS 全部自带，无需安装任何东西）
- 支持语言：**简体中文 / English / Українська**（自动跟随系统语言）

---

## 使用方法

### 1. 下载

**只想用工具** —— 到 [Releases](https://github.com/xingtuan416/HackintoshDisplayFix/releases) 页面下载
`HackintoshDisplayFix-v1.0.0.zip`，解压后只有一个脚本和说明文档，没有多余文件。

**想看源码 / 参与开发**：

```bash
git clone https://github.com/xingtuan416/HackintoshDisplayFix.git
cd HackintoshDisplayFix
```

> 注意：GitHub 自动生成的 "Source code (zip)" 会包含 `tests/` 目录，那是给开发用的，普通使用不需要。

### 2. 运行

```bash
bash HackintoshDisplayFix.sh
```

也可以把 `HackintoshDisplayFix.sh` 拖进「终端」窗口后回车。

> 中途会要求输入开机密码（写入系统目录需要管理员权限）。**输入时屏幕上不会显示任何字符，这是正常的**，输完直接回车即可。

### 3. 按提示操作

```
  ================================================================
   HackintoshDisplayFix   v1.0.0
   修复黑苹果 / macOS 外接显示器显示异常（紫屏 · 绿屏 · 花屏 · 黑屏）
   https://github.com/xingtuan416/HackintoshDisplayFix
  ================================================================

  检测到 2 台显示器:

    1)  10ac:4183   DELL U2720Q
    2)  1e6d:5b11   LG HDR 4K

  请选择要修复的显示器 [1-2]（q 退出）: 1
```

**① 选择出问题的那台显示器**（按序号）。

**② 选择「(1) 注入 EDID —— 修复显示问题」**。

**③ 选择显示器图标** —— 这里**直接选 `(6) 保持原样`** 即可，见下节。

**④ 确认后输入 `y`**，然后输入开机密码。

**⑤ 重启 Mac**，配置才会生效。

### 4. 命令行参数

```bash
bash HackintoshDisplayFix.sh            # 交互式运行
bash HackintoshDisplayFix.sh --list     # 只列出检测到的显示器（排查问题用）
bash HackintoshDisplayFix.sh --help     # 帮助
bash HackintoshDisplayFix.sh --version  # 版本号
```

---

## 强烈推荐：(6) 保持原样 + (1) 注入 EDID

图标选择那一步，**请选 `(6) 保持原样`**，原因：

- **兼容性最强** —— 不修改 `Icons.plist`，不引入任何额外的系统识别信息
- **不会二次出问题** —— 改图标会往 `Overrides` 里写入额外的 plist 键值，增加与系统冲突的概率
- **修复效果完全不受影响** —— EDID 注入和图标是两件独立的事，改图标对修显示问题没有任何帮助
- **黑苹果尤其适用** —— 黑苹果的机型识别本身就脆弱，少动一样少一分风险

所以选项 `(6)` 后面标了 **【推荐】**，它是默认且最稳的选择。

> 如果你确实想要 iMac / MacBook 风格的显示器图标，再选 `(1)`~`(5)`，但它们只是外观，与修显示问题无关。

---

## 还原 / 卸载

### 方式一：重新运行脚本

```bash
bash HackintoshDisplayFix.sh
```

选择显示器 → 选 `(2) 还原 / 移除已注入的配置`，然后：

- `(1) 只移除本显示器的配置` —— 只删掉这台显示器的注入，**推荐**
- `(2) 移除 Overrides 目录下的全部配置` —— 连其他工具（如 one-key-hidpi）写入的 HIDPI 配置也一并删除，慎用

### 方式二：运行自动生成的还原脚本

每次注入成功后，工具会在你的用户目录生成一个独立还原脚本：

```bash
~/.hackintoshdisplayfix-restore.sh
```

直接运行即可，它自己会申请管理员权限。

### 方式三：手动删除

```bash
sudo rm -rf "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-<你的VID>"
```

改完都要**重启 Mac** 才生效。

### 自动备份

注入前，如果该显示器已存在旧配置，工具会自动备份到：

```
~/.hackintoshdisplayfix/backup/<时间戳>/
```

---

## 常见问题

**Q：注入后还是紫屏 / 花屏？**
先运行 `(2)` 还原并重启，然后重新注入一次。如果仍然无效，可能是线材、接口或显卡驱动层面的问题，EDID 注入解决不了。

**Q：为什么注入完必须重启？**
`Overrides` 只在显示器初始化时读取，运行期无法热重载。

**Q：Apple Silicon（M 系列）没效果？**
M 系列不外暴露完整 EDID，工具只能退化为注入 VID+PID。请先升级到最新的 macOS 再试。

**Q：会不会把系统搞坏？**
不会。工具只往 `/Library/Displays/...` 写文件，不碰系统卷（`/System`）和 EFI。而且操作前有备份、之后有还原脚本。不过**黑苹果用户仍建议先备份 EFI**，这是好习惯。

**Q：提示「没有检测到任何显示器」？**
用 `bash HackintoshDisplayFix.sh --list` 看检测结果。若确实为空，说明 macOS 没能从 `ioreg` 读出显示器 EDID，先排查线材和接口。

**Q：支持 macOS Tahoe 26 吗？**
支持。

**Q：能修复内置屏幕吗？**
可以，内置屏也会出现在列表里，但通常没必要。

---

## 项目结构

```
HackintoshDisplayFix/
├── HackintoshDisplayFix.sh      # 主程序（纯 bash，无依赖）
├── README.md
├── LICENSE                       # MIT
├── CHANGELOG.md
├── .github/workflows/test.yml    # CI
└── tests/
    ├── run_tests.sh              # 测试套件（59 项断言）
    ├── gen_fixtures.py           # 重新生成 EDID 测试数据用（日常不需要跑）
    └── fixtures/                 # EDID 测试向量
```

### 运行测试

```bash
sudo bash tests/run_tests.sh
```

工具本身只能在 macOS 上运行，测试套件用 mock 顶替 `ioreg` / `sudo` / `uname` / `curl` 等 macOS 专有命令，
验证**解析逻辑、交互流程、文件产物**是否正确（含 EDID 改造算法的逐字节比对）。

- **在 Linux 上跑**：`sed` 会被 mock 掉（GNU sed 不支持 BSD 的 `-i ''` 写法）
- **在 macOS 上跑**：`sed` / `xxd` / `base64` 全部用真命令，验证的是真实的 BSD 行为

CI 实测结果：

| 平台 | bash 版本 | 结果 |
|---|---|---|
| macOS (arm64) | **3.2.57**（系统自带） | **59 / 59 通过** |
| Ubuntu | 5.2.21 | 59 / 59 通过 |

macOS 那一栏是**故意用 `/bin/bash` 启动**的 —— runner 的 PATH 里 Homebrew 在前，裸 `bash` 会拿到 bash 5。
这样才能确认脚本在 macOS 自带的 bash 3.2 上确实跑得起来，而那正是唯一真正重要的运行环境。

CI 还会额外扫描 bash 4+ 专有写法（关联数组、`${var,,}`、`mapfile` 等），防止以后不小心写进去。

> ⚠️ **不要在自己的 Mac 上随手跑测试。** 它会清空 `/Library/Displays/Contents/Resources/Overrides`，
> 而那正是你真实显示器配置所在的位置。测试套件启动时会先检查该目录，**一旦发现里面有内容就直接拒绝运行**，
> 但更稳妥的做法还是用 CI 或干净的虚拟机。

详见 [.github/workflows/test.yml](.github/workflows/test.yml)。

---

## 相比旧版 Great-EDID 的改进

| 项 | 旧版 | 现在 |
|---|---|---|
| 输入错误 | 直接退出，要重跑全流程 | 提示后重新输入，不中断 |
| 密码提示时机 | 在显示器列表**之前**就弹密码 | 移到确认操作之后 |
| 单台显示器 | 不显示列表，直接静默选中 | 同样列出并确认 |
| 显示器名称 | 只读第 3 个 descriptor，放在第 4 个就乱码 | 4 个 descriptor 全扫描 |
| Apple / LG 显示器 | 名称被硬编码覆盖 | 仅在解析不出真实名称时才兜底 |
| 表格排版 | 列宽写死，`\|` 对不齐 | 改为编号列表，不再错位 |
| 横幅 | 行尾 `\` 被 heredoc 当续行符，缺一块 | 重绘 |
| 结果校验 | 不检查是否真的写入成功 | 写入后校验文件存在性 |
| 备份 | README 说「自带备份」，实际不备份 | 真正备份到 `~/.hackintoshdisplayfix/backup/` |
| 还原脚本 | Apple Silicon 版本引用了未定义变量和不存在的 `xpath` 命令，是坏的 | 重写为自包含、可正常执行 |
| 还原范围 | 「还原所有设置」= 静默 `rm -rf` 整个目录 | 明确提示会影响其他工具的配置 |
| 显示器去重 | 同一台显示器可能重复出现 | 按 VID:PID 去重 |

---

## 致谢

本项目的 EDID 注入思路与图标资源参考了 **[one-key-hidpi](https://github.com/xzhih/one-key-hidpi)**（MIT License，作者 [@xzhih](https://github.com/xzhih)）。

这是一个**独立重写**的项目，不是 one-key-hidpi 的 fork，代码与交互流程均已重做。

---

## 许可证

[MIT](LICENSE) © 2025 wezzs0406

---

## English

**HackintoshDisplayFix** — a tool that fixes external display issues on Hackintosh / macOS (purple screen, green tint, artifacts, black screen, wrong resolution) by injecting a corrected EDID override.

```bash
git clone https://github.com/xingtuan416/HackintoshDisplayFix.git
cd HackintoshDisplayFix
bash HackintoshDisplayFix.sh
```

Pick your display, choose `(1) Inject EDID`, choose `(6) Keep as is`, confirm, enter your password, then **reboot**.
Run `bash HackintoshDisplayFix.sh --list` to only list detected displays. Restore with `~/.hackintoshdisplayfix-restore.sh`.

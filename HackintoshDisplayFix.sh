#!/bin/bash
#
#  HackintoshDisplayFix  —  修复黑苹果 / macOS 外接显示器显示异常
#
#  典型症状：HDMI 连接外接显示器出现紫屏、绿屏、花屏、闪烁、色彩失真、
#            分辨率异常、显示器无法点亮或识别异常。
#
#  原理：向 /Library/Displays/Contents/Resources/Overrides 写入显示器 EDID 覆盖配置，
#        强制 macOS 采用标准数字输入与显示时序，从而修复上述显示异常。
#        本工具只注入 EDID，不改动任何 HIDPI 分辨率设置。
#
#  用法：bash HackintoshDisplayFix.sh
#        bash HackintoshDisplayFix.sh --list      只列出显示器
#        bash HackintoshDisplayFix.sh --help
#
#  许可证：MIT
#  参考项目：one-key-hidpi (https://github.com/xzhih/one-key-hidpi) — MIT
#

set -o pipefail

VERSION="1.0.0"
APP_NAME="HackintoshDisplayFix"
REPO_URL="https://github.com/xingtuan416/HackintoshDisplayFix"

# ---------------------------------------------------------------- 路径常量

TARGET_DIR="/Library/Displays/Contents/Resources/Overrides"
SYSTEM_TARGET_DIR="/System${TARGET_DIR}"
BACKUP_ROOT="${HOME}/.hackintoshdisplayfix/backup"
RESTORE_SCRIPT="${HOME}/.hackintoshdisplayfix-restore.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
WORK_DIR=""
LANG_CODE="en"

# ---------------------------------------------------------------- 显示器数据

DISP_VID=()
DISP_PID=()
DISP_NAME=()
DISP_EDID=()
DISP_COUNT=0

# 交互结果（用全局变量回传，避免命令替换把界面输出一起捕获）
CHOSEN_INDEX=0
CHOSEN_ICON=6

# ---------------------------------------------------------------- 语言包

function load_strings() {
    S_TAGLINE="Fix Hackintosh / macOS external display issues"
    S_NEED_MACOS="This tool only runs on macOS."
    S_MISSING_CMD="Missing required command:"
    S_NO_DISPLAY="No display was detected. Nothing to do. Exiting."
    S_LIST_TITLE="%d display(s) detected"
    S_PICK="  Select the display to fix [1-%d] (q to quit): "
    S_INVALID="  Invalid input, please try again."
    S_CANCELLED="Cancelled."
    S_SELECTED="Selected display:"
    S_MENU_TITLE="What do you want to do?"
    S_MENU_INJECT="(1) Inject EDID  ->  fix the display issue   [recommended]"
    S_MENU_RESTORE="(2) Restore / remove injected configuration"
    S_MENU_QUIT="(q) Quit"
    S_ACTION_PROMPT="  Enter your choice [1-2] (q to quit): "
    S_ICON_TITLE="Display icon (optional, does not affect the fix)"
    S_ICON_IMAC="(1) iMac"
    S_ICON_MB="(2) MacBook"
    S_ICON_MBP="(3) MacBook Pro"
    S_ICON_LG="(4) LG display"
    S_ICON_XDR="(5) Pro Display XDR"
    S_ICON_NONE="(6) Keep as is  [recommended]"
    S_ICON_PROMPT="  Enter your choice [1-6]: "
    S_CONFIRM_TITLE="Please confirm"
    S_CONFIRM_DISPLAY="Display"
    S_CONFIRM_ACTION="Action"
    S_CONFIRM_ICON="Icon"
    S_CONFIRM_PROMPT="  Proceed? [y/N]: "
    S_ACTION_INJECT="Inject EDID (fix display issue)"
    S_ACTION_RESTORE_ONE="Remove this display's configuration"
    S_ACTION_RESTORE_ALL="Remove ALL override configuration"
    S_NEED_ADMIN="Administrator privileges are required to write:"
    S_NEED_ADMIN2="Please enter your password when prompted."
    S_ADMIN_FAILED="Failed to obtain administrator privileges. Aborted."
    S_WORKING="Working, please wait..."
    S_BACKUP="Backing up existing configuration to:"
    S_INJECT_OK="EDID injected successfully - the display issue should be fixed."
    S_INJECT_LOG="Only EDID was injected. No HIDPI resolution was configured."
    S_VERIFY_OK="Verification passed:"
    S_VERIFY_FAIL="Verification FAILED, configuration file was not written:"
    S_REBOOT="REBOOT your Mac for the change to take effect."
    S_RESTORE_MENU="How much do you want to remove?"
    S_RESTORE_ONE="(1) Only this display"
    S_RESTORE_ALL="(2) Everything in the Overrides folder (also removes config written by other tools)"
    S_RESTORE_PROMPT="  Enter your choice [1-2] (q to cancel): "
    S_RESTORE_DONE="Configuration removed."
    S_RESTORE_SCRIPT="A standalone restore script was written to:"
    S_DOWNLOAD_FAIL="Could not download the icon resources (offline?). Continuing without icon."
    S_ABORTED="Aborted."
    S_UNKNOWN_MONITOR="Unknown display"
    S_HINT_ICON="Tip: keeping the icon unchanged is the safest and most compatible choice."

    if [ "$LANG_CODE" = "zh_CN" ]; then
        S_TAGLINE="修复黑苹果 / macOS 外接显示器显示异常（紫屏 · 绿屏 · 花屏 · 黑屏）"
        S_NEED_MACOS="本工具仅支持 macOS。"
        S_MISSING_CMD="缺少必要命令："
        S_NO_DISPLAY="没有检测到任何显示器，无需处理，退出。"
        S_LIST_TITLE="检测到 %d 台显示器"
        S_PICK="  请选择要修复的显示器 [1-%d]（q 退出）: "
        S_INVALID="  输入无效，请重新输入。"
        S_CANCELLED="已取消。"
        S_SELECTED="已选择显示器："
        S_MENU_TITLE="请选择要执行的操作"
        S_MENU_INJECT="(1) 注入 EDID —— 修复显示问题   【推荐】"
        S_MENU_RESTORE="(2) 还原 / 移除已注入的配置"
        S_MENU_QUIT="(q) 退出"
        S_ACTION_PROMPT="  请输入你的选择 [1-2]（q 退出）: "
        S_ICON_TITLE="显示器图标（可选，不影响修复效果）"
        S_ICON_IMAC="(1) iMac"
        S_ICON_MB="(2) MacBook"
        S_ICON_MBP="(3) MacBook Pro"
        S_ICON_LG="(4) LG 显示器"
        S_ICON_XDR="(5) Pro Display XDR"
        S_ICON_NONE="(6) 保持原样   【推荐】"
        S_ICON_PROMPT="  请输入你的选择 [1-6]: "
        S_CONFIRM_TITLE="请确认"
        S_CONFIRM_DISPLAY="显示器"
        S_CONFIRM_ACTION="操作"
        S_CONFIRM_ICON="图标"
        S_CONFIRM_PROMPT="  确认继续？[y/N]: "
        S_ACTION_INJECT="注入 EDID（修复显示问题）"
        S_ACTION_RESTORE_ONE="移除该显示器的配置"
        S_ACTION_RESTORE_ALL="移除全部覆盖配置"
        S_NEED_ADMIN="写入以下位置需要管理员权限："
        S_NEED_ADMIN2="稍后提示时请输入你的开机密码。"
        S_ADMIN_FAILED="获取管理员权限失败，已中止。"
        S_WORKING="正在处理，请稍候……"
        S_BACKUP="正在备份原有配置到："
        S_INJECT_OK="EDID 注入成功，显示问题已修复。"
        S_INJECT_LOG="本次仅注入 EDID，未配置任何 HIDPI 分辨率。"
        S_VERIFY_OK="校验通过："
        S_VERIFY_FAIL="校验失败，配置文件没有写入成功："
        S_REBOOT="请重启 Mac 后生效。"
        S_RESTORE_MENU="要移除多少配置？"
        S_RESTORE_ONE="(1) 只移除本显示器的配置"
        S_RESTORE_ALL="(2) 移除 Overrides 目录下的全部配置（会一并移除其他工具写入的配置）"
        S_RESTORE_PROMPT="  请输入你的选择 [1-2]（q 取消）: "
        S_RESTORE_DONE="配置已移除。"
        S_RESTORE_SCRIPT="已生成独立还原脚本："
        S_DOWNLOAD_FAIL="图标资源下载失败（是否断网？），将跳过图标设置。"
        S_ABORTED="已中止。"
        S_UNKNOWN_MONITOR="未知显示器"
        S_HINT_ICON="提示：保持图标不变兼容性最好，也是官方推荐做法。"
    elif [ "$LANG_CODE" = "uk_UA" ]; then
        S_TAGLINE="Виправлення проблем із зовнішніми дисплеями на Hackintosh / macOS"
        S_NEED_MACOS="Цей інструмент працює лише на macOS."
        S_MISSING_CMD="Відсутня потрібна команда:"
        S_NO_DISPLAY="Дисплеїв не знайдено. Нічого робити. Вихід."
        S_LIST_TITLE="Знайдено дисплеїв — %d"
        S_PICK="  Вибери дисплей для виправлення [1-%d] (q — вихід): "
        S_INVALID="  Невірне введення, спробуй ще раз."
        S_CANCELLED="Скасовано."
        S_SELECTED="Вибраний дисплей:"
        S_MENU_TITLE="Що зробити?"
        S_MENU_INJECT="(1) Інжектувати EDID —— виправити проблему   [рекомендовано]"
        S_MENU_RESTORE="(2) Відновити / видалити налаштування"
        S_MENU_QUIT="(q) Вихід"
        S_ACTION_PROMPT="  Введи свій вибір [1-2] (q — вихід): "
        S_ICON_TITLE="Піктограма дисплея (необовʼязково)"
        S_ICON_IMAC="(1) iMac"
        S_ICON_MB="(2) MacBook"
        S_ICON_MBP="(3) MacBook Pro"
        S_ICON_LG="(4) Дисплей LG"
        S_ICON_XDR="(5) Pro Display XDR"
        S_ICON_NONE="(6) Не змінювати   [рекомендовано]"
        S_ICON_PROMPT="  Введи свій вибір [1-6]: "
        S_CONFIRM_TITLE="Підтверди"
        S_CONFIRM_DISPLAY="Дисплей"
        S_CONFIRM_ACTION="Дія"
        S_CONFIRM_ICON="Піктограма"
        S_CONFIRM_PROMPT="  Продовжити? [y/N]: "
        S_ACTION_INJECT="Інжектувати EDID (виправити проблему)"
        S_ACTION_RESTORE_ONE="Видалити налаштування цього дисплея"
        S_ACTION_RESTORE_ALL="Видалити всі налаштування"
        S_NEED_ADMIN="Для запису потрібні права адміністратора:"
        S_NEED_ADMIN2="Введи пароль, коли зʼявиться запит."
        S_ADMIN_FAILED="Не вдалося отримати права адміністратора. Скасовано."
        S_WORKING="Обробка, зачекай…"
        S_BACKUP="Резервна копія налаштувань:"
        S_INJECT_OK="EDID успішно інжектовано — проблему з дисплеєм виправлено."
        S_INJECT_LOG="Інжектовано лише EDID, HIDPI не налаштовувався."
        S_VERIFY_OK="Перевірку пройдено:"
        S_VERIFY_FAIL="Перевірка НЕ пройдена, файл не записано:"
        S_REBOOT="Перезавантаж Mac, щоб застосувати зміни."
        S_RESTORE_MENU="Скільки налаштувань видалити?"
        S_RESTORE_ONE="(1) Лише цей дисплей"
        S_RESTORE_ALL="(2) Усе в теці Overrides (разом із налаштуваннями інших інструментів)"
        S_RESTORE_PROMPT="  Введи свій вибір [1-2] (q — скасувати): "
        S_RESTORE_DONE="Налаштування видалено."
        S_RESTORE_SCRIPT="Окремий скрипт відновлення записано до:"
        S_DOWNLOAD_FAIL="Не вдалося завантажити ресурси піктограм. Продовжую без піктограми."
        S_ABORTED="Скасовано."
        S_UNKNOWN_MONITOR="Невідомий дисплей"
        S_HINT_ICON="Порада: не змінювати піктограму — найсумісніший варіант."
    fi
}

function detect_language() {
    local loc=""
    loc=$(defaults read -g AppleLocale 2>/dev/null || true)
    if [ -z "$loc" ]; then
        loc="${LC_ALL:-${LANG:-}}"
    fi
    case "$loc" in
        zh_Hans*|zh_CN*|zh_SG*|zh-Hans*) LANG_CODE="zh_CN" ;;
        uk*)                             LANG_CODE="uk_UA" ;;
        zh*)                             LANG_CODE="zh_CN" ;;
        *)                               LANG_CODE="en" ;;
    esac
    load_strings
}

# ---------------------------------------------------------------- 基础工具

function print_banner() {
    printf '\n'
    printf '  ================================================================\n'
    printf '   %s   v%s\n' "$APP_NAME" "$VERSION"
    printf '   %s\n' "$S_TAGLINE"
    printf '   %s\n' "$REPO_URL"
    printf '  ================================================================\n'
}

function info()  { printf '  %s\n' "$*"; }
function warn()  { printf '  ! %s\n' "$*" >&2; }
function die()   { printf '  ! %s\n' "$*" >&2; exit "${2:-1}"; }

# 读取 [min..max] 的整数选择。成功时把答案打到 stdout 并返回 0，取消返回 1。
function ask_choice() {
    local prompt="$1" min="$2" max="$3" ans
    while :; do
        printf '%s' "$prompt" >&2
        if ! read -r ans; then
            printf '\n' >&2
            return 1
        fi
        ans=$(printf '%s' "$ans" | tr -d '[:space:]')
        case "$ans" in
            ''|q|Q) return 1 ;;
        esac
        case "$ans" in
            *[!0-9]*) printf '%s\n' "$S_INVALID" >&2; continue ;;
        esac
        if [ "$ans" -ge "$min" ] && [ "$ans" -le "$max" ]; then
            printf '%s' "$ans"
            return 0
        fi
        printf '%s\n' "$S_INVALID" >&2
    done
}

# y/N 确认。返回 0 表示确认。
function ask_yes() {
    local prompt="$1" ans
    printf '%s' "$prompt" >&2
    if ! read -r ans; then
        printf '\n' >&2
        return 1
    fi
    case "$(printf '%s' "$ans" | tr -d '[:space:]' | tr 'A-Z' 'a-z')" in
        y|yes) return 0 ;;
        *)     return 1 ;;
    esac
}

function check_requirements() {
    if [ "$(uname -s)" != "Darwin" ]; then
        printf '%s\n' "$S_NEED_MACOS" >&2
        exit 3
    fi
    local missing="" c
    for c in ioreg xxd base64; do
        if ! command -v "$c" >/dev/null 2>&1; then
            missing="${missing} ${c}"
        fi
    done
    if [ -n "$missing" ]; then
        printf '%s%s\n' "$S_MISSING_CMD" "$missing" >&2
        exit 3
    fi
}

function cleanup() {
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------- 显示器检测

# 从 128 字节 EDID 里解析显示器名称：在 4 个 descriptor 中找 0xFC 描述符
function parse_monitor_name() {
    local edid="$1" off hex text
    for off in 54 72 90 108; do
        if [ "${edid:$((off * 2)):10}" = "000000fc00" ]; then
            hex="${edid:$((off * 2 + 10)):26}"
            text=$(printf '%s' "$hex" | xxd -p -r 2>/dev/null | tr -d '\000-\037' | sed 's/[[:space:]]*$//')
            if [ -n "$text" ]; then
                printf '%s' "$text"
                return 0
            fi
        fi
    done
    printf ''
}

# 名称解析不出来时，按厂商 ID 给一个兜底名称
function fallback_monitor_name() {
    case "$1" in
        0610) printf 'Apple Display' ;;
        1e6d) printf 'LG Display' ;;
        *)    printf '%s' "$S_UNKNOWN_MONITOR" ;;
    esac
}

function add_display() {
    local vid="$1" pid="$2" name="$3" edid="$4" i
    [ -z "$vid" ] && return 0
    [ -z "$pid" ] && return 0
    # 去重：同样的 VID:PID 只保留一条
    i=0
    while [ "$i" -lt "$DISP_COUNT" ]; do
        if [ "${DISP_VID[$i]}" = "$vid" ] && [ "${DISP_PID[$i]}" = "$pid" ]; then
            return 0
        fi
        i=$((i + 1))
    done
    DISP_VID[$DISP_COUNT]="$vid"
    DISP_PID[$DISP_COUNT]="$pid"
    DISP_NAME[$DISP_COUNT]="$name"
    DISP_EDID[$DISP_COUNT]="$edid"
    DISP_COUNT=$((DISP_COUNT + 1))
}

function detect_displays_intel() {
    local raw lines line edid vid pid name
    raw=$(ioreg -lw0 2>/dev/null | grep -i 'IODisplayEDID' | sed -n 's/.*<\([0-9a-fA-F]*\)>.*/\1/p')
    [ -z "$raw" ] && return 0

    local saved_ifs="$IFS"
    IFS=$'\n'
    lines=($raw)
    IFS="$saved_ifs"

    for line in "${lines[@]}"; do
        edid="$line"
        [ "${#edid}" -lt 32 ] && continue
        vid=$(printf '%s' "${edid:16:4}" | tr 'A-Z' 'a-z')
        pid=$(printf '%s' "${edid:22:2}${edid:20:2}" | tr 'A-Z' 'a-z')
        name=$(parse_monitor_name "$edid")
        [ -z "$name" ] && name=$(fallback_monitor_name "$vid")
        add_display "$vid" "$pid" "$name" "$edid"
    done
}

function detect_displays_arm() {
    local vends prods names
    vends=$(ioreg -l 2>/dev/null | grep 'DisplayAttributes' | sed -n 's/.*"LegacyManufacturerID"=\([0-9]*\).*/\1/p')
    prods=$(ioreg -l 2>/dev/null | grep 'DisplayAttributes' | sed -n 's/.*"ProductID"=\([0-9]*\).*/\1/p')
    names=$(ioreg -l 2>/dev/null | grep 'DisplayAttributes' | sed -n 's/.*"ProductName"="\([^"]*\)".*/\1/p')

    local saved_ifs="$IFS"
    IFS=$'\n'
    local a_vends=($vends) a_prods=($prods) a_names=($names)
    IFS="$saved_ifs"

    local i=0 n=${#a_prods[@]} vid pid name
    while [ "$i" -lt "$n" ]; do
        vid=$(printf '%04x' "${a_vends[$i]:-0}" 2>/dev/null)
        pid=$(printf '%04x' "${a_prods[$i]:-0}" 2>/dev/null)
        name="${a_names[$i]:-}"
        [ -z "$name" ] && name=$(fallback_monitor_name "$vid")
        add_display "$vid" "$pid" "$name" ""
        i=$((i + 1))
    done
}

function detect_displays() {
    DISP_VID=(); DISP_PID=(); DISP_NAME=(); DISP_EDID=(); DISP_COUNT=0
    if [ "$(uname -m)" = "arm64" ]; then
        detect_displays_arm
    else
        detect_displays_intel
    fi
}

function show_displays() {
    printf "\n  ${S_LIST_TITLE}:\n\n" "$DISP_COUNT"
    local i=0
    while [ "$i" -lt "$DISP_COUNT" ]; do
        printf '    %d)  %s:%s   %s\n' "$((i + 1))" "${DISP_VID[$i]}" "${DISP_PID[$i]}" "${DISP_NAME[$i]}"
        i=$((i + 1))
    done
    printf '\n'
}

# ---------------------------------------------------------------- EDID 处理

# 生成注入用的 base64 EDID
#   Intel：改造真实 EDID —— 强制 1.4 / 数字输入 / feature byte，并重算校验和
#   Apple Silicon：系统不暴露完整 EDID，退化为 VID+PID 四个字节
function build_edid_base64() {
    local edid="$1" vid_dec="$2" pid_dec="$3"
    if [ -n "$edid" ] && [ "${#edid}" -ge 256 ]; then
        local version basic checksum newcs newedid
        version=${edid:38:2}
        basic=${edid:40:2}
        checksum=${edid:254:2}
        newcs=$(printf '%02x' $(( (0x$checksum + 0x$version + 0x$basic - 0x04 - 0x90) & 0xff )))
        newedid="${edid:0:38}0490${edid:42:6}e6${edid:50:204}${newcs}"
        printf '%s' "$newedid" | xxd -r -p | base64 | tr -d '\n'
    else
        printf '%04x%04x' "$vid_dec" "$pid_dec" | xxd -r -p | base64 | tr -d '\n'
    fi
}

function write_display_plist() {
    local path="$1" vid_dec="$2" pid_dec="$3" edid_b64="$4"
    cat > "$path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>DisplayProductID</key>
	<integer>${pid_dec}</integer>
	<key>DisplayVendorID</key>
	<integer>${vid_dec}</integer>
	<key>IODisplayEDID</key>
	<data>${edid_b64}</data>
</dict>
</plist>
PLIST
}

# ---------------------------------------------------------------- 图标资源

function icon_base_url() {
    if [ -d "${SCRIPT_DIR}/displayIcons" ] && [ -f "${SCRIPT_DIR}/Icons.plist" ]; then
        printf 'file://%s' "$SCRIPT_DIR"
    else
        printf '%s/raw/main' "$REPO_URL"
    fi
}

# 返回 0 表示拿到图标模板
function fetch_icon_template() {
    local base url
    base=$(icon_base_url)
    url="${base}/Icons.plist"
    if ! curl -fsSL "$url" -o "${WORK_DIR}/Icons.plist" 2>/dev/null; then
        return 1
    fi
    [ -s "${WORK_DIR}/Icons.plist" ] || return 1
    return 0
}

function fetch_icon_asset() {
    local base name dest
    base=$(icon_base_url)
    name="$1"
    dest="$2"
    curl -fsSL "${base}/displayIcons/${name}" -o "$dest" 2>/dev/null
}

# 应用图标设置；$1 是用户选择
# 成功时把要写入 Overrides 的额外文件准备好，返回 0
function apply_icon() {
    local choice="$1" vid="$2" pid="$3"
    local icon_dir="${WORK_DIR}/DisplayVendorID-${vid}"
    local icon_file="${icon_dir}/DisplayProductID-${pid}"
    local picon="" rp=() asset=""

    mkdir -p "$icon_dir"

    case "$choice" in
        1) picon="\\/Library\\/Displays\\/Contents\\/Resources\\/Overrides\\/DisplayVendorID-${vid}\\/DisplayProductID-${pid}\\.icns"
           rp=("33" "68" "160" "90"); asset="iMac.icns" ;;
        2) picon="\\/Library\\/Displays\\/Contents\\/Resources\\/Overrides\\/DisplayVendorID-${vid}\\/DisplayProductID-${pid}\\.icns"
           rp=("52" "66" "122" "76"); asset="MacBook.icns" ;;
        3) picon="\\/Library\\/Displays\\/Contents\\/Resources\\/Overrides\\/DisplayVendorID-${vid}\\/DisplayProductID-${pid}\\.icns"
           rp=("40" "62" "147" "92"); asset="MacBookPro.icns" ;;
        4) picon="\\/Library\\/Displays\\/Contents\\/Resources\\/Overrides\\/DisplayVendorID-${vid}\\/DisplayProductID-${pid}\\.icns"
           rp=("11" "47" "202" "114")
           if ! cp "${SYSTEM_TARGET_DIR}/DisplayVendorID-1e6d/DisplayProductID-5b11.icns" "${icon_file}.icns" 2>/dev/null; then
               return 1
           fi ;;
        5) picon="\\/Library\\/Displays\\/Contents\\/Resources\\/Overrides\\/DisplayVendorID-${vid}\\/DisplayProductID-${pid}\\.icns"
           rp=("5" "45" "216" "121"); asset="ProDisplayXDR.icns" ;;
        6) rm -f "${WORK_DIR}/Icons.plist"
           rmdir "$icon_dir" 2>/dev/null
           return 0 ;;
        *) return 1 ;;
    esac

    if [ -n "$asset" ]; then
        if ! fetch_icon_asset "$asset" "${icon_file}.icns"; then
            warn "$S_DOWNLOAD_FAIL"
            rm -f "${WORK_DIR}/Icons.plist"
            rmdir "$icon_dir" 2>/dev/null
            return 1
        fi
    fi

    if [ ! -f "${WORK_DIR}/Icons.plist" ]; then
        return 1
    fi

    sed -i '' \
        -e "s/VID/${vid}/g" \
        -e "s/PID/${pid}/g" \
        -e "s/RPX/${rp[0]}/g" \
        -e "s/RPY/${rp[1]}/g" \
        -e "s/RPW/${rp[2]}/g" \
        -e "s/RPH/${rp[3]}/g" \
        -e "s/PICON/${picon}/g" \
        "${WORK_DIR}/Icons.plist"

    local dicon="\\/Library\\/Displays\\/Contents\\/Resources\\/Overrides\\/DisplayVendorID-${vid}\\/DisplayProductID-${pid}\\.icns"
    sed -i '' -e "s/DICON/${dicon}/g" "${WORK_DIR}/Icons.plist"
    return 0
}

# ---------------------------------------------------------------- 提权执行

# 以 root 执行 $1 指定的脚本
function run_as_root() {
    local script="$1"
    sudo /bin/bash "$script"
}

# 先申请一次管理员权限，把凭据缓存起来，后续 sudo 不再重复询问
function acquire_admin() {
    printf '\n'
    info "$S_NEED_ADMIN"
    info "  $TARGET_DIR"
    info "$S_NEED_ADMIN2"
    printf '\n'
    if ! sudo -v; then
        warn "$S_ADMIN_FAILED"
        return 1
    fi
    return 0
}

function backup_existing() {
    local vid="$1" stamp dir
    stamp=$(date +%Y%m%d-%H%M%S)
    dir="${BACKUP_ROOT}/${stamp}"
    local found=0
    if [ -d "${TARGET_DIR}/DisplayVendorID-${vid}" ] || [ -f "${TARGET_DIR}/Icons.plist" ]; then
        mkdir -p "$dir" 2>/dev/null || return 0
        if [ -d "${TARGET_DIR}/DisplayVendorID-${vid}" ]; then
            cp -R "${TARGET_DIR}/DisplayVendorID-${vid}" "$dir/" 2>/dev/null && found=1
        fi
        if [ -f "${TARGET_DIR}/Icons.plist" ]; then
            cp "${TARGET_DIR}/Icons.plist" "$dir/" 2>/dev/null && found=1
        fi
    fi
    if [ "$found" = "1" ]; then
        printf '%s' "$dir"
    fi
}

# ---------------------------------------------------------------- 注入

function do_inject() {
    local idx="$1" icon_choice="$2"
    local vid="${DISP_VID[$idx]}" pid="${DISP_PID[$idx]}" edid="${DISP_EDID[$idx]}"
    local vid_dec pid_dec edid_b64 dpi_file backup

    vid_dec=$((16#$vid))
    pid_dec=$((16#$pid))
    edid_b64=$(build_edid_base64 "$edid" "$vid_dec" "$pid_dec")

    dpi_file="${WORK_DIR}/DisplayVendorID-${vid}/DisplayProductID-${pid}"
    mkdir -p "${WORK_DIR}/DisplayVendorID-${vid}"

    if [ "$icon_choice" != "6" ]; then
        fetch_icon_template >/dev/null 2>&1 || warn "$S_DOWNLOAD_FAIL"
    fi

    write_display_plist "$dpi_file" "$vid_dec" "$pid_dec" "$edid_b64"

    if [ "$icon_choice" != "6" ]; then
        apply_icon "$icon_choice" "$vid" "$pid" >/dev/null 2>&1 || true
    fi

    backup=$(backup_existing "$vid")
    if [ -n "$backup" ]; then
        info "$S_BACKUP"
        info "  $backup"
    fi

    local priv="${WORK_DIR}/_priv_inject.sh"
    cat > "$priv" <<PRIV
#!/bin/bash
set -e
TARGET='${TARGET_DIR}'
SRC='${WORK_DIR}'
mkdir -p "\$TARGET"
cp -R "\$SRC/." "\$TARGET/"
rm -f "\$TARGET/_priv_inject.sh"
chown -R root:wheel "\$TARGET"
chmod -R 0755 "\$TARGET"
find "\$TARGET" -type f -exec chmod 0644 {} \;
PRIV
    chmod +x "$priv"

    info "$S_WORKING"
    if ! run_as_root "$priv"; then
        return 1
    fi

    # 校验
    if [ -f "${TARGET_DIR}/DisplayVendorID-${vid}/DisplayProductID-${pid}" ]; then
        info "$S_VERIFY_OK ${TARGET_DIR}/DisplayVendorID-${vid}/DisplayProductID-${pid}"
    else
        warn "$S_VERIFY_FAIL"
        warn "  ${TARGET_DIR}/DisplayVendorID-${vid}/DisplayProductID-${pid}"
        return 1
    fi

    write_restore_script "$vid" "$pid"
    return 0
}

function write_restore_script() {
    local vid="$1" pid="$2"
    mkdir -p "$(dirname "$RESTORE_SCRIPT")" 2>/dev/null
    cat > "$RESTORE_SCRIPT" <<RESTORE
#!/bin/bash
# ${APP_NAME} v${VERSION} — 独立还原脚本 / standalone restore script
# 生成时间 / generated: $(date '+%Y-%m-%d %H:%M:%S')
# 目标显示器 / target display: ${vid}:${pid}

TARGET='${TARGET_DIR}'
VID='${vid}'
PID='${pid}'

if [ "\$(id -u)" -ne 0 ]; then
    exec /usr/bin/sudo /bin/bash "\$0" "\$@"
fi

echo ""
echo "(1) Remove the configuration for this display (\${VID}:\${PID})"
echo "(2) Remove everything in the Overrides folder"
echo ""
printf 'Enter your choice [1-2]: '
read -r ans

case "\$ans" in
    1)
        rm -rf "\${TARGET}/DisplayVendorID-\${VID}"
        if [ -f "\${TARGET}/Icons.plist" ]; then
            /usr/libexec/PlistBuddy -c "Delete :vendors:\${VID}:products:\${PID}" "\${TARGET}/Icons.plist" 2>/dev/null || true
        fi
        ;;
    2)
        rm -rf "\$TARGET"
        ;;
    *)
        echo "Invalid input, nothing changed."
        exit 1
        ;;
esac

echo ""
echo "Done. Reboot your Mac to apply the change."
RESTORE
    chmod +x "$RESTORE_SCRIPT"
}

# ---------------------------------------------------------------- 还原

function do_restore() {
    local scope="$1" vid="$2" pid="$3"
    local priv="${WORK_DIR}/_priv_restore.sh"

    if [ "$scope" = "all" ]; then
        cat > "$priv" <<PRIV
#!/bin/bash
set -e
rm -rf '${TARGET_DIR}'
PRIV
    else
        cat > "$priv" <<PRIV
#!/bin/bash
TARGET='${TARGET_DIR}'
VID='${vid}'
PID='${pid}'
rm -rf "\${TARGET}/DisplayVendorID-\${VID}"
if [ -f "\${TARGET}/Icons.plist" ]; then
    /usr/libexec/PlistBuddy -c "Delete :vendors:\${VID}:products:\${PID}" "\${TARGET}/Icons.plist" 2>/dev/null || true
fi
exit 0
PRIV
    fi
    chmod +x "$priv"

    info "$S_WORKING"
    run_as_root "$priv"
}

# ---------------------------------------------------------------- 主流程

function choose_display() {
    local ans
    show_displays
    if ! ans=$(ask_choice "$(printf "$S_PICK" "$DISP_COUNT")" 1 "$DISP_COUNT"); then
        info "$S_CANCELLED"
        return 1
    fi
    CHOSEN_INDEX=$((ans - 1))
    return 0
}

function choose_icon() {
    local ans
    printf '\n  %s\n\n' "$S_ICON_TITLE"
    printf '    %s\n' "$S_ICON_IMAC"
    printf '    %s\n' "$S_ICON_MB"
    printf '    %s\n' "$S_ICON_MBP"
    printf '    %s\n' "$S_ICON_LG"
    printf '    %s\n' "$S_ICON_XDR"
    printf '    %s\n' "$S_ICON_NONE"
    printf '\n  %s\n\n' "$S_HINT_ICON"
    if ! ans=$(ask_choice "$S_ICON_PROMPT" 1 6); then
        CHOSEN_ICON=6
        return 0
    fi
    CHOSEN_ICON="$ans"
    return 0
}

function icon_label() {
    case "$1" in
        1) printf '%s' "$S_ICON_IMAC" ;;
        2) printf '%s' "$S_ICON_MB" ;;
        3) printf '%s' "$S_ICON_MBP" ;;
        4) printf '%s' "$S_ICON_LG" ;;
        5) printf '%s' "$S_ICON_XDR" ;;
        *) printf '%s' "$S_ICON_NONE" ;;
    esac
}

function main() {
    detect_language
    case "${1:-}" in
        -h|--help)
            cat <<HELP
$APP_NAME v$VERSION
$S_TAGLINE

用法 / Usage:
  bash $(basename "$0")              交互式运行
  bash $(basename "$0") --list       只列出检测到的显示器
  bash $(basename "$0") --help       显示帮助
  bash $(basename "$0") --version    显示版本

还原 / Restore:
  ${RESTORE_SCRIPT}
HELP
            exit 0 ;;
        -v|--version)
            printf '%s %s\n' "$APP_NAME" "$VERSION"
            exit 0 ;;
    esac

    print_banner
    check_requirements
    detect_displays

    if [ "$DISP_COUNT" -eq 0 ]; then
        warn "$S_NO_DISPLAY"
        exit 2
    fi

    if [ "${1:-}" = "--list" ]; then
        show_displays
        exit 0
    fi

    local idx ans
    if ! choose_display; then
        exit 0
    fi
    idx="$CHOSEN_INDEX"
    info "$S_SELECTED ${DISP_VID[$idx]}:${DISP_PID[$idx]}  ${DISP_NAME[$idx]}"
    printf '\n'

    printf '  %s\n\n' "$S_MENU_TITLE"
    printf '    %s\n' "$S_MENU_INJECT"
    printf '    %s\n' "$S_MENU_RESTORE"
    printf '    %s\n' "$S_MENU_QUIT"
    printf '\n'

    if ! ans=$(ask_choice "$S_ACTION_PROMPT" 1 2); then
        info "$S_CANCELLED"
        exit 0
    fi

    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hackintoshdisplayfix.XXXXXX") || die "mktemp failed"
    chmod 700 "$WORK_DIR"

    if [ "$ans" = "1" ]; then
        local icon
        choose_icon
        icon="$CHOSEN_ICON"
        printf '\n  --- %s ---\n\n' "$S_CONFIRM_TITLE"
        printf '    %s : %s (%s:%s)\n' "$S_CONFIRM_DISPLAY" "${DISP_NAME[$idx]}" "${DISP_VID[$idx]}" "${DISP_PID[$idx]}"
        printf '    %s : %s\n' "$S_CONFIRM_ACTION" "$S_ACTION_INJECT"
        printf '    %s : %s\n\n' "$S_CONFIRM_ICON" "$(icon_label "$icon")"
        if ! ask_yes "$S_CONFIRM_PROMPT"; then
            info "$S_ABORTED"
            exit 0
        fi
        acquire_admin || exit 1
        if do_inject "$idx" "$icon"; then
            printf '\n'
            info "$S_INJECT_OK"
            info "$S_INJECT_LOG"
            info "$S_RESTORE_SCRIPT"
            info "  $RESTORE_SCRIPT"
            printf '\n'
            info "$S_REBOOT"
            printf '\n'
        else
            exit 1
        fi
    else
        printf '\n  %s\n\n' "$S_RESTORE_MENU"
        printf '    %s\n' "$S_RESTORE_ONE"
        printf '    %s\n\n' "$S_RESTORE_ALL"
        local scope_ans
        if ! scope_ans=$(ask_choice "$S_RESTORE_PROMPT" 1 2); then
            info "$S_CANCELLED"
            exit 0
        fi
        if [ "$scope_ans" = "1" ]; then
            printf '\n  --- %s ---\n\n' "$S_CONFIRM_TITLE"
            printf '    %s : %s (%s:%s)\n' "$S_CONFIRM_DISPLAY" "${DISP_NAME[$idx]}" "${DISP_VID[$idx]}" "${DISP_PID[$idx]}"
            printf '    %s : %s\n\n' "$S_CONFIRM_ACTION" "$S_ACTION_RESTORE_ONE"
            if ! ask_yes "$S_CONFIRM_PROMPT"; then
                info "$S_ABORTED"
                exit 0
            fi
            acquire_admin || exit 1
            do_restore "one" "${DISP_VID[$idx]}" "${DISP_PID[$idx]}"
        else
            printf '\n  --- %s ---\n\n' "$S_CONFIRM_TITLE"
            printf '    %s : %s\n\n' "$S_CONFIRM_ACTION" "$S_ACTION_RESTORE_ALL"
            if ! ask_yes "$S_CONFIRM_PROMPT"; then
                info "$S_ABORTED"
                exit 0
            fi
            acquire_admin || exit 1
            do_restore "all" "" ""
        fi
        printf '\n'
        info "$S_RESTORE_DONE"
        info "$S_REBOOT"
        printf '\n'
    fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi

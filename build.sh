#!/usr/bin/env bash
# ==============================================================================
# PonWrt (pbs05/ponwrt) 一键编译脚本
# 设备：Nokia XG-040G-MD / AN7581（profile: nokia_xg-040g-md-ubi）
# 用途：官方主线 + Vantage 主题 + 6 个应用 + 中文 + LAN 192.168.100.1
# 用法：把本文件夹放到 ponwrt 源码根目录下，然后
#         cd /path/to/ponwrt && ./ponwrt-040g-md/build.sh
#       或 ./build.sh /path/to/ponwrt
#       加 V=s ./build.sh ... 可输出详细编译日志
# ==============================================================================
set -euo pipefail

LAN_IP="192.168.100.1"
PROFILE="nokia_xg-040g-md-ubi"
SRC="${1:-$PWD}"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 并行编译数：GitHub Actions 的 2 核 runner 请设 JOBS=2，避免内存不足
JOBS="${JOBS:-$(nproc)}"

cd "$SRC"
if [ ! -x scripts/feeds ] || [ ! -f configs/an7581.config ]; then
    echo "错误：$SRC 不是 ponwrt 源码根目录（找不到 scripts/feeds 或 configs/an7581.config）" >&2
    echo "用法：$0 [ponwrt源码目录]" >&2
    exit 1
fi
for f in feeds.addon config.addon files/etc/uci-defaults/zzzz-custom; do
    [ -f "$SELF/$f" ] || { echo "错误：缺少 $SELF/$f" >&2; exit 1; }
done

echo "==> [1/7] 配置 feeds（官方 7 个源 + 2 个第三方源）"
if [ -f feeds.conf ]; then
    cp feeds.conf "feeds.conf.bak.$(date +%s)"
else
    cp feeds.conf.default feeds.conf
fi
# 重复运行不会重复追加
sed -i '/^src-git \(vantage\|airoha\)[[:space:]]/d' feeds.conf
cat "$SELF/feeds.addon" >> feeds.conf
grep -E '^src-git' feeds.conf

echo "==> [2/7] 更新并安装 feeds"
./scripts/feeds update -a
./scripts/feeds install -a

echo "==> [3/7] 写入自定义文件（IP / 中文 / 主题 / 版本标识）"
mkdir -p files
cp -rv "$SELF/files/." files/
chmod 0755 files/etc/uci-defaults/zzzz-custom

# 同时把 config_generate 里的默认 LAN IP 和时区改掉，双保险
python3 - "$SRC/package/base-files/files/bin/config_generate" "$LAN_IP" <<'PY'
import re, sys
p, ip = sys.argv[1], sys.argv[2]
s = open(p, encoding='utf-8').read()
s, n = re.subn(r'ipad=\$\{ipaddr:-"[0-9.]+"\}',
               'ipad=${ipaddr:-"%s"}' % ip, s)
print("  config_generate 默认 LAN IP -> %s（%d 处）" % (ip, n)) if n else \
    print("  警告：未匹配到默认 IP（uci-defaults 仍会设置）")
# 默认时区 UTC -> 北京时间（UTC+8）
s, t1 = re.subn(r"set system\.@system\[-1\]\.timezone='GMT0'",
                "set system.@system[-1].timezone='CST-8'", s)
s, t2 = re.subn(r"set system\.@system\[-1\]\.zonename='UTC'",
                "set system.@system[-1].zonename='Asia/Shanghai'", s)
print("  config_generate 默认时区 -> CST-8 / Asia/Shanghai（timezone %d 处, zonename %d 处）" % (t1, t2))
open(p, 'w', encoding='utf-8').write(s)
PY

echo "==> [4/7] 生成 .config（基于 configs/an7581.config）"
cp configs/an7581.config .config
# 只编译 XG-040G-MD，关掉同 config 里其它机型，缩短编译时间
python3 - "$PROFILE" <<'PY'
import re, sys
keep = sys.argv[1]
lines = open('.config', encoding='utf-8').read().splitlines()
out = []
for l in lines:
    m = re.match(r'^CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_(.+)=y$', l)
    if m and m.group(1) != keep:
        out.append('# CONFIG_TARGET_DEVICE_airoha_an7581_DEVICE_%s is not set' % m.group(1))
    else:
        out.append(l)
open('.config', 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print("  仅保留机型：%s" % keep)
PY
# 去掉即将追加的符号，避免 .config 里重复定义
python3 - "$SELF/config.addon" <<'PY'
import sys
addon = sys.argv[1]
keys = set()
for l in open(addon, encoding='utf-8'):
    if l.startswith('CONFIG_') and '=' in l:
        keys.add(l.split('=')[0])
lines = open('.config', encoding='utf-8').read().splitlines()
lines = [l for l in lines
         if not (l.split('=')[0] in keys or
                 (l.startswith('# ') and l[2:].split(' ')[0] in keys))]
open('.config', 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
PY
cat "$SELF/config.addon" >> .config

# ---------- 动态版本号 ----------
# 云编译时由 workflow 传入 FW_NUMBER（日期）与 FW_CODE（递增代号）；
# 本地直接运行则用默认值 2026.11 / r1。
FW_NUMBER="${FW_NUMBER:-2026.11}"
FW_CODE="${FW_CODE:-r1}"
echo "==> 固件版本：PonWrt ${FW_NUMBER} ${FW_CODE}"
# 覆盖 .config 版本项（必须在 make defconfig 之前）
python3 - "$FW_NUMBER" "$FW_CODE" <<'PY'
import sys
number, code = sys.argv[1], sys.argv[2]
lines = open('.config', encoding='utf-8').read().splitlines()
out = []
for l in lines:
    if l.startswith('CONFIG_VERSION_NUMBER='):
        out.append('CONFIG_VERSION_NUMBER="%s"' % number)
    elif l.startswith('CONFIG_VERSION_CODE='):
        out.append('CONFIG_VERSION_CODE="%s"' % code)
    else:
        out.append(l)
open('.config', 'w', encoding='utf-8').write('\n'.join(out) + '\n')
PY
# 真实改掉 base-files 模板里的 %R（git hash）：只改这两个纯文本模板，
# 不动 scripts/getver.sh、不动全局 REVISION，故不影响 base-files 包版本计算。
for tpl in package/base-files/files/etc/openwrt_release \
           package/base-files/files/usr/lib/os-release; do
    [ -f "$tpl" ] && sed -i "s/%R/${FW_CODE}/g" "$tpl"
done

echo "==> [5/7] make defconfig（自动解析并补全依赖）"
# 注意：绝不要在源码根目录写 version 文件。scripts/getver.sh 会优先读它，
# 从而改写全局 REVISION，连带影响 base-files 的 stamp 与包版本计算 ——
# 这正是上一轮 package/base-files 编译失败的原因。
# 版本号只通过 .config 的 VERSIONOPT 段设置；%R 残留的 git hash 由
# files/etc/uci-defaults/zzzz-custom 在首次开机时清理。
make defconfig

echo "--- 关键包确认（应全部为 =y）---"
grep -E '^CONFIG_PACKAGE_(luci-theme-vantage|luci-app-(upnp|autoreboot|ttyd|wol|airoha-npu|package-manager)|miniupnpd|ttyd|etherwake|kmod-br-netfilter)=y' .config || true

echo "==> [6/7] 下载源码包"
make -j"$JOBS" download

echo "==> [7/7] 编译（JOBS=$JOBS，首次约 1~3 小时，视机器性能）"
if [ "${V:-}" = "s" ]; then
    make -j"$JOBS" V=s
else
    make -j"$JOBS"
fi

echo
echo "================== 编译完成 =================="
echo "固件目录：bin/targets/airoha/an7581/"
echo "登录地址：http://${LAN_IP}（默认密码为空）"
echo "界面：简体中文，主题 Vantage"
echo "=============================================="

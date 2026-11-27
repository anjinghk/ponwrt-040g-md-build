# PonWrt 固件编译配置（XG-040G-MD + HG5382A）

主线：[pbs05/ponwrt](https://github.com/pbs05/ponwrt)（基于 ImmortalWrt，Airoha AN7581/AN7583 PON 设备，包管理器为 **apk**）。

同一套配置编译**两台机型**，各自发布独立 Release。两台**底层均用 pbs05/ponwrt 上游原样**（机型定义 / DTS / 分区 / 引导全部照上游），**上层注入同样的定制**（简体中文 / Vantage / 全套插件 / `192.168.100.1`）：

| 机型 | 平台 | 闪存 | profile | DEVICE 环境变量 | Release tag |
|---|---|---|---|---|---|
| **Nokia XG-040G-MD** | AN7581 | SkyHigh SPI NAND | `nokia_xg-040g-md-ubi` | `nokia_xg-040g-md-ubi`（默认） | `firmware-rN` |
| **FiberHome HG5382A** | AN7581 | 并行 NAND | `fiberhome_hg5382a` | `fiberhome_hg5382a` | `hg5382a-rN` |

两台均：管理地址 **192.168.100.1**、界面 **简体中文**、主题 **Vantage**、全套插件（含 iStore/UPnP/omcproxy）。
差异：**MD 打 SkyHigh 闪存补丁**（SPI NAND）；HG5382A 是并行 NAND，**不打**该补丁，刷机流程也不同（见第七节）。华邦闪存批次可能导致免拆刷机后无法启动的风险已知晓，按此方式编译，不因此做额外改动。

> 切换机型只需设环境变量 `DEVICE`，其余配置、插件、主题全部共用。若你的机器是 AN7583 的 **XG-040G-MF**，请把 `configs/an7581.config` 换成 `configs/an7583.config`、`DEVICE` 换成 `nokia_xg-040g-mf-ubi`。

---

## 一、插件去重与改名结果

最初清单里有 1 个重复、1 个笔误，处理后是 **1 个主题 + 6 个应用**；后续追加了 WOL 与 omcproxy。natmap（本机有公网、用不上打洞）与 IPTV（该插件的二层桥方案与实际环境不适配，改用手工脚本）已移除，现为 **1 个主题 + 7 个应用**（标"追加"）：

| # | 你写的 | 处理结果 | 来源 |
|---|---|---|---|
| 1 | `luci-theme-vantage` | 保留 | 第三方 feed `anothaDev/luci-theme-vantage` |
| 2 | `luci-app-package-manager` | **保留 1 次**（你写了 2 次）；且官方 `configs/an7581.config` 默认已启用 | ImmortalWrt `luci` feed |
| 3 | `luci-app-upnp` | 保留 | ImmortalWrt `luci` feed |
| 4 | `luci-app-autoreboot` | 保留 | ImmortalWrt `luci` feed |
| 5 | `luci-app-ttyd` | 保留 | ImmortalWrt `luci` feed |
| 6 | `luci-app-airoha-npu` | 保留 | 第三方 feed `naoki66/luci-app-airoha` |
| 7 | `luci-app-wol` | **追加**：网络唤醒（你说的"wol push"，社区无此同名包，确认用官方 WOL） | ImmortalWrt `luci` feed |
| 8 | `luci-app-omcproxy` | **追加**：IGMPv3/MLDv2 组播代理（用于 IPTV 组播，自带 LuCI 界面） | PonWrt 主线 `luci` feed |

> 已移除：`luci-app-natmap`（含笔误项 `luci-app-natmapt`）——本机有公网 IPv4，打洞无用；`luci-app-iptv`——其二层桥方案与联通 3300/4075 环境不适配，实际 IPTV 用独立脚本方案解决。

其余应用（package-manager / upnp / autoreboot / ttyd / wol）在 PonWrt 自带的 `luci` 与 `packages` feed 里都有，**不需要另外加源**；只有主题和 airoha-npu 需要加 2 个 `src-git` 源（见 `feeds.addon`）。

---

## 二、补齐的依赖

依赖来自各插件 Makefile 的 `LUCI_DEPENDS`，已全部写进 `config.addon`（`make defconfig` 本身也会自动选中）：

| 插件 | 运行期依赖 | 说明 |
|---|---|---|
| `luci-theme-vantage` | `luci-base` | 已有 |
| `luci-app-package-manager` | `luci-base`、`apk-openssl` | 已有（PonWrt 用 apk，不是 opkg） |
| `luci-app-upnp` | **`miniupnpd`、`rpcd-mod-ucode`** | upnp 本体必须装，否则页面开了不生效 |
| `luci-app-autoreboot` | **`crond`**（busybox `CONFIG_BUSYBOX_CONFIG_CROND`） | 定时重启靠 crond，默认已开 |
| `luci-app-ttyd` | **`ttyd`** | Web 终端本体 |
| `luci-app-airoha-npu` | **`kmod-br-netfilter`**、`CONFIG_KERNEL_DEVMEM`、busybox `devmem`、`rpcd` | 读 AN7581 NPU/PPE 寄存器必须有 `/dev/mem` + `devmem`；默认 config 里 `kmod-br-netfilter` 是关的，已补 |
| `luci-app-wol`（追加） | **`etherwake`** | 发送魔术包的本体，已补；官方默认关 |
| `luci-app-omcproxy`（追加） | **`omcproxy`** | 组播代理本体，已补；PonWrt 主线自带 |

另外 `rpcd`、`rpcd-mod-ucode`、`rpcd-mod-file` 等官方配置里已经带上了。

---

## 三、中文怎么保证

- 插件**全部有简体中文翻译**（`po/zh_Hans`），固件最终启用 11 个 `luci-i18n-*-zh-cn` 包：
  `base`、`firewall`、`package-manager`、`pon`（这 4 个官方 config 已带，故 `config.addon` 不重复写）＋
  `upnp`、`autoreboot`、`ttyd`、`airoha-npu`、`vantage-theme` ＋
  `wol`、`omcproxy`（追加）（这 7 个由 `config.addon` 显式选中）。
- `CONFIG_LUCI_LANG_zh_Hans=y` 让 LuCI 构建系统生成中文语言包，官方 config 已开。
- 首次启动脚本 `zzzz-custom` 把 `luci.main.lang` 设为 `zh_cn`，并把默认主题设为 Vantage。
  若少数页面仍显示英文，到 **系统 → 系统 → 语言和界面** 选「简体中文」即可（个别新版本 LuCI 语言值写成 `zh-cn`，把脚本里 `zh_cn` 改成 `zh-cn` 即可）。

---

## 四、192.168.100.1 怎么改

三处一起改，保证首次开机、恢复出厂、failsafe 都是这个地址：

1. `.config`：`CONFIG_TARGET_PREINIT_IP` / `CONFIG_TARGET_PREINIT_BROADCAST`（`config.addon` 已含）；
2. `package/base-files/files/bin/config_generate` 里 `ipad=${ipaddr:-"192.168.1.1"}` → `192.168.100.1`（脚本自动替换）；
3. `files/etc/uci-defaults/zzzz-custom`：删除 `network.lan.ipaddr` 的 list 后重新 `add_list 192.168.100.1/24`，并设置语言与主题。
   注意官方 `config_generate` 用的是 **add_list**，直接 `uci set` 会失败，所以脚本用「先 delete 再 add_list」。

---

## 五、固件版本号（无 git hash）

主线默认编译出来是 `PonWrt SNAPSHOT r0-d9dd3a4 / LuCI Master (git-…)`。本配置把它固定成：

> **`PonWrt 2026.11 r1 / LuCI release`**

LuCI「状态 → 概览 → 固件版本」显示 `OPENWRT_RELEASE`（模板是 `%D %V %C`，不含 `%R`），所以**只靠 `.config` 就是干净的**；固件文件名同步变成 `ponwrt-2026.11-r1-airoha-an7581-nokia_xg-040g-md-ubi-squashfs-sysupgrade.itb`。

| 位置 | 作用 |
|---|---|
| `config.addon` 的 `CONFIG_VERSIONOPT` 段 | `VERSION_NUMBER=2026.11`、`VERSION_CODE=r1`；`VERSION_FILENAMES` / `VERSION_CODE_FILENAMES` 让文件名自动带版本 |
| `files/etc/uci-defaults/zzzz-custom` 第 5、6 段 | 首次开机清掉 `BUILD_ID` / `DISTRIB_REVISION` / `/etc/build.version` 里 `%R` 残留的 hash，并覆盖 LuCI 版本模块去掉 `git-…` |

**以后想改**：改 `config.addon` 的 `CONFIG_VERSION_NUMBER` / `CONFIG_VERSION_CODE`（例如 `2026.12` / `r2`），同时把 `zzzz-custom` 里的 `VER_CODE` 改成一致，再重编译即可。

> **⚠️ 不要在源码根目录写 `version` 文件**（早期版本这么做过，已撤销）。`scripts/getver.sh` 会优先读它并改写全局 `REVISION`，连带影响 base-files 的 stamp 与包版本计算，实测会导致 `package/base-files` 编译失败、整个固件编不出来。同理，也**不要用 `files/` overlay 覆盖 `/usr/share/ucode/luci/version.uc`**（编译期多出 `usr/` 目录会改变 base-files 的安装输入）；这两件事都改由首次开机脚本在运行时处理。
>
> 另两个坑：① `CONFIG_VERSION_CODE` **不能留空**，留空会回退成 git hash；② 打开 `VERSIONOPT` 后 `VERSION_DIST` 的 Kconfig 默认值是 `ImmortalWrt`，所以 `CONFIG_VERSION_DIST="PonWrt"` 必须显式写，否则固件名会变成 `immortalwrt-` 开头。
>
> 局限：uci-defaults 只在首次开机 / 恢复出厂执行一次。若以后用 sysupgrade「保留配置」升级，新固件里 `%R` 的 hash 会回来（页面主显示仍干净）；想继续干净就重刷不保留配置，或 SSH 手动跑一遍那几行 sed。

---

## 六、使用方法

### 方式 A：一键脚本（推荐）

```bash
# 1. 装编译依赖（Ubuntu/Debian，官方推荐的一键脚本）
sudo bash -c 'bash <(curl -s https://build-scripts.immortalwrt.org/init_build_environment.sh)'

# 2. 拉源码
git clone https://github.com/pbs05/ponwrt.git
cd ponwrt

# 3. 把本文件夹整个放到源码根目录，执行
#    （假设本文件夹在 /workspace/ponwrt-040g-md）
cp -r /workspace/ponwrt-040g-md ./
chmod +x ponwrt-040g-md/build.sh
./ponwrt-040g-md/build.sh          # 想看详细日志用：V=s ./ponwrt-040g-md/build.sh
```

脚本依次完成：写 `feeds.conf` → `feeds update/install -a` → 写 `files/` → 基于 `configs/an7581.config` 生成 `.config`（并关掉其它机型，只编 XG-040G-MD）→ `make defconfig` → `make download` → `make -j$(nproc)`。

产物在 `bin/targets/airoha/an7581/`，浏览器打开 `http://192.168.100.1`，默认密码为空。

### 方式 B：手动 / 自建云编译

```bash
cat /workspace/ponwrt-040g-md/feeds.addon  >> feeds.conf      # 若无 feeds.conf 先 cp feeds.conf.default feeds.conf
./scripts/feeds update -a && ./scripts/feeds install -a
cp configs/an7581.config .config
cat /workspace/ponwrt-040g-md/config.addon >> .config
cp -r /workspace/ponwrt-040g-md/files ./                      # 首次启动脚本
# 再用 python/sed 改 config_generate 里的 192.168.1.1 -> 192.168.100.1
make defconfig && make -j$(nproc) download && make -j$(nproc)
```

> `.config` 里若有同名符号重复，手动方式请用 `config.addon` 里的值覆盖原值，或先删旧行再追加（一键脚本已自动处理）。

### 方式 C：GitHub Actions 云编译（已搭好）

仓库：**https://github.com/anjinghk/ponwrt-040g-md-build**
运行状态：**https://github.com/anjinghk/ponwrt-040g-md-build/actions**

- 公开仓库、Ubuntu 24.04 runner，单个 job 上限 **6 小时**，`JOBS=2`（2 核 / 7GB 内存，避免 OOM）。
- **两个独立 workflow**：`build.yml`（XG-040G-MD，tag `firmware-rN`）与 `build-hg5382a.yml`（HG5382A，tag `hg5382a-rN`）。并发组各自独立，互不取消。
- 修改 `config.addon` / `feeds.addon` / `files/` / `build.sh` / `patches/` 再 push 会**同时触发两台编译**；也可在 Actions 页单独点某台的 **Run workflow** 手动重跑。
- 编译流程：释放磁盘 → 装 76 个编译依赖 → 浅克隆 `pbs05/ponwrt` → 运行 `build.sh`（feeds / config / **SkyHigh 补丁（仅 MD）** / defconfig / download / make）→ 收集固件 → 发布各自 Release。
- 成功后**每台的 Release** 里下载对应固件（`*-squashfs-sysupgrade.itb` 升级、`*-initramfs-recovery.itb` 救砖）；Artifacts 分别为 `ponwrt-xg-040g-md-firmware` / `ponwrt-hg5382a-firmware`（保留 30 天）。
- 失败时直接看 Actions 网页日志，常见失败点：feeds 拉取超时、磁盘不足、上游源码快照变动、Vantage 主题与 SNAPSHOT 不兼容、关键包未被 defconfig 选中。
- **仓库里没有任何密钥**：workflow 使用 GitHub 自动注入的 `GITHUB_TOKEN`，推送用的 PAT 只存在于本地，不会写进仓库、日志或产物。

> 云编译通常要 1.5~3 小时/台，也可能因上游变动失败而需要看日志迭代。刷机前请核对固件机型（`nokia_xg-040g-md-ubi` 或 `fiberhome_hg5382a`），两台引导不通用。

---

## 七、需要留意的风险

> **HG5382A 刷机请以 pbs05/ponwrt 上游定义为准**：上游 profile 为 `fiberhome_hg5382a`，DTS `an7581-fiberhome-hg5382a.dts`，并行 NAND 8bit（DTSI `an7581-fiberhome-ubi-parts.dtsi`）。分区：前 128KiB 为 `bl2`，其余为一个 UBI 分区，内含 `fip` / `ubootenv` / `ubootenv2` / `factory` / `fit` 五个卷，rootfs 在 `fit` 卷（fitblk），升级包 `sysupgrade.itb`。2.5G LAN1 用 MaxLinear GPY211，光模块为 FiberHome BOSA。校准/MAC/PON SN 存于 `factory` 卷。上游官方刷机工具：引导 [AN758x U-Boot](https://github.com/pbs05/uboot-an758x)（HG5382A 是正式 target `hg5382a` / Parallel NAND，带中英文 Web 恢复页：上电约 1 秒后按住 Reset 进入，浏览器开 `http://192.168.0.1/`）+ 转 UBI 布局 [AN758x-Stock2UBI](https://github.com/pbs05/an758x-stock2ubi) + 校准转换 [FiberHome Factory](https://github.com/pbs05/fiberhome-factory)。**这些以源码为准，不要照搬 MD 的免拆流程**（两台引导不通用）。

> **⚠️ HG5382A 华邦闪存批次（重要，issue #21 实测）**：部分 HG5382A 用 Winbond **W29N02KVSIAF** 256MB 并行 NAND。原厂整片按 **8bit BCH** 编码；`uboot-an758x` v2026.07-3 起按 ONFI 标称改成 **4bit**，Stock2UBI 免拆写入的 BL2/FIP 是原厂内核写的 8bit 数据，通用 BL2 按 4bit 解码 → 大量 ECC 不可纠正、找不到 fip 卷 → **黑灯变砖**。到手先 telnet `dmesg | grep -i nand` 查闪存；华邦批次需用 xe5700 的 [uboot-an758x-winbond](https://github.com/xe5700/uboot-an758x-winbond) 临时 8bit 引导过渡再刷回官方；已黑灯只能拆机 TTL + XMODEM 救砖（主板 TX/RX 未标注，参考 [issue #21](https://github.com/pbs05/uboot-an758x/issues/21)）。普通批次按常规 uboot 流程即可。

1. **Vantage 兼容性**：官方标注支持 OpenWrt **25.12 / 24.10**，`Snapshots` 为「Untested」。PonWrt 是 ImmortalWrt master 的 SNAPSHOT（内核 6.18），能编译但没经过官方验证。若刷好后主题白屏，SSH 里执行
   `uci set luci.main.mediaurlbase=/luci-static/bootstrap; uci commit luci` 换回默认主题，或去掉 `CONFIG_PACKAGE_luci-theme-vantage` 重编。
2. **`luci-app-airoha-npu` 机型差异**：该插件原是给 Gemtek XR1710G / XG2010G 写的（同为 AN7581）。在 XG-040G-MD 上 NPU / PPE / 网口状态可用，但 WiFi、风扇等板块可能不适用或显示为空。
3. **`luci-app-vantage`（仪表盘）没装**：你只要了主题，主题可独立工作。若想要 dashboard，额外加
   `CONFIG_PACKAGE_luci-app-vantage=y` + `CONFIG_PACKAGE_luci-i18n-vantage-zh-cn=y`，并装上 `umdns`（可选，用于客户端名称）。
4. **刷机风险**：PonWrt 官方强调，刷写或修改 PON 参数可能导致无法注册光网络、丢失原厂校准/身份数据。刷前务必**完整备份原厂固件与校准分区**，并确认操作符合当地运营商规定。
5. `feeds update -a` 需要能访问 GitHub；国内网络建议先配好代理或镜像，否则容易超时中断。

---

## 七·补、网络唤醒用法（本次追加）

> IPTV 插件（原「服务 → IPTV」页面）已移除：其二层桥方案在联通 3300/4075 环境会出现机顶盒认证卡顿，实际 IPTV 改用独立脚本方案（组播口关 MAC 学习 + 静态钉网关 MAC），不在本固件插件清单内。

### 网络唤醒（WOL）

LuCI「服务 → 网络唤醒」，添加设备填名称 + MAC 地址，接口选 `br-lan`，点唤醒即发送魔术包。前提是**被唤醒设备**的网卡/BIOS 已开启 WoL、关机后网卡仍供电；路由器与它在同一二层网络。桥梁由 `etherwake` 提供。

---

## 七·补2、luci-app-upnp 两处上游 Bug 的编译期修复

`build.sh` 的 `[3.5/7]` 步对 feeds 源码做精准行级替换（改不到的会告警，便于发现版本差异）：

1. **活动端口映射列表空白**：miniupnpd 2.3.11 起在 nft DNAT 规则插入 `counter packets N bytes N`，2022 年写死的正则要求 `dport` 后紧跟 `dnat`，导致列表空白（上游 [issue #9214](https://github.com/openwrt/luci/issues/9214)，PR #9200/#9269 至今未合并）。修复：`luci.upnp` 正则的 `dport ([0-9]+)` 与 `dnat` 之间加 `.*`，兼容有/无 counter。
2. **description 存储型 XSS**：`upnp.js` 的 `s.render` 首次渲染把 `rule.descr` 裸字符串交给 `innerHTML`（CVE-2026-61875 漏补，[issue #9203](https://github.com/openwrt/luci/issues/9203)）。修复：该处改为 `'%h'.format(rule.descr)`；`poll_status` 那处上游已修，不动。

---

## 七·补3、iStore 应用商店（源码编译集成）

iStore（`luci-app-store`）**从源码编译进固件**，开机即用、无需联网安装：

- `build.sh` 的 `[2.5/7]` 步浅克隆 `kenzok8/small-package`，**只取 4 个包**：`luci-app-store`（本体）、`luci-lib-taskd`、`luci-lib-xterm`、`taskd`（依赖），不引入该仓库里几百个无关包。
- 修正 `luci-app-store/Makefile`：把 `LUCI_DEPENDS` 改为仅 `+luci-lib-taskd`、删除 `LUCI_EXTRA_DEPENDS`（原依赖 `libuci-lua`/`mount-utils` 在 PonWrt 精简树里没有，会导致 defconfig 静默剔除本体）。运行期真正需要的 `curl`/`taskd`/`luci-compat` 由 `config.addon` 显式选中。
- `build.sh` 有**硬校验**：`luci-app-store`/`miniupnpd-nftables`/`curl` 等关键包任一未被 defconfig 选中就立即中止，避免白编数小时后才发现没装全。

> 参考了 `zk6685/zk-vikingowrt` 的做法：只拷贝 iStore 相关的 4 个包，不把 small-package 的其他应用编进来。

---

## 八、文件清单

| 文件 | 用途 |
|---|---|
| `build.sh` | 一键编译脚本（`DEVICE` 环境变量切机型；feeds / config / iStore 源码集成 / UPnP 修复 / SkyHigh 补丁 / defconfig / download / make） |
| `feeds.addon` | 2 行第三方 feed（vantage、airoha） |
| `config.addon` | 追加到 `.config` 的完整符号（8 插件、依赖、中文、IP、版本号，含 omcproxy/iStore） |
| `files/etc/uci-defaults/zzzz-custom` | 首次开机设置 IP / 中文 / Vantage 主题 / 运行时去 git hash / DHCP force |
| `patches/971-mtd-spinand-skyhigh-premature-ready.patch` | SkyHigh SPI NAND 二次确认补丁（仅 MD 用，基于 6.18.60 内核，已实测干净应用） |
| `.github/workflows/build.yml` | XG-040G-MD 云编译 workflow（tag `firmware-rN`，含补丁与失败兜底） |
| `.github/workflows/build-hg5382a.yml` | HG5382A 云编译 workflow（tag `hg5382a-rN`，并行 NAND 不打补丁） |

> 注：`version.uc` 编译期 overlay 早已删除，改由 `zzzz-custom` 首次开机时生成，避免触发 `package/base-files` 编译失败。iStore 已从旧的「运行时安装」改为源码编译集成，旧的 `istore-reinstall.run` / `95-istore-auto-install` 两个文件已删除。

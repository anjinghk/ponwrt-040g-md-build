# PonWrt 固件编译配置（XG-040G-MD）

主线：[pbs05/ponwrt](https://github.com/pbs05/ponwrt)（基于 ImmortalWrt，Airoha AN7581/AN7583 PON 设备，包管理器为 **apk**）。
目标设备：**Nokia XG-040G-MD**（AN7581，profile `nokia_xg-040g-md-ubi`）。
管理地址：**192.168.100.1**；界面：**简体中文**；主题：**Vantage**。

> 你写的「md-040g-md」我按 **XG-040G-MD** 处理。如果你的机器其实是 AN7583 的 **XG-040G-MF**，请把脚本里的 `configs/an7581.config` 换成 `configs/an7583.config`、`PROFILE` 换成 `nokia_xg-040g-mf-ubi`，其余不变。

---

## 一、插件去重与改名结果

你给的清单里有 1 个重复、1 个笔误，处理后是 **1 个主题 + 6 个应用**：

| # | 你写的 | 处理结果 | 来源 |
|---|---|---|---|
| 1 | `luci-theme-vantage` | 保留 | 第三方 feed `anothaDev/luci-theme-vantage` |
| 2 | `luci-app-package-manager` | **保留 1 次**（你写了 2 次）；且官方 `configs/an7581.config` 默认已启用 | ImmortalWrt `luci` feed |
| 3 | `luci-app-upnp` | 保留 | ImmortalWrt `luci` feed |
| 4 | `luci-app-autoreboot` | 保留 | ImmortalWrt `luci` feed |
| 5 | `luci-app-ttyd` | 保留 | ImmortalWrt `luci` feed |
| 6 | `luci-app-natmapt` | **改为 `luci-app-natmap`**（不带尾部 t，原名字的包不存在） | ImmortalWrt `luci` feed |
| 7 | `luci-app-airoha-npu` | 保留 | 第三方 feed `naoki66/luci-app-airoha` |

其余 4 个应用（package-manager / upnp / autoreboot / ttyd / natmap）在 PonWrt 自带的 `luci` 与 `packages` feed 里都有，**不需要另外加源**；只有主题和 airoha-npu 需要加 2 个 `src-git` 源（见 `feeds.addon`）。

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
| `luci-app-natmap` | **`natmap`** | NATMAP 本体 |
| `luci-app-airoha-npu` | **`kmod-br-netfilter`**、`CONFIG_KERNEL_DEVMEM`、busybox `devmem`、`rpcd` | 读 AN7581 NPU/PPE 寄存器必须有 `/dev/mem` + `devmem`；默认 config 里 `kmod-br-netfilter` 是关的，已补 |

另外 `rpcd`、`rpcd-mod-ucode`、`rpcd-mod-file` 等官方配置里已经带上了。

---

## 三、中文怎么保证

- 7 个插件**全部有简体中文翻译**（`po/zh_Hans`），共启用 10 个 `luci-i18n-*-zh-cn` 包：
  `base`、`firewall`、`package-manager`、`pon`（这 4 个官方 config 已带）＋
  `upnp`、`autoreboot`、`ttyd`、`natmap`、`airoha-npu`、`vantage-theme`（新增）。
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

主线默认编译出来是 `PonWrt SNAPSHOT r0-d9dd3a4 / LuCI Master (git-…)`，后面两段都是 git hash。本配置把它固定成：

> **`PonWrt 2026.11 r1 / LuCI release`**

LuCI「状态 → 概览 → 固件版本」显示上面这行；`ubus call system board`、`cat /etc/os-release` 里也不再有 hash。固件文件名同步变成 `ponwrt-2026.11-r1-airoha-an7581-nokia_xg-040g-md-ubi-squashfs-sysupgrade.itb`。

| 位置 | 作用 |
|---|---|
| `config.addon` 的 `CONFIG_VERSIONOPT` 段 | `VERSION_NUMBER=2026.11`、`VERSION_CODE=r1`；`VERSION_FILENAMES` / `VERSION_CODE_FILENAMES` 让固件文件名自动带版本 |
| `build.sh` 写源码根目录的 `version` 文件 | `scripts/getver.sh` 优先读它，覆盖 `REVISION`，清掉 `BUILD_ID` / `DISTRIB_REVISION` 里的 hash |
| `files/usr/share/ucode/luci/version.uc` | 覆盖 LuCI 自带版本模块，把 `LuCI Master (git-…)` 改成 `LuCI release` |

**以后想改**：只改 `config.addon` 里 `CONFIG_VERSION_NUMBER` 与 `CONFIG_VERSION_CODE` 两行（例如 `2026.12` / `r2`）再重编译即可。`version` 文件由 `build.sh` 自动跟着 `CONFIG_VERSION_CODE` 变，文件名和 `/etc/os-release` 同步更新。

> 两个坑：① `CONFIG_VERSION_CODE` **不能留空**，留空会回退成 git hash；② 打开 `VERSIONOPT` 后 `VERSION_DIST` 的 Kconfig 默认值是 `ImmortalWrt`，所以 `CONFIG_VERSION_DIST="PonWrt"` 必须显式写，否则固件名会变成 `immortalwrt-` 开头。
>
> 若覆盖 `version.uc` 后 LuCI 出现异常，删掉 `files/usr/share/ucode/luci/version.uc` 重编即可回退。

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
- 首次推送已自动触发一次编译；之后修改 `config.addon` / `feeds.addon` / `files/` / `build.sh` 再 push 会自动重编；也可以在 Actions 页点 **Run workflow** 手动重跑并指定并行数 / 是否输出详细日志。
- 编译流程：释放磁盘 → 装 76 个编译依赖 → 浅克隆 `pbs05/ponwrt` → 运行 `build.sh`（feeds / config / defconfig / download / make）→ 收集固件。
- 成功后在该次运行的 **Artifacts** 下载 `ponwrt-xg-040g-md-firmware`（zip，保留 30 天），运行摘要里会列出文件名与大小。
- 失败时直接看 Actions 网页日志（GitHub 自动保存完整输出），常见失败点：feeds 拉取超时、磁盘不足、上游源码快照变动、Vantage 主题与 SNAPSHOT 不兼容。
- **仓库里没有任何密钥**：workflow 使用 GitHub 自动注入的 `GITHUB_TOKEN`，推送用的 PAT 只存在于本地，不会写进仓库、日志或产物。

> 云编译通常要 2~5 小时，也可能因上游变动失败而需要看日志迭代，不保证一次成功。刷机前请核对固件型号为 `nokia_xg-040g-md-ubi`。

---

## 七、需要留意的风险

1. **Vantage 兼容性**：官方标注支持 OpenWrt **25.12 / 24.10**，`Snapshots` 为「Untested」。PonWrt 是 ImmortalWrt master 的 SNAPSHOT（内核 6.18），能编译但没经过官方验证。若刷好后主题白屏，SSH 里执行
   `uci set luci.main.mediaurlbase=/luci-static/bootstrap; uci commit luci` 换回默认主题，或去掉 `CONFIG_PACKAGE_luci-theme-vantage` 重编。
2. **`luci-app-airoha-npu` 机型差异**：该插件原是给 Gemtek XR1710G / XG2010G 写的（同为 AN7581）。在 XG-040G-MD 上 NPU / PPE / 网口状态可用，但 WiFi、风扇等板块可能不适用或显示为空。
3. **`luci-app-vantage`（仪表盘）没装**：你只要了主题，主题可独立工作。若想要 dashboard，额外加
   `CONFIG_PACKAGE_luci-app-vantage=y` + `CONFIG_PACKAGE_luci-i18n-vantage-zh-cn=y`，并装上 `umdns`（可选，用于客户端名称）。
4. **刷机风险**：PonWrt 官方强调，刷写或修改 PON 参数可能导致无法注册光网络、丢失原厂校准/身份数据。刷前务必**完整备份原厂固件与校准分区**，并确认操作符合当地运营商规定。
5. `feeds update -a` 需要能访问 GitHub；国内网络建议先配好代理或镜像，否则容易超时中断。

---

## 八、文件清单

| 文件 | 用途 |
|---|---|
| `build.sh` | 一键编译脚本（feeds / config / files / defconfig / download / make） |
| `feeds.addon` | 2 行第三方 feed（vantage、airoha） |
| `config.addon` | 追加到 `.config` 的完整符号（插件、依赖、中文、IP、版本号） |
| `files/etc/uci-defaults/zzzz-custom` | 首次开机设置 IP / 中文 / Vantage 主题 |
| `files/usr/share/ucode/luci/version.uc` | 覆盖 LuCI 版本显示，去掉 git hash |
| `.github/workflows/build.yml` | GitHub Actions 云编译 workflow |

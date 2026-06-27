#!/bin/bash

# 1. 首先更新和安装 feeds，确保后续操作的依赖可用
./scripts/feeds update -a
./scripts/feeds install -a

# 2. 移除要替换的包 (请确保这些路径在你的源码中存在，通常位于 feeds/packages 或 feeds/luci)
# 如果路径变更，rm -rf 命令不会报错，但后续的 git clone 会覆盖
rm -rf feeds/packages/net/mosdns
rm -rf feeds/packages/net/msd_lite
rm -rf feeds/packages/net/smartdns
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-mosdns
rm -rf feeds/luci/applications/luci-app-netdata

# 3. 定义 Git 稀疏克隆函数 (修复了原函数的逻辑)
# 参数: 分支名 仓库URL 要克隆的目录1 [目录2...]
function git_sparse_clone() {
  local branch="$1"
  local repourl="$2"
  shift 2
  local temp_dir="temp_git_clone"
  
  # 克隆仓库到临时目录
  git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl" "$temp_dir"
  
  # 进入临时目录并设置稀疏检出
  cd "$temp_dir" || exit 1
  git sparse-checkout set "$@"
  
  # 将指定目录移动到 package 目录
  mv -f "$@" ../package/
  
  # 返回上级目录并清理
  cd ..
  rm -rf "$temp_dir"
}

# 4. 添加额外插件

# Netdata (Jason6111 的汉化版)
git clone --depth=1 https://github.com/Jason6111/luci-app-netdata package/luci-app-netdata

# msd_lite (使用 ximiTech 的源)
git clone --depth=1 https://github.com/ximiTech/luci-app-msd_lite package/luci-app-msd_lite
git clone --depth=1 https://github.com/ximiTech/msd_lite package/msd_lite

# MosDNS (sbwml 的 v5 版本，根据文档推荐)
# 注意: 这可能会比较大，如果不需要可注释
# git clone --depth=1 https://github.com/sbwml/luci-app-mosdns -b v5 package/luci-app-mosdns

# Alist (sbwml 的源，注意该项目可能已归档，但代码仍可用)
# 如果你遇到克隆错误，可以尝试使用归档后的镜像或替换为其他文件管理插件
git clone --depth=1 https://github.com/sbwml/luci-app-alist package/luci-app-alist

# iStore (如果你需要应用商店)
# git_sparse_clone main https://github.com/linkease/istore-ui app-store-ui
# git_sparse_clone main https://github.com/linkease/istore luci

# Themes
# Argon 主题 (推荐使用 jerrykuku 的官方源，支持新版)
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config

# Opentomcat 主题
git_sparse_clone main https://github.com/haiibo/packages luci-theme-opentomcat

# 晶晨宝盒 (Amlogic)
git_sparse_clone main https://github.com/ophub/luci-app-amlogic luci-app-amlogic
# 修改固件下载源为 haiibo (如果你使用的是 haiibo 的内核)
sed -i "s|firmware_repo.*|firmware_repo 'https://github.com/haiibo/OpenWrt'|g" package/luci-app-amlogic/root/etc/config/amlogic
sed -i "s|ARMv8|ARMv8_MINI|g" package/luci-app-amlogic/root/etc/config/amlogic

# SmartDNS (pymumu 的源)
# git clone --depth=1 https://github.com/pymumu/luci-app-smartdns package/luci-app-smartdns
# git clone --depth=1 https://github.com/pymumu/openwrt-smartdns package/smartdns

# 5. 系统配置与修复

# 修改默认IP
sed -i 's/192.168.1.1/192.168.30.254/g' package/base-files/files/bin/config_generate

# 更改默认 Shell 为 zsh (确保已安装 zsh)
# sed -i 's/\/bin\/ash/\/usr\/bin\/zsh/g' package/base-files/files/etc/passwd

# TTYD 免登录
sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config

# 修改本地时间格式 (适用于 ImmortalWrt/OpenWrt 24.10)
# 如果 package/lean 不存在，尝试直接修改 base-files 或 autocore
# 这里尝试修改通用的 autocore 路径
find package/ -path "*/autocore/files/*/index.htm" -exec sed -i 's/os.date()/os.date("%a %Y-%m-%d %H:%M:%S")/g' {} \;

# 修改版本为编译日期
# 由于 lean 目录不存在，我们修改默认设置文件，通常位于 package/base-files 或直接在 files 下
# 这里尝试通用路径，如果报错请检查具体路径
if [ -f "package/lean/default-settings/files/zzz-default-settings" ]; then
    date_version=$(date +"%y.%m.%d")
    sed -i "s/DISTRIB_REVISION=.*/DISTRIB_REVISION='R${date_version} by Haiibo'/g" package/lean/default-settings/files/zzz-default-settings
fi

# 修复 hostapd 报错
# 确保目标目录存在
mkdir -p package/network/services/hostapd/patches
cp -f "$GITHUB_WORKSPACE/scripts/011-fix-mbo-modules-build.patch" package/network/services/hostapd/patches/011-fix-mbo-modules-build.patch 2>/dev/null || echo "Warning: 011-fix-mbo-modules-build.patch not found, skipping."

# 修复 armv8 设备 xfsprogs 报错
# 路径可能在 feeds/packages/utils/xfsprogs
if [ -f "feeds/packages/utils/xfsprogs/Makefile" ]; then
  sed -i 's/TARGET_CFLAGS.*/TARGET_CFLAGS += -DHAVE_MAP_SYNC -D_LARGEFILE64_SOURCE/g' feeds/packages/utils/xfsprogs/Makefile
fi

# 取消主题默认设置 (修复路径)
find package/luci-theme-* -type f -name "*.mk" -exec sed -i '/set luci.main.mediaurlbase/d' {} \;

# 调整 Docker 和 ZeroTier 菜单 (取消注释并修复路径)
# Docker
if [ -d "feeds/luci/applications/luci-app-dockerman" ]; then
  sed -i 's/"admin"/"admin", "services"/g' feeds/luci/applications/luci-app-dockerman/luasrc/controller/*.lua
  sed -i 's/"admin"/"admin", "services"/g; s/admin\//admin\/services\//g' feeds/luci/applications/luci-app-dockerman/luasrc/model/cbi/dockerman/*.lua
  sed -i 's/admin\//admin\/services\//g' feeds/luci/applications/luci-app-dockerman/luasrc/view/dockerman/*.htm
  sed -i 's|admin\\|admin\\/services\\|g' feeds/luci/applications/luci-app-dockerman/luasrc/view/dockerman/container.htm
fi

# ZeroTier
if [ -d "feeds/luci/applications/luci-app-zerotier" ]; then
  sed -i 's/vpn/services/g; s/VPN/Services/g' feeds/luci/applications/luci-app-zerotier/luasrc/controller/zerotier.lua
  sed -i 's/vpn/services/g' feeds/luci/applications/luci-app-zerotier/luasrc/view/zerotier/zerotier_status.htm
fi

# 6. 再次运行 feeds install 以确保所有新添加的包都被识别
./scripts/feeds update -a
./scripts/feeds install -a

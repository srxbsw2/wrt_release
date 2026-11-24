#!/usr/bin/env bash
# 系统默认设置、主题依赖与 Wi-Fi 初始化修正。

fix_default_set() {
    # 替换默认主题依赖，并注入系统设置和目标平台通用补丁。
    if [ -d "$BUILD_DIR/feeds/luci/collections/" ]; then
        find "$BUILD_DIR/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$THEME_SET/g" {} \;
    fi

    install -Dm544 "$BASE_PATH/patches/991_custom_settings" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/991_custom_settings"
    local wifi_defaults_path="$BUILD_DIR/package/base-files/files/etc/uci-defaults/992_set-wifi-uci.sh"
    if is_vikingyfy_owrt_build; then
        local wifi_detect_path="$BUILD_DIR/package/network/config/wifi-scripts/files/etc/hotplug.d/ieee80211/10-wifi-detect"
        local wifi_hook="/usr/libexec/992_set-wifi-uci.sh --hotplug"
        local wifi_retry="ubus call network.wireless retry"
        local wifi_config_count

        if [[ ! -f "$wifi_detect_path" ]]; then
            echo "错误：VIKINGYFY owrt 缺少预期的 IEEE 802.11 热插拔脚本：$wifi_detect_path" >&2
            return 1
        fi

        # 上游有两种形态：旧版为 /sbin/wifi config 与 retry 各一行；
        # wifi-scripts r22 起 retry 移入 mac80211.uc 的 --hotplug 分支，只剩一行内联调用。
        wifi_config_count=$(grep -Ec '^[[:space:]]*[^#]*/sbin/wifi config([[:space:]]|$)' "$wifi_detect_path" || true)
        if [[ "$wifi_config_count" != "1" ]]; then
            echo "错误：VIKINGYFY owrt 的 IEEE 802.11 热插拔流程与预期不符（检测到 ${wifi_config_count} 处 /sbin/wifi config），拒绝安装早期 Wi-Fi 默认值。" >&2
            return 1
        fi

        install -Dm755 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$BUILD_DIR/package/base-files/files/usr/libexec/992_set-wifi-uci.sh"
        rm -f "$wifi_defaults_path"

        # 幂等：先剥离旧钩子，再按上游当前形态重新挂载
        sed -E -i 's@ \&\& /usr/libexec/992_set-wifi-uci\.sh --hotplug \&\& ubus call network\.wireless retry@@' "$wifi_detect_path"
        sed -E -i '\|^[[:space:]]*/usr/libexec/992_set-wifi-uci\.sh --hotplug[[:space:]]*$|d' "$wifi_detect_path"

        if grep -Eq "^[[:space:]]*${wifi_retry}\$" "$wifi_detect_path"; then
            # 旧形态：钩子插在配置生成与 retry 之间
            sed -E -i '/^[[:space:]]*[^#]*\/sbin\/wifi config([[:space:]]|$)/a\    /usr/libexec/992_set-wifi-uci.sh --hotplug' "$wifi_detect_path"
        else
            # 新形态：钩子与一次 retry 追加到 wifi config 同行，沿用 add 事件的 && 条件
            sed -E -i 's@^([[:space:]]*[^#]*\/sbin\/wifi config.*)$@\1 \&\& /usr/libexec/992_set-wifi-uci.sh --hotplug \&\& ubus call network.wireless retry@' "$wifi_detect_path"
        fi

        if ! awk -v cfg="/sbin/wifi config" -v hook="$wifi_hook" -v retry="$wifi_retry" '
        {
            line = $0
            sub(/#.*/, "", line)
            while (1) {
                c = index(line, cfg); h = index(line, hook); r = index(line, retry)
                pos = 0; tok = ""; len = 0
                if (c && (!pos || c < pos)) { pos = c; tok = "C"; len = length(cfg) }
                if (h && (!pos || h < pos)) { pos = h; tok = "H"; len = length(hook) }
                if (r && (!pos || r < pos)) { pos = r; tok = "R"; len = length(retry) }
                if (!pos) break
                seq = seq tok
                line = substr(line, pos + len)
            }
        }
        END { exit (seq == "CHR" ? 0 : 1) }
        ' "$wifi_detect_path"; then
            echo "错误：VIKINGYFY Wi-Fi 初始化钩子没有位于配置生成与无线 retry 之间。" >&2
            return 1
        fi
    else
        install -Dm544 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$wifi_defaults_path"
    fi

    if [ -f "$BUILD_DIR/package/emortal/autocore/files/tempinfo" ]; then
        if [ -f "$BASE_PATH/patches/tempinfo" ]; then
            \cp -f "$BASE_PATH/patches/tempinfo" "$BUILD_DIR/package/emortal/autocore/files/tempinfo"
        fi
    fi
}

#!/bin/bash
# 适配 W6180：基于小米 CR6606 DTS，修改为 SPI NOR 闪存，调整 LED 和网络端口
set -e
set -x

DTS_FILE="target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606.dts"
MK_FILE="target/linux/ramips/image/mt7621.mk"

[ -f "$DTS_FILE" ] || { echo "DTS文件不存在"; exit 1; }
[ -f "$MK_FILE" ] || { echo "MK文件不存在"; exit 1; }

# ========== 1. 生成适配 W6180 的 DTS ==========
cat > "$DTS_FILE" << 'EOF'
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
/dts-v1/;

#include "mt7621.dtsi"
#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>

/ {
	compatible = "xiaomi,mi-router-cr6606", "mediatek,mt7621-soc";
	model = "Maiwardi W6180";

	aliases {
		led-boot = &led_power;
		led-failsafe = &led_power;
		led-running = &led_power;
		led-upgrade = &led_power;
		label-mac-device = &gmac0;
	};

	chosen {
		bootargs = "console=ttyS0,115200n8 root=/dev/root rootfstype=squashfs,jffs2";
	};

	leds {
		compatible = "gpio-leds";

		led_power: power {
			label = "power";
			gpios = <&gpio 14 GPIO_ACTIVE_LOW>;   // 请根据实际硬件修改 GPIO 号
		};
		led_wan: wan {
			label = "wan";
			gpios = <&gpio 16 GPIO_ACTIVE_LOW>;    // 请根据实际硬件修改 GPIO 号
		};
		led_2g: 2g {
			label = "2.4g";
			gpios = <&gpio 13 GPIO_ACTIVE_LOW>;    // 请根据实际硬件修改 GPIO 号
		};
		led_5g: 5g {
			label = "5g";
			gpios = <&gpio 15 GPIO_ACTIVE_LOW>;    // 请根据实际硬件修改 GPIO 号
		};
	};

	keys {
		compatible = "gpio-keys";
		reset {
			label = "reset";
			gpios = <&gpio 8 GPIO_ACTIVE_LOW>;
			linux,code = <KEY_RESTART>;
		};
		/* W6180 无独立 WPS 键，移除 */
	};
};

&nand {
	status = "disabled";
};

&spi0 {
	status = "okay";

	flash@0 {
		compatible = "jedec,spi-nor";
		reg = <0>;
		spi-max-frequency = <50000000>;

		partitions {
			compatible = "fixed-partitions";
			#address-cells = <1>;
			#size-cells = <1>;

			partition@0 {
				label = "u-boot";
				reg = <0x000000 0x030000>;
				read-only;
			};
			partition@30000 {
				label = "env";
				reg = <0x030000 0x010000>;
			};
			partition@40000 {
				label = "factory";
				reg = <0x040000 0x010000>;
				read-only;
				nvmem-layout {
					compatible = "fixed-layout";
					#address-cells = <1>;
					#size-cells = <1>;
					eeprom_factory_0: eeprom@0 {
						reg = <0x0 0xe00>;
					};
					macaddr_factory_0: macaddr@4 {
						reg = <0x4 0x6>;
					};
					macaddr_factory_8000: macaddr@8000 {
						reg = <0x8000 0x6>;
					};
				};
			};
			partition@50000 {
				label = "firmware";
				reg = <0x050000 0x1fb0000>;
				compatible = "openwrt,firmware";
				linux,rootfs;   // 明确标记为 rootfs，辅助内核识别
			};
		};
	};
};

&gmac0 {
	nvmem-cells = <&macaddr_factory_0>;
	nvmem-cell-names = "mac-address";
};

&gmac1 {
	nvmem-cells = <&macaddr_factory_8000>;
	nvmem-cell-names = "mac-address";
};

&pcie {
	status = "okay";
};

&pcie1 {
	wifi@0,0 {
		compatible = "mediatek,mt76";
		reg = <0x0000 0 0 0 0>;
		nvmem-cells = <&eeprom_factory_0>;
		nvmem-cell-names = "eeprom";
		mediatek,disable-radar-background;
	};
};

&gmac0 {
	status = "okay";
};

/* 交换机：1 WAN + 2 LAN */
&switch0 {
	ports {
		port@0 {
			status = "okay";
			label = "wan";
		};
		port@1 {
			status = "okay";
			label = "lan1";
		};
		port@2 {
			status = "okay";
			label = "lan2";
		};
		port@3 {
			status = "disabled";
		};
	};
};

&state_default {
	gpio {
		groups = "jtag", "uart3", "wdt";
		function = "gpio";
	};
};
EOF

# ========== 2. 添加设备定义到 mt7621.mk ==========
if ! grep -q "Device/w6180" "$MK_FILE"; then
    echo "" >> "$MK_FILE"
    echo "define Device/w6180" >> "$MK_FILE"
    echo "  DEVICE_VENDOR := Maiwardi" >> "$MK_FILE"
    echo "  DEVICE_MODEL := W6180" >> "$MK_FILE"
    echo "  DEVICE_DTS := mt7621_xiaomi_mi-router-cr6606" >> "$MK_FILE"
    echo "  DEVICE_PACKAGES := kmod-mt76-connac mt76da-firmware mtk-wifi-da" >> "$MK_FILE"
    echo "  IMAGE_SIZE := 32448k" >> "$MK_FILE"
    echo "endef" >> "$MK_FILE"
    echo "TARGET_DEVICES += w6180" >> "$MK_FILE"
fi

# ========== 3. 修改系统默认配置（时区、主机名等） ==========
# 修正路径：package/base-files/files/bin/config_generate
sed -i 's/OpenWrt/W6180-MT7621/g' package/base-files/files/bin/config_generate
sed -i 's/UTC/CST-8/g' package/base-files/files/bin/config_generate
sed -i 's/00:00:00/08:00:00/g' package/base-files/files/bin/config_generate

[ -f feeds/luci/modules/luci-base/root/etc/config_generate ] && \
    sed -i 's/luci.i18n.en/luci.i18n.zh-cn/g' feeds/luci/modules/luci-base/root/etc/config_generate

# ========== 4. 先生成默认 .config，再强制追加 MTD split 选项 ==========
make defconfig

# 追加必要的 MTD split 选项（确保它们不被 defconfig 覆盖）
echo "CONFIG_MTD_SPLIT_SUPPORT=y" >> .config
echo "CONFIG_MTD_SPLIT_FIRMWARE=y" >> .config
echo "CONFIG_MTD_SPLIT_UIMAGE_FW=y" >> .config
echo "CONFIG_MTD_BLOCK=y" >> .config

# 处理依赖，让内核确认这些选项有效
make oldconfig

echo "diy-part2.sh 执行完毕。"

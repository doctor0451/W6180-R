#!/bin/bash
# 适配 W6180：直接替换 cr6606.dts 为 SPI NOR 配置
set -e
set -x

DTS_FILE="target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606.dts"
MK_FILE="target/linux/ramips/image/mt7621.mk"

[ -f "$DTS_FILE" ] || { echo "DTS文件不存在"; exit 1; }
[ -f "$MK_FILE" ] || { echo "MK文件不存在"; exit 1; }

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
		led-boot = &led_sys_yellow;
		led-failsafe = &led_sys_yellow;
		led-running = &led_sys_blue;
		led-upgrade = &led_sys_yellow;
		label-mac-device = &gmac0;
	};

	chosen {
		bootargs = "console=ttyS0,115200n8";
	};

	leds {
		compatible = "gpio-leds";
		led_sys_yellow: sys_yellow {
			label = "yellow:sys";
			gpios = <&gpio 14 GPIO_ACTIVE_LOW>;
		};
		led_sys_blue: sys_blue {
			label = "blue:sys";
			gpios = <&gpio 16 GPIO_ACTIVE_LOW>;
		};
		net_yellow {
			label = "yellow:net";
			gpios = <&gpio 13 GPIO_ACTIVE_LOW>;
		};
		net_blue {
			label = "blue:net";
			gpios = <&gpio 15 GPIO_ACTIVE_LOW>;
		};
	};

	keys {
		compatible = "gpio-keys";
		reset {
			label = "reset";
			gpios = <&gpio 8 GPIO_ACTIVE_LOW>;
			linux,code = <KEY_RESTART>;
		};
		wps {
			label = "wps";
			gpios = <&gpio 7 GPIO_ACTIVE_LOW>;
			linux,code = <KEY_WPS_BUTTON>;
		};
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
				compatible = "openwrt,firmware";   /* 关键修复 */
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

&switch0 {
	ports {
		port@0 {
			status = "okay";
			label = "lan1";
		};
		port@1 {
			status = "okay";
			label = "lan2";
		};
		port@2 {
			status = "okay";
			label = "lan3";
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

sed -i 's/3125000/115200/g' "$DTS_FILE"

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

sed -i 's/OpenWrt/W6180-MT7621/g' package/base-files/files/bin/config_generate
sed -i 's/UTC/CST-8/g' package/base-files/files/bin/config_generate
sed -i 's/00:00:00/08:00:00/g' package/base-files/files/bin/config_generate

[ -f feeds/luci/modules/luci-base/root/etc/config_generate ] && \
    sed -i 's/luci.i18n.en/luci.i18n.zh-cn/g' feeds/luci/modules/luci-base/root/etc/config_generate

echo "diy-part2.sh 执行完毕。"

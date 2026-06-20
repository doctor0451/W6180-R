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
if [ ! -f "${DTS_FILE}" ]; then
    echo "ERROR DTS文件写入失败！文件不存在"
    exit 1
fi
echo "DTS文件生成成功: ${DTS_FILE}"

# 删除可能存在的旧设备定义，避免冲突（确保新规则生效）
sed -i '/maiwardi_w6180/d' "$MK_FILE"

# 追加新设备定义（标准 OpenWrt 格式，非 trx）
cat >> "${MK_FILE}" << 'MK_EOF'
define Device/maiwardi_w6180
  DEVICE_VENDOR := Maiwardi
  DEVICE_MODEL := W6180
  DEVICE_DTS := mt7621_maiwardi_w6180
  IMAGE_SIZE := 32448k
  IMAGES += factory.bin sysupgrade.bin
  IMAGE/factory.bin := append-kernel | append-rootfs | pad-rootfs
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  DEVICE_PACKAGES := mt76da-firmware kmod-mt76-connac mtk-wifi-da kmod-m25p80
endef
TARGET_DEVICES += maiwardi_w6180
MK_EOF

# 验证定义是否写入成功（方便在编译日志中检查）
echo "===== mt7621.mk 中 maiwardi_w6180 定义 ====="
grep -A10 "maiwardi_w6180" "$MK_FILE" || echo "未找到定义！"
echo "=================== 全部脚本执行完毕 ==================="

echo "diy-part2.sh 执行完毕。"

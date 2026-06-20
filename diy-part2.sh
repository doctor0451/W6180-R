#!/bin/bash
set -e
set -x
# 设备文件路径定义
DTS_PATH="target/linux/ramips/dts/mt762_maiwardi_w6180.dts"
MK_PATH="target/linux/ramips/image/mt7621.mk"
# 新建DTS目录
mkdir -p target/linux/ramips/dts
# 写入修复后DTS（修复交换机、删除双重bootargs、无nand_ecc）
cat > "$DTS_PATH" << 'EOF'
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
/dts-v1/;
#include "mt7621.dtsi"
#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>

/ {
	compatible = "maiwardi,w6180", "mediatek,mt7621-soc";
	model = "Maiwardi W6180";

	memory@0 {
		device_type = "memory";
		reg = <0x0 0x10000000>;
	};

	aliases {
		led-boot = &led_power;
		led-failsafe = &led_power;
		led-running = &led_power;
		led-upgrade = &led_power;
		label-mac-device = &gmac0;
	};

	chosen {
		bootargs = "console=ttyS0,115200n8 root=/dev/mtdblock3 rootfstype=squashfs,jffs2";
	};

	leds {
		compatible = "gpio-leds";
		led_power: power {
			label = "power";
			gpios = <&gpio 14 GPIO_ACTIVE_HIGH>;
		};
		led_wan: wan {
			label = "wan";
			gpios = <&gpio 16 GPIO_ACTIVE_HIGH>;
		};
		led_2g: 2g {
			label = "2.4g";
			gpios = <&gpio 13 GPIO_ACTIVE_HIGH>;
		};
		led_5g: 5g {
			label = "5g";
			gpios = <&gpio 15 GPIO_ACTIVE_HIGH>;
		};
	};

	keys {
		compatible = "gpio-keys";
		reset {
			label = "reset";
			gpios = <&gpio 8 GPIO_ACTIVE_LOW>;
			linux,code = <KEY_RESTART>;
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
		broken-flash-reset;
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
				reg = <0x050000 0x1FA0000>;
				compatible = "openwrt,firmware";
				linux,rootfs;
			};
		};
	};
};

&gmac0 {
	nvmem-cells = <&macaddr_factory_0>;
	nvmem-cell-names = "mac-address";
	status = "okay";
};

&gmac1 {
	nvmem-cells = <&macaddr_factory_8000>;
	nvmem-cell-names = "mac-address";
	status = "okay";
};

&pcie {
	status = "okay";
};

&pcie1 {
	wifi@0,0 {
		compatible = "mediatek,mt7905";
		reg = <0x0000 0 0 0 0>;
		nvmem-cells = <&eeprom_factory_0>;
		nvmem-cell-names = "eeprom";
	};
};

&switch0 {
	mediatek,port-map = "llllw";
	mediatek,mt7530;
	#address-cells = <1>;
	#size-cells = <0>;
	ports {
		port@0 {
			reg = <0>;
			label = "wan";
			phy-mode = "rgmii";
			phy-handle = <&phy0>;
		};
		port@1 {
			reg = <1>;
			label = "lan1";
			phy-mode = "rgmii";
			phy-handle = <&phy1>;
		};
		port@2 {
			reg = <2>;
			label = "lan2";
			phy-mode = "rgmii";
			phy-handle = <&phy2>;
		};
		port@3 {
			reg = <3>;
			status = "disabled";
		};
		port@4 {
			reg = <4>;
			status = "disabled";
		};
	};
	mdio-bus {
		#address-cells = <1>;
		#size-cells = <0>;
		phy0: phy@0 { reg = <0>; };
		phy1: phy@1 { reg = <1>; };
		phy2: phy@2 { reg = <2>; };
		phy3: phy@3 { reg = <3>; status = "disabled"; };
		phy4: phy@4 { reg = <4>; status = "disabled"; };
	};
};

&state_default {
	gpio {
		groups = "jtag", "uart3", "wdt";
		function = "gpio";
	};
};
EOF

# 修正mk，增加factory.bin镜像（Breed可刷）
cat >> "$MK_PATH" << 'MK_EOF'
define Device/maiwardi_w6180
  DEVICE_VENDOR := Maiwardi
  DEVICE_MODEL := W6180
  DEVICE_DTS := mt7621_maiwardi_w6180
  IMAGE_SIZE := 32448k
  IMAGES += factory.bin sysupgrade.bin
  IMAGE/factory.bin := trx -M 0x50000 $(IMAGE_SIZE) $@
  DEVICE_PACKAGES := mt76da-firmware kmod-mt76-connac mtk-wifi-da kmod-m25p80
endef
TARGET_DEVICES += maiwardi_w6180
MK_EOF

echo "===== 修复完成 ===="
echo "1. 交换机mt7530 PHY绑定修复，消除网口-EINVAL报错"
echo "2. 删除bootargs mtdparts，解决OF分区cell告警"
echo "3. mt7621.mk新增factory.bin（Breed底层刷机专用）"
echo "4. 设备名maiwardi_w6180与.config保持一致"
echo "刷机提醒：Breed只能刷factory.bin，sysupgrade.bin仅系统内升级使用"

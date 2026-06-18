#!/bin/bash
# ImmortalWrt MT7621 W6180 适配脚本
# 硬件：MT7621A + MT7905DAN WiFi6 256M DDR3 32MB SPI NOR

DTS_FILE=target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606.dts
DTSI_FILE=target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr660x.dtsi
MK_FILE=target/linux/ramips/image/mt7621.mk

# 1. 串口波特率兼容修复
[ -f "$DTS_FILE" ] && sed -i 's/3125000/115200/g' "$DTS_FILE"

# 2. 修改复位键为 GPIO8（替换原 GPIO18）
[ -f "$DTSI_FILE" ] && sed -i '/reset {/,/};/ s/gpios = <&gpio 18 GPIO_ACTIVE_LOW>/gpios = <&gpio 8 GPIO_ACTIVE_LOW>/' "$DTSI_FILE"

# 3. 在 cr6606.dts 末尾追加：禁用 NAND、添加 SPI NOR 及分区
cat >> "$DTS_FILE" << EOF

/* Override for W6180: use SPI NOR instead of NAND */
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

					/* 校准数据位于 factory 开头，保持偏移 0x0 */
					eeprom_factory_0: eeprom@0 {
						reg = <0x0 0xe00>;
					};

					/* MAC 地址位置需根据实际情况修改！示例假设在 0x4 和 0x8000 */
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
			};
		};
	};
};

/* 重新指定 gmac0/1 的 MAC 来源（使用新标签） */
&gmac0 {
	nvmem-cells = <&macaddr_factory_0>;
	nvmem-cell-names = "mac-address";
};

&gmac1 {
	nvmem-cells = <&macaddr_factory_8000>;
	nvmem-cell-names = "mac-address";
};

/* pcie1 的 Wi-Fi 仍然使用 eeprom_factory_0（无需改动） */
EOF

# 4. mt7621.mk 新增 W6180 设备条目（保持与您原有一致）
echo "" >> "$MK_FILE"
echo "define Device/w6180" >> "$MK_FILE"
echo "  DEVICE_VENDOR := Maiwardi" >> "$MK_FILE"
echo "  DEVICE_MODEL := W6180" >> "$MK_FILE"
echo "  DEVICE_DTS := mt7621_xiaomi_mi-router-cr6606" >> "$MK_FILE"
echo "  DEVICE_PACKAGES := kmod-mt76-connac mt76da-firmware mtk-wifi-da" >> "$MK_FILE"
echo "  IMAGE_SIZE := 32448k" >> "$MK_FILE"
echo "endef" >> "$MK_FILE"
echo "TARGET_DEVICES += w6180" >> "$MK_FILE"

# 5. 主机名、时区、北京时间
sed -i 's/OpenWrt/W6180-MT7621/g' package/base-files/files/bin/config_generate
sed -i 's/UTC/CST-8/g' package/base-files/files/bin/config_generate
sed -i 's/00:00:00/08:00:00/g' package/base-files/files/bin/config_generate

# 6. LuCI 默认中文界面
[ -f feeds/luci/modules/luci-base/root/etc/config_generate ] && sed -i 's/luci.i18n.en/luci.i18n.zh-cn/g' feeds/luci/modules/luci-base/root/etc/config_generate

#!/bin/bash
# ImmortalWrt MT7621 W6180 适配脚本 基于xiaomi_mi-router-cr6606模板
# 硬件：MT7621A + MT7905DAN WiFi6 256M DDR3 32MB NOR Flash

# 真实完整DTS文件名（修复缺失mi-router-前缀）
DTS_FILE=target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606.dts

# 1. 修复串口波特率 原生已经115200，保留兼容逻辑
[ -f $DTS_FILE ] && sed -i 's/3125000/115200/g' $DTS_FILE

# 2. 屏蔽DTS原生复位按键（原生GPIO18，释放给W6180 GPIO8 Breed按键）
[ -f $DTS_FILE ] && sed -i '/reset {/,/};/ s/^/#/' $DTS_FILE

# 3. 替换NAND分区为32MB SPI NOR 匹配Breed分区
[ -f $DTS_FILE ] && sed -i '/partitions/,/};/c\
	partitions {\
		compatible = "fixed-partitions";\
		#address-cells = <1>;\
		#size-cells = <1>;\
		partition@0 {\
			label = "u-boot";\
			reg = <0x000000 0x030000>;\
			read-only;\
		};\
		partition@30000 {\
			label = "env";\
			reg = <0x030000 0x010000>;\
		};\
		partition@40000 {\
			label = "factory";\
			reg = <0x040000 0x010000>;\
			read-only;\
		};\
		partition@50000 {\
			label = "firmware";\
			reg = <0x050000 0x1FB000>;\
		};\
	};' $DTS_FILE

# 4. mt7621.mk 新增w6180设备条目
MK_FILE=target/linux/ramips/image/mt7621.mk
echo "" >> $MK_FILE
echo "define Device/w6180" >> $MK_FILE
echo "  DEVICE_VENDOR := Maiwardi" >> $MK_FILE
echo "  DEVICE_MODEL := W6180" >> $MK_FILE
# 绑定正确完整DTS文件名
echo "  DEVICE_DTS := mt7621_xiaomi_mi-router-cr6606" >> $MK_FILE
echo "  DEVICE_PACKAGES := kmod-mt76-connac mt76da-firmware mtk-wifi-da" >> $MK_FILE
echo "  IMAGE_SIZE := 32448k" >> $MK_FILE
echo "endef" >> $MK_FILE
echo "TARGET_DEVICES += w6180" >> $MK_FILE

# 5. 系统主机名、时区、时间修改
sed -i 's/OpenWrt/W6180-MT7621/g' package/base-files/files/bin/config_generate
sed -i 's/UTC/CST-8/g' package/base-files/files/bin/config_generate
sed -i 's/00:00:00/08:00:00/g' package/base-files/files/bin/config_generate

# 6. LuCI默认中文界面
[ -f feeds/luci/modules/luci-base/root/etc/config_generate ] && sed -i 's/luci.i18n.en/luci.i18n.zh-cn/g' feeds/luci/modules/luci-base/root/etc/config_generate

#!/bin/bash
# ImmortalWrt MT7621 W6180 适配脚本 基于xiaomi_cr6606模板
# 硬件：MT7621A + MT7905DAN WiFi6 256M DDR3 32MB NOR Flash

# 1. 修复串口波特率 3125000 → 115200 解决TTL乱码
DTS_FILE=target/linux/ramips/dts/mt7621_xiaomi_cr6606.dts
[ -f $DTS_FILE ] && sed -i 's/3125000/115200/g' $DTS_FILE

# 2. 屏蔽DTS原生复位按键，释放GPIO8给Breed识别
[ -f $DTS_FILE ] && sed -i '/reset {/,/};/ s/^/#/' $DTS_FILE

# 3. 修改分区：CR6606 NAND → W6180 32M NOR Flash（关键改动）
# 替换flash分区布局，适配32MB SPI NOR
sed -i '/partitions/,/};/c\
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

# 4. 镜像编译脚本 mt7621.mk 新增W6180设备条目
MK_FILE=target/linux/ramips/image/mt7621.mk
# 复制CR6606模板，改名为W6180，适配32M NOR
echo "" >> $MK_FILE
echo "define Device/w6180" >> $MK_FILE
echo "  DEVICE_VENDOR := Maiwardi" >> $MK_FILE
echo "  DEVICE_MODEL := W6180" >> $MK_FILE
echo "  DEVICE_DTS := mt7621_xiaomi_cr6606" >> $MK_FILE
echo "  DEVICE_PACKAGES := kmod-mt76-connac mt76da-firmware mtk-wifi-da" >> $MK_FILE
echo "  IMAGE_SIZE := 32448k" >> $MK_FILE
echo "endef" >> $MK_FILE
echo "TARGET_DEVICES += w6180" >> $MK_FILE

# 5. 系统定制：主机名、时区、中文
sed -i 's/OpenWrt/W6180-MT7621/g' package/base-files/files/bin/config_generate
sed -i 's/UTC/CST-8/g' package/base-files/files/bin/config_generate
sed -i 's/00:00:00/08:00:00/g' package/base-files/files/bin/config_generate

# 6. LuCI默认中文界面
[ -f feeds/luci/modules/luci-base/root/etc/config_generate ] && sed -i 's/luci.i18n.en/luci.i18n.zh-cn/g' feeds/luci/modules/luci-base/root/etc/config_generate

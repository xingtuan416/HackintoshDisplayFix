#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成测试用的 EDID 数据与 ioreg 输出。

两台显示器：
  A) DELL U2720Q   VID 10ac  PID 4183  —— 显示器名放在【第 3 个】descriptor（常规情况）
  B) LG HDR 4K     VID 1e6d  PID 5b11  —— 显示器名放在【第 4 个】descriptor（旧脚本会输出乱码）
"""
import base64
import os

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
os.makedirs(FIX, exist_ok=True)


def build_edid(manufacturer, product, name, name_desc_index, year=2020, week=30):
    """name_desc_index: 3 或 4，决定显示器名放第几个 descriptor"""
    b = bytearray(128)
    b[0:8] = bytes([0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])
    b[8:10] = manufacturer.to_bytes(2, "big")
    b[10:12] = product.to_bytes(2, "little")
    b[12:16] = bytes([0x78, 0x56, 0x34, 0x12])
    b[16] = week
    b[17] = year - 1990
    b[18] = 0x01          # EDID 版本 1
    b[19] = 0x04          # 修订 4      <- 脚本会重写
    b[20] = 0x80          # 数字输入     <- 脚本会重写为 0x90
    b[21] = 0x3C          # 水平尺寸 60cm
    b[22] = 0x23          # 垂直尺寸 35cm
    b[23] = 0x78          # gamma 2.2
    b[24] = 0x0A          # features    <- 脚本会重写为 0xE6
    b[25:35] = bytes([0xEA, 0x1E, 0xC5, 0xAE, 0x4F, 0x34, 0xB5, 0x26, 0x0E, 0x50])
    b[35:38] = bytes([0x54, 0xA5, 0x4B])
    b[38:54] = bytes([0x00, 0x71, 0x4F, 0x81, 0x80, 0xA9, 0xC0, 0xD1, 0xC0,
                      0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01])
    # descriptor 1 / 2：详细的时序描述符（内容不影响解析）
    dtd = bytes([0x02, 0x3A, 0x80, 0x18, 0x71, 0x38, 0x2D, 0x40, 0x58, 0x2C,
                 0x45, 0x00, 0x0F, 0x28, 0x21, 0x00, 0x00, 0x1E])
    b[54:72] = dtd
    b[72:90] = bytes([0x01, 0x1D, 0x80, 0x18, 0x71, 0x1C, 0x16, 0x20, 0x58, 0x2C,
                      0x25, 0x00, 0x0F, 0x28, 0x21, 0x00, 0x00, 0x9E])
    # 显示器名描述符
    text = name.encode("ascii")
    payload = text + b"\x0a" + b"\x20" * (13 - len(text) - 1)
    assert len(payload) == 13, len(payload)
    name_desc = bytes([0x00, 0x00, 0x00, 0xFC, 0x00]) + payload
    # 范围限制描述符
    range_desc = bytes([0x00, 0x00, 0x00, 0xFD, 0x00, 0x38, 0x4C, 0x1E, 0x51, 0x11,
                        0x00, 0x0A, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20])
    if name_desc_index == 3:
        b[90:108] = name_desc
        b[108:126] = range_desc
    else:
        b[90:108] = range_desc
        b[108:126] = name_desc
    b[126] = 0x00
    b[127] = (-sum(b[0:127])) & 0xFF
    return bytes(b)


def inject_transform(edid_hex):
    """复刻 HackintoshDisplayFix 的 EDID 改造算法"""
    version = edid_hex[38:40]
    basic = edid_hex[40:42]
    checksum = edid_hex[254:256]
    newcs = (int(checksum, 16) + int(version, 16) + int(basic, 16) - 0x04 - 0x90) & 0xFF
    newedid = (edid_hex[0:38] + "0490" + edid_hex[42:48] + "e6"
               + edid_hex[50:254] + "%02x" % newcs)
    assert len(newedid) == 256, len(newedid)
    return newedid, base64.b64encode(bytes.fromhex(newedid)).decode()


dell = build_edid(0x10AC, 0x4183, "DELL U2720Q", name_desc_index=3)
lg = build_edid(0x1E6D, 0x5B11, "LG HDR 4K", name_desc_index=4)

dell_hex = dell.hex()
lg_hex = lg.hex()
dell_new, dell_b64 = inject_transform(dell_hex)
lg_new, lg_b64 = inject_transform(lg_hex)

IORS = '    | |   |   |   |   |   |   |           "IODisplayEDID" = <%s>\n'


def ioreg_intel(edids):
    out = '+-o Root  <class IORegistryEntry, id 0x100000100, retain 15>\n'
    for e in edids:
        out += IORS % e
    return out


with open(os.path.join(FIX, "ioreg_intel_2.txt"), "w") as f:
    f.write(ioreg_intel([dell_hex, lg_hex]))
with open(os.path.join(FIX, "ioreg_intel_1.txt"), "w") as f:
    f.write(ioreg_intel([dell_hex]))
with open(os.path.join(FIX, "ioreg_intel_0.txt"), "w") as f:
    f.write('+-o Root  <class IORegistryEntry>\n')

arm = ('    | |   |   |   |   |   |   |     "DisplayAttributes" = '
       '{"LegacyManufacturerID"=4268,"ProductID"=16771,"ProductName"="DELL U2720Q",'
       '"SerialNumber"=1,"DisplayProductName"="DELL U2720Q"}\n'
       '    | |   |   |   |   |   |   |     "DisplayAttributes" = '
       '{"LegacyManufacturerID"=7789,"ProductID"=23313,"ProductName"="LG HDR 4K",'
       '"SerialNumber"=2,"DisplayProductName"="LG HDR 4K"}\n')
with open(os.path.join(FIX, "ioreg_arm64_2.txt"), "w") as f:
    f.write(arm)

with open(os.path.join(FIX, "expected.sh"), "w") as f:
    f.write("# 由 gen_fixtures.py 自动生成\n")
    f.write('EXPECT_VID="10ac"\n')
    f.write('EXPECT_PID="4183"\n')
    f.write('EXPECT_NAME="DELL U2720Q"\n')
    f.write('EXPECT_VID_DEC="4268"\n')
    f.write('EXPECT_PID_DEC="16771"\n')
    f.write('EXPECT_B64="%s"\n' % dell_b64)
    f.write('EXPECT_LG_VID="1e6d"\n')
    f.write('EXPECT_LG_PID="5b11"\n')
    f.write('EXPECT_LG_NAME="LG HDR 4K"\n')
    f.write('EXPECT_LG_B64="%s"\n' % lg_b64)

print("DELL EDID   :", dell_hex[:32], "...")
print("DELL 名称位置: descriptor 3 -> 字节 95..106")
print("LG   EDID   :", lg_hex[:32], "...")
print("LG   名称位置: descriptor 4 -> 字节 113..125（旧脚本读字节 95..106 会乱码）")
print()
print("DELL 注入后 base64:", dell_b64)
print("LG   注入后 base64:", lg_b64)
print()
print("已写入:", FIX)

# 三码生成

[← 返回 README](../README.md)

仓库里的 `config.plist` 三码是**占位符**：

```
SystemSerialNumber = F5KXXXXXXXXXXX
MLB                = F5KXXXXXXXXXXXXXX
SystemUUID         = 00000000-0000-0000-0000-000000000000
ROM                = 000000000000
```

直接这样用能开机进系统，但 **iMessage / FaceTime / App Store 登录会失败**。

---

## 三个码是什么

| 字段 | 含义 | 长度 | 来源 |
|---|---|---|---|
| `SystemSerialNumber` | 机器序列号 | 12 字符 | 由机型规则生成 |
| `MLB` | 主板序列号（Main Logic Board） | 17 字符 | 与序列号配对生成 |
| `SystemUUID` | 硬件 UUID | 36 字符 | 随机 |
| `ROM` | 网卡 MAC（小端 6 字节） | 6 字节 | 取本机有线网卡 MAC |

`SystemSerialNumber` 和 `MLB` **必须配对**。单独换一个会导致 Apple 服务器拒绝。

---

## 用 GenSMBIOS 生成

### 安装

```bash
git clone https://github.com/corpnewt/GenSMBIOS.git
cd GenSMBIOS
chmod +x GenSMBIOS.command
./GenSMBIOS.command
```

### 使用

```
1. Install/Update MacSerial        ← 先更新一次
2. Select config.plist             ← 选你要改的 config.plist
3. Generate SMBIOS                 ← 关键
```

输入机型：

```
MacPro7,1
```

生成数量填 `5`（多生成几个，挑一个没被别人用过的）。

### 输出长这样

```
Type:         MacPro7,1
Serial:       F5KXXXXXXX1P
Board Serial: F5KXXXXXXXXXXXXXXX
SmUUID:       XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
Apple ROM:    XXXXXXXXXXXX
```

对应填入：

| 输出 | 填入 |
|---|---|
| `Serial` | `SystemSerialNumber` |
| `Board Serial` | `MLB` |
| `SmUUID` | `SystemUUID` |
| `Apple ROM` | `ROM` |

GenSMBIOS 的 `4. Select config.plist` 功能会**直接写进 config.plist**，最省事。

---

## 手动改（如果不用 GenSMBIOS）

`ROM` 要从网卡 MAC 转换。假设有线网卡 MAC 是 `a0:b1:c2:d3:e4:f5`：

```
原始 MAC:   a0 b1 c2 d3 e4 f5
写入 ROM:   应该是这 6 个字节
```

在 plist 里是 data 类型：

```xml
<key>ROM</key>
<data>obHC0+T1</data>
```

或者转成 base64：

```bash
python3 -c "
import base64
mac = bytes.fromhex('a0b1c2d3e4f5')
print(base64.b64encode(mac).decode())
"
```

> 有些教程说要**反序**（`f5e4d3c2b1a0`）。实际上 OpenCore 的 `ROM` 字段就是正序的 6 字节 MAC，不用反。如果你的网卡 MAC 是 `a0:b1:c2:d3:e4:f5`，`ROM` 就是 `a0b1c2d3e4f5`。

查本机 MAC：

```bash
ifconfig en0 | grep ether
```

---

## 怎么判断序列号能不能用

### 1. 查 Apple 保修页面

打开 [checkcoverage.apple.com](https://checkcoverage.apple.com/)，输入序列号。

| 结果 | 判断 |
|---|---|
| "此序列号无效" | ✅ **可以用**（说明没被注册） |
| 显示某台真实 Mac 的保修信息 | ❌ **不能用**，这是别人的机器 |
| "此设备已被替换" | ❌ 不能用 |

**理想情况是"无效"。** 这听起来反直觉，但黑苹果就是要一个 Apple 数据库里不存在的序列号。

### 2. 注意机型真实性

`MacPro7,1` 是 2019 年的机器，序列号格式是 `F5K` 开头 + 9 位。

如果生成出来的序列号格式明显不对（比如长度不对、字母组合奇怪），说明 MacSerial 的数据过期了，更新一下。

---

## 不要做的事

### ❌ 不要用别人分享的 EFI 里的三码

这是黑苹果社区最脏的问题之一。有人把自己能用的三码连 EFI 一起上传，下载的人直接用 —— 然后两个人在 Apple 服务器上抢同一个身份。

后果：轻则 iMessage 掉线，重则 **Apple ID 被标记/封禁**。

**这也是本仓库把三码脱敏的原因。**

### ❌ 不要在多台机器上用同一套三码

同上。

### ❌ 不要买"三码服务"

有人卖"可用序列号"。这些东西来路不明，且大概率是批量注册的，随时会被 Apple 干掉。

### ❌ 不要用真实 Mac 的序列号

等于盗用他人身份。

---

## 改完之后

### 清 NVRAM

改了三码必须清一次 NVRAM，否则旧值还有残留：

```
OpenCore 菜单 → 按空格显示辅助项 → Reset NVRAM
```

或者命令行：

```bash
sudo nvram -c
```

> **注意**：`nvram -c` 会清掉 `boot-args`。清完要重新写回：
> ```bash
> sudo nvram boot-args="-v keepsyms=1 debug=0x100 alcid=15 ..."
> ```
> 更稳妥的办法是用 OpenCore 菜单里的 `Reset NVRAM` —— 它会按 `config.plist → NVRAM → Delete` 的规则重建。

### 验证

```bash
# 看系统报告的序列号
system_profiler SPHardwareDataType | grep -E "Serial|Hardware UUID|Model"

# 看 NVRAM 里的值
nvram -p | grep -i "MLB\|ROM\|uuid"
```

### 登录 iMessage

1. 先确保有线网络正常、`en0` 是内建网卡
2. 打开信息 App，登录 Apple ID
3. 如果提示"联系 Apple 支持"，说明三码有问题，换一套

**注意**：iMessage 能不能用还取决于 Apple 的风控。同一套三码在短时间内被多次激活会触发风控，需要等一段时间。

---

## 常见问题

### 提示"无法登录，请联系 Apple 支持"

按顺序排查：

1. 三码是否真的唯一（去 checkcoverage 查）
2. `ROM` 是否与 `en0` 的 MAC 一致
3. `SystemUUID` 是否与其他机器重复
4. 网卡是否被识别为 `en0` 且 `built-in`

```bash
# 检查内建网卡
ioreg -l | grep -A2 "BSD Name.*en0" | grep built-in
```

`config.plist` 里应该有：

```xml
<key>PciRoot(0x0)/Pci(0x1,0x3)/Pci(0x0,0x2)/Pci(0x0,0x0)/Pci(0x0,0x0)</key>
<dict>
  <key>built-in</key><data>AQ==</data>     <!-- 0x01 -->
</dict>
```

### 序列号格式对但系统显示 "Unknown"

正常。`MacPro7,1` 在 `system_profiler` 里可能显示不完整信息。只要序列号对了就行。

### 改完开机变慢

清一次 NVRAM。旧的 SMBIOS 缓存会让系统重新枚举硬件。

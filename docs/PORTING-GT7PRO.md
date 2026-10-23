# 移植到 realme GT7 Pro（RMX5010 / RMX5011）

本文记录把 OmniCam Muse 从 OPPO Find X9 Ultra（PMA110，相机 7.006.x）迁到 realme GT7 Pro 的评估、已完成的改造、以及拿到设备取证后要做的工序。

> 目标机现状：**ColorOS 17，`RMX5010_17.0.0.112(CN01C10P02)`，相机 `7.006.180(60000)_26-10-19 22:03`**（2026-10 系统升级后）。
>
> 关键发现：相机是 **7.006.180**，模块适配的是 **7.006.119**——同一条 7.006 分支，只差几十个 build。`symbols.json` 用的是字符串指纹而不是类名，跨 build 匹配本来就是它的设计目标，所以符号层的预期命中率很高，B 级功能大多能直接复用，C 级里走 Java 层的那几个也有了落点。

## 0. 结论先说

Muse 不是一个"改几个机型常量就能跑"的模块。它的每个功能都同时踩在三条与机型绑定的链路上：

| 层 | 内容 | 换机型的后果 |
|---|---|---|
| 资源层 | `module/payload/` 下的 `camera_unit_config`、`oplus_camera_config`、`meishe_lut`、`basictone`、ISP tuned bin | 别的机型的配置喂给本机 HAL，轻则模式消失，重则相机启动崩溃 |
| 符号层 | `assets/symbols.json`（309 个相机符号 + 31 个相册符号），指向 ColorOS 16 相机 7.006 的混淆类 | 找不到的符号只会让对应功能自动关闭，不会崩，但功能等于没有 |
| 指令层 | `app/src/main/cpp/*` 里对 `libAlgoInterface.so`、`libBasicTonePhotoX9.so`、`libCombineLut.so` 的偏移与跳板 | 偏移对不上就是野指针，直接崩相机进程 |

GT7 Pro 是骁龙 8 Elite + ColorOS 17（Android 16 基线），相机是与 7.006 同代的新版本，但它是 realme 机型：没有哈苏大师管线、没有 200MP 传感器、没有 XPAN 与 GR 模式。**整包直接刷过去依旧没有意义**，正确做法仍是：先做设备门控（已完成），再按功能分级逐项重建。

## 1. 两台机器的差异

| 项 | Find X9 Ultra (PMA110) | GT7 Pro (RMX5010) |
|---|---|---|
| 平台 | 联发科天玑 9500 | 骁龙 8 Elite (SM8750) |
| 系统 | ColorOS 16 / Android 16（`first_api_level` 36） | **ColorOS 17 / Android 16**（`RMX5010_17.0.0.112 CN01C10P02`） |
| 相机 | `com.oplus.camera` 7.006.119 | **7.006.180(60000)**，同分支，差 61 个 build |
| 相册 | `com.coloros.gallery3d` 17.10.7 | ColorOS 17 对应版本 |
| 影像管线 | 哈苏大师色彩 LMT + BasicTone（X9 专属库） | realme 影像调校，无哈苏 LMT |
| 相机 | 200MP 超清、XPAN、GR（移植）、移轴 | 50MP 主摄 + 50MP 3× 潜望 + 8MP 超广，无上述模式 |

### 1.1 系统升级（ColorOS 17）带来的变化

| 变化 | 对移植的影响 |
|---|---|
| 相机 7.006.180 vs 模块目标 7.006.119 | 同一分支，字符串指纹大概率仍命中；差异集中在补丁级的字符串与分支，需逐条跑报表确认，但不是整表重写 |
| 同代框架类 | `BaseMode`、`ModeItem`、滤镜目录、`WatermarkInfo`、`Mode.modeId` 等结构一致，B 级功能可直接复用 |
| ColorOS 17 沿用 OPPO 影像 SDK | `libAlgoInterface.so`、`libCombineLut.so` 应该都在；但骁龙与天玑是两个编译产物，指令层偏移必须重定位，不能照搬 |
| OTA 清掉 root 与 LSPosed | 升级后必须重新 root、重刷模块；取证要在升级后做 |
| 相册版本同步升级 | 批量水印与相册水印系列属 B 级，类名可能变，需要重测 |

## 2. 功能可行性分级

| 级别 | 含义 | 功能 | 代码位置 |
|---|---|---|---|
| **A** | 与机型基本无关，改门控即可用 | 快门声（静音/振动下仍响）、闪光灯与实况按模式记忆、水印与 EXIF 机型伪装、日志镜像、注入状态检查、地址跳转 | `hook/shutter/`、`hook/modestate/`、`hook/watermark/ModelSpoof.java`、`common/CameraLogMirror.java`、`ui/Diagnostics.kt`、`hook/gallery/AddressNavigation.java` |
| **B** | 需要本机取证后调参 | 相册批量水印、相册水印系列开放、快启键指定模式、4K60 保留滤镜、25MP/高像素直出放宽 | `hook/gallery/BatchWatermark.java`、`hook/gallery/WatermarkSeriesUnlock.java`、`hook/launch/KeyLaunchMode.java`、`hook/video/VideoFilterHighSpec.java`、`hook/unlock25mp/` + `cpp/unlock25mp.cpp` |
| **C** | 需要按本机管线重新实现 | 滤镜列表注入、大师色彩、大师滤镜、大师 LUT 槽与对比度、颗粒、物理柔光、自然模式、POP、X10、GR、XPAN、移轴 | `hook/filters/`、`hook/mastercolor/`、`hook/masterfilter/`、`hook/masterlut/`、`hook/softlight/` + `cpp/soft_light.cpp`、`hook/natural/` + `cpp/natural_mode.cpp`、`hook/pop/`、`hook/x10/`、`hook/gr/`、`hook/xpan/`、`hook/tilt/` |
| **D** | 不适用 | 哈苏超清 200MP 人脸门禁（GT7 Pro 无 200MP）、哈苏 / LUMO 水印系列（realme 无水印资产） | `hook/highpixel/HighPixel200mFace.java`、`cpp/face200m.cpp`、`module/payload/face200m/` |

C 级的共同点：都直接挂钩 HAL。举例来说，大师 LUT 槽挂的是 `libBasicTonePhotoX9.so` 的 `MergeLutTet_resize` 和 `libCombineLut.so` 的 `MergeLutTet_resize2rgb`（`cpp/master_lut_slots.cpp:241-246`），柔光挂的是 `libmsnativefilter.so` 的 ProMist（`cpp/soft_light.cpp:957`），GR 的 BasicTone 补丁写死了 PMA110 相机 7.006.77 的偏移（`cpp/gr_basictone.cpp:10`）。

ColorOS 17 之后要分两种情况看：

- **`libBasicTonePhotoX9.so` 是 X9U 独有**（文件名就带 X9），GT7 Pro 上不存在，所以大师色彩、大师 LUT 槽、颗粒、GR 的 BasicTone 分支仍然没有宿主，属长期关闭项；
- 但 **POP / X10 / XPAN / 移轴 / 滤镜注入**走的是相机 APK 的 Java 层与通用 SDK，只要 ColorOS 17 的相机里还留着对应类（realme 机型通常会保留 retro/GR 的入口，只是不开放），这些就只是"重做指纹 + 补资源"，不是从零实现。这一条要等符号命中率报表出来才能定。

## 3. 本次已完成的改造

核心思路：**给模块加一层设备档案，Java 钩子与三个开机脚本读同一份配置，默认什么都不挂**。这样 GT7 Pro 可以先把模块装上去跑 A 级功能，再逐个开开关验证，任何一步出问题都只影响那一个功能。

新增文件：

| 路径 | 作用 |
|---|---|
| `device-profiles/gt7pro.json` | 唯一的设备档案：不挂载任何 `/odm` 资源，只开 A 级钩子 |
| `module/device.json` | 打包进模块的设备档案，由 `build.ps1` 从上面复制 |
| `app/src/main/java/local/jiege/hook/common/DeviceProfile.java` | 从 `assets/device.json` 读取开关；读不到时全部为开，保证老构建行为不变 |
| `tools/port/dump_device.sh` | 设备侧一键取证脚本（只读） |

修改文件：

| 路径 | 改动 |
|---|---|
| `app/src/main/java/local/jiege/hook/ModuleEntry.java` | 每个 `installCamera/installGallery` 前加 `DeviceProfile.on("key")` 判断；`xpan` 三项合并到同一开关 |
| `app/build.gradle.kts` | `-Pdevice=<name>` 把档案作为 `assets/device.json` 打进 APK |
| `build.ps1` | 新增 `-Device`（默认 `gt7pro`），同步 `module/device.json` 并传给 Gradle |
| `module/module.prop` | `id` 改为 `omnicam_gt7pro`，版本 `Muse 4.4.4-gt7pro`，避免与原版互相覆盖 |
| `module/post-fs-data.sh` | 顶部加 `flag()`，`/odm/etc/camera/config`、`meishe_lut`、`basictone`、ISP bin、gamma、`CameraHWConfiguration.config` 各自受控 |
| `module/post-mount.sh` | `libAlgoInterface.so` / `libBasicTonePhoto*.so` 的绑定受 `mount_hal_libs` 控制（**这是最危险的一步**，默认对 GT7 Pro 关闭） |
| `module/service.sh` | GR 配置与 LMT、大师色彩数据、POP 资源、移轴建库、25MP、200MP、相册 GR 开关与 IPU jar 全部按 flag 分段执行 |

构建 GT7 Pro 版本：

```powershell
.\build.ps1
```

默认就是 GT7 Pro 档案，产物为 `OmniCam-Muse-4.4.4-gt7pro-KSU.zip`。仓库只服务这一台机器，不再保留 X9U 档案；需要对比历史行为时去 git 提交 `7cc0458a` 之前看。

## 4. 需要你提供的取证

升级到 ColorOS 17 后先重新 root（KSU 补丁要匹配新的 boot 镜像），再在手机上用 root 执行：

```sh
adb push tools/port/dump_device.sh /data/local/tmp/
adb shell su -c "sh /data/local/tmp/dump_device.sh --apk"
adb pull /sdcard/omnicam-dump-RMX5010-*.tar.gz
```

取证必须在升级后做：OTA 之前的相机是 6.x，指纹与现在完全不同，旧 dump 全部作废。

`--apk` 会把相机和相册 APK 一并打包（几百 MB）。**这个必须带**，否则没法给 `symbols.json` 重新做指纹匹配，B/C 级功能一项都开不了。不想带 APK 的话，也可以单独把 `/product/app/.../OplusCamera/OplusCamera.apk` 拉出来给我。

脚本收集的东西与用途：

| 内容 | 用途 |
|---|---|
| `props.txt` | 型号、ColorOS 版本号、`ro.product.first_api_level`、realme/OPPO 专属属性，决定特性开关的默认值 |
| `packages.txt` | 相机/相册版本号、APK 路径、`/odm/lib64` 下的 HAL 库清单 |
| `odm_camera_tree.txt` | `/odm/etc/camera` 全量列表；模块要 bind 的那 8 个文件是否存在、大小、权限 |
| `configs/` | `camera_unit_config`、`oplus_camera_config`、preview decision、`CameraHWConfiguration.config` 等原文 |
| `lut_and_basictone.txt` | `meishe_lut` / `filters_lut` / `basictone` 的目录结构（只列文件名，不打包内容） |
| `lib_sha256.txt` | HAL 库的 sha256 与大小，用于判断能否复用现成偏移 |
| `db/mode_data.db` | 相机模式库，决定哪些模式能在 `mode_data.db` 里被打开 |
| `prefs/` | `override_config_data.xml`、相册特性开关，看看 GT7 Pro 已经开了什么 |
| `apk/` | 重新跑符号指纹的输入 |

## 5. 拿到 dump 之后的工序

1. **符号命中率报表**：解包相机 APK，用 `tools/symbols/replay` 把 `symbols.json` 的 309 条指纹全跑一遍，输出每条命中/未命中。命中率决定了 B 级功能有多少能直接复用。
2. **裁剪出 `symbols.gt7pro.json`**：只保留命中项，避免启动时白跑 DexKit；未命中的功能在档案里保持关闭。
3. **重建 payload**：以 GT7 Pro 自己的 `camera_unit_config`、`oplus_camera_config` 为底，只在上面做差异修改（例如放开 25MP 决策条件），**绝不复制 X9U 的文件**。
4. **HAL 偏移重定位**：只对确认要保留的功能做。`libAlgoInterface.so` 里用字符串/常量定位（如 `cpp/natural_mode.cpp` 的 `0x33d6bf95` eps 特征），而不是照搬 `0x150cdd0` 这类绝对地址。
5. **按阶段开 flag 验证**：每次只改一个 key，出问题就把它关回去。

## 6. 分阶段验证清单

| 阶段 | 打开的 key | 验证点 | 失败表现 |
|---|---|---|---|
| 0（无挂载实验） | `require_mounts=false`、`native_hooks=false` + 阶段 1 的键 | 只刷 APK 不刷 `/odm`，验证 7.006.180 上符号能否解析：看设置应用"注入状态"卡片与 `logcat | grep Symbols` | 相机启动异常 → LSPosed 里关掉相机作用域 |
| 1（已默认） | `shutter` `log_mirror` `address_nav` `model_spoof` | 静音模式快门有声；相册详情点地址能跳地图；水印机型显示预设 | 相机无响应 → 关 `shutter` |
| 2 | `batch_watermark` | 多选 → 更多 → 批量水印，3 张能完成 | 相册崩溃 → 关掉 |
| 3 | `mode_state` `key_launch` | 每个模式记住闪光灯/实况；快启键直达指定模式 | 相机启动卡死 → 关 `key_launch` |
| 4 | `watermark_unlock` `palette_gallery` | 相册水印列表出现对应系列 | 列表为空 → 说明类名不同，需重做 |
| 5 | `video` `unlock25mp` | 4K60 保留滤镜；高像素触发率 | 花屏/降分辨率 → 关掉 |
| 6 | `filters` `filter_panel` | 滤镜条出现模块滤镜；先看 `symbols` 命中报告再开 | 大师卡片消失 → 关掉 |
| 7 | `pop` `x10` `xpan` `tilt` `seamless` | ColorOS 17 相机若仍带 retro/XPAN 类，这一步成功率最高；一次只开一个模式 | 模式入口缺失 → 说明类被裁掉，回 B 级重做资源 |
| 8 | `gr` `gr_gallery` | 需要 `libBasicTonePhotoX9.so` 的 BasicTone 分支，GT7 Pro 无此库 | 预期失败，只做记录 |
| 9 | `master_color` `master_filter` `master_lut` `master_contrast` `soft_light` `natural` | 哈苏 LMT + X9 专属库，realme 机型没有 | 长期关闭 |

## 7. 风险与回滚

- **最危险的是 `mount_hal_libs` 与 `mount_camera_config`**：把 X9U 的 HAL 库或相机配置 bind 到 GT7 Pro 上，可能让相机进程直接崩溃甚至开机后相机不可用。`gt7pro.json` 里这两项都是 `false`，在完成取证和适配前不要打开。
- 建议第一次安装时同时准备好 `adb shell touch /data/adb/modules/omnicam_gt7pro/disable` 的写法，或直接在 KernelSU 里停用模块再重启；所有 bind 都是模块生命周期内的。
- LSPosed 作用域仍需勾选 **系统框架、相机、相册** 三项；少勾系统框架只是快门声不生效，少勾相册则相册功能全无。
- 不同证书签名的 APK 不能覆盖安装，换签名前先卸载旧设置应用。

## 8. 速查

```sh
# 构建
./build.ps1

# 看模块挂载与设备档案
adb shell su -c "cat /data/adb/modules/omnicam_gt7pro/device.json"
adb shell su -c "cat /data/adb/modules/omnicam_gt7pro/bind.log"

# 看相机是否被注入
adb shell su -c "logcat -d | grep -E 'DeviceProfile|Symbols|Muse'"
```

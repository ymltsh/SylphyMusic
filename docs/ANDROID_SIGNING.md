# Android 正式签名

2026-10-28 已在本机建立独立于调试证书的正式签名身份，并完成三个 ABI 的 Release APK 构建与验签。该身份用于本项目自行分发的 APK；未接入 Google Play App Signing。应用 ID 仍为 `com.ymltsh.sylphymusic`。

## 固定身份

- 算法：RSA 3072 / SHA256withRSA；证书有效期至 2054-03-15。
- 别名：`sylphy-release`。
- 证书 SHA-256：`de84e8469b8419278ac85a482b70103258a1edc331b3701c76a9d784a48eebc5`。
- 公共证书：[release-cert.pem](../android/signing/release-cert.pem)；可公开，不含私钥。
- 指纹文件：[release-cert.sha256](../android/signing/release-cert.sha256)；这是证书 DER 内容的 SHA-256，不能用 PEM 文本的文件摘要替代。

后续更新必须保留这一身份。丢失密钥后重新生成同名文件、别名或主体，不会恢复原身份。证书主体 `Sylphy Music` 是项目名称，不代表认证机构核验过的个人或企业身份。

## 本机私密文件与备份

私钥位于 `.private/android-signing/sylphy-release.p12`，为强随机密码加密的 PKCS#12。构建配置为 `android/key.properties`，恢复副本为 `.private/android-signing/key.properties.backup`；两者含明文密码，不得公开。签名目录和构建配置已设置 Windows ACL，仅允许当前用户和 SYSTEM；这些路径均被 Git 忽略。

**需要由维护者另做离线备份。** 本机恢复副本与私钥位于同一磁盘，不能抵御磁盘损坏。将密钥存入加密离线介质，并将密码保存到独立的密码管理器；至少保留两个可恢复副本。不要把整个目录作为普通附件发送或上传到源码仓库。

换机时恢复同一私钥到上述位置，将配置副本复制为 `android/key.properties`；如调整路径，`storeFile` 相对于 `android/` 解析，Windows 建议使用正斜杠。重新设置当前账户的文件访问权限，然后构建并核对公共证书。参考配置为 [key.properties.example](../android/key.properties.example)，其中不含真实密码。

## 构建与核验

在工程根目录运行，先确保没有设置 `SYLPHY_INTERNAL_DEBUG_SIGNING=1` 或 `SYLPHY_ALLOW_UNSIGNED_RELEASE=1`：

```powershell
flutter build apk --release --split-per-abi
python tool/verify_android_signing.py build/app/outputs/flutter-apk/app-arm64-v8a-release.apk build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk build/app/outputs/flutter-apk/app-x86_64-release.apk
```

校验工具先调用 SDK 的 `apksigner verify` 验证签名，再要求唯一签名者匹配仓库公共证书。SDK 从 PATH、Android 环境变量或 `android/local.properties` 定位，也可传入 `--apksigner`。`release.py` 本地准备阶段已加入同样的核验，避免将错误证书签名的 APK 打包为发布资产。

本轮产物仍为 `0.2.8-beta+11`，只证明正式签名链路可用。版本、发布清单和远端资产均未调整；不可与此前公开的同版本测试签名 APK 混用。构建日志为 `build/test_logs/android-production-signing-build.log`；未执行设备安装。

## 从测试版迁移

此前公开的 Android 包使用另一张调试证书。本轮没有配置证书轮换谱系，因此这些测试版不能直接覆盖安装当前正式密钥签名的 APK。不要在更新提示中宣称可以无损直接升级，也不要为绕过证书冲突自行卸载用户应用。

2026-10-28 维护者确认测试版未实际安装使用，因此本次切换按全新安装处理，无需开发旧测试版数据迁移功能。此决定不改变证书不兼容的技术约束；如有人另行安装过旧测试包，仍不能直接覆盖安装。项目当前未实现或验证整库导出与恢复。正式发布仍须完成其他 [发布门槛](RELEASE_GATES.md)。

Android 的证书约束和密钥备份要求见 [Android 官方应用签名说明](https://developer.android.com/studio/publish/app-signing)。Windows 代码签名不在本轮范围。

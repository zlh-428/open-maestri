## open-maestri vX.Y.Z — Title Here

Brief English summary of this release.
本版本的简要中文说明。

### Changes since vPREV | 自 vPREV 以来的变更

- **Category**: English description (#PR) — Thanks @contributor
  中文描述 (#PR)

> Add `— Thanks @contributor` to entries from external contributors.
> 外部贡献者的条目请附上 `— Thanks @contributor`。

### Contributors | 贡献者

- @contributor

---

## Installation | 安装说明

### Recommended | 推荐方式

1. Download **open-maestri.dmg** from the Assets below.
   从下方 Assets 下载 **open-maestri.dmg**。

2. Open the DMG, then drag **open-maestri** to **Applications**.
   打开 DMG，将 **open-maestri** 拖入 **Applications** 文件夹。

3. Requires **macOS 14.0+ (Sonoma)**. Supports both **Apple Silicon** and **Intel** Macs.
   需要 **macOS 14.0+（Sonoma）**。同时支持 **Apple Silicon** 和 **Intel** Mac。

### ⚠️ Gatekeeper / Unsigned App Notice | 未签名应用说明

This build is **not notarized by Apple**. To open it for the first time:
此版本**未经 Apple 公证**。首次打开时需要以下步骤：

**Option A — Right-click method | 方式 A — 右键菜单**

Right-click (or Control-click) the app icon in **Applications**, choose **Open**, then click **Open** in the dialog.
在 **Applications** 中右键（或按住 Control 点击）应用图标，选择**打开**，然后在弹出窗口中点击**打开**。

**Option B — System Settings | 方式 B — 系统设置**

If macOS blocks the app, go to **System Settings → Privacy & Security**, scroll down to find the blocked entry, and click **Open Anyway**.
如果 macOS 拦截了应用，前往**系统设置 → 隐私与安全性**，向下找到被拦截的条目，点击**仍要打开**。

**Option C — Terminal | 方式 C — 终端**

```bash
xattr -cr /Applications/open-maestri.app
```

---

## Upgrading | 升级说明

Replace the existing app in **Applications** with the new version. Workspaces and preferences are stored in `~/.open-maestri/` and will be preserved.
将 **Applications** 中的旧版本替换为新版本即可。工作区和偏好设置存储在 `~/.open-maestri/`，不会丢失。

---

*For issues or feedback, please open a GitHub issue at [zlh-428/open-maestri](https://github.com/zlh-428/open-maestri/issues).*
*如有问题或反馈，请在 [zlh-428/open-maestri](https://github.com/zlh-428/open-maestri/issues) 提交 GitHub Issue。*

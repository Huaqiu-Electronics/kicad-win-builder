# edge-headless / dsh CLI 集成实现说明

任务来源：`C:\code\hq-edge\docs\tasks\kicad-windows-intaller.md`（§17.7 交付物）。
目标：把固定版本 `edge-headless` 0.1.3（`edge-headless-win-x64.zip`）打入 KiCad Windows 安装器流水线，并以 stable `dsh` CLI shim 形式外露给全新终端。

## 架构边界（保持不变）

- 下载 / 校验 / 解压 / staging 全部归属 `build.ps1 -PreparePackage`；NSIS 只负责安装、PATH 集成与卸载清理。
- 运行时安装在 `$INSTDIR\bin\edge-headless\...`（与已有 `HQ_EDGE_LAUNCHER` 契约 `<exeDir>\edge-headless\bin\{node.exe,hq-edge-server.cjs}` 一致，launcher 未改动）。
- `edge-headless\bin` **不**加入 PATH；对外只暴露 stable shim `dsh.cmd`。
- 不使用 `latest` 版本，不使用 npm 安装。

## 下载位置与校验

| 项 | 值 |
|---|---|
| 资产 | `edge-headless-win-x64.zip`（GitHub Release `Huaqiu-Electronics/edge-headless` tag `0.1.3`） |
| URL | `https://github.com/Huaqiu-Electronics/edge-headless/releases/download/0.1.3/edge-headless-win-x64.zip` |
| SHA256 | `e8436850f40466bc8f1117b6682ad10834fd8ac5d26b1b37ebd2595faa18ba98` |
| 配置 | `build-configs/kicad-hq.json` → `sources.edge-headless.ref = "0.1.3"`、`sources.edge-headless-sha256.ref = "<SHA256>"` |

`build.ps1` 顶层新增四个变量（`$edgeHeadlessVersion` / `$edgeHeadlessAsset` / `$edgeHeadlessDownload` / `$edgeHeadlessChecksum`），版本取自配置，资产名与 URL 由固定资产名拼出（属释放布局契约常量）。

## staging 位置

`Start-Prepare-Package` 内（uv 块之后、sentry artifact 之前）新增 "Install edge-headless" 块：

1. `Get-Tool` 下载到 `$BuilderPaths.DownloadsRoot\edge-headless-win-x64.zip`（`-ExtractZip $False`，由本块自行解压）；
2. `7za x` 解压到 `$BuilderPaths.DownloadsRoot\edge-headless-temp\`；
3. 校验 ZIP 根为单一 `edge-headless\` 目录；
4. **剔除 DSH 用户数据缓存 `dsh\.dsh`**（上游资产自带：约 3 万个 node_modules 文件、约 205MB，含机器专属 `.credentials.yaml` 与 >260 字符的深层路径；CLI 首次运行会自动重建，绝不能随安装器下发。删除走 `Remove-Item`，失败则回退 `\\?\` 扩展路径前缀删除，兼容未开启长路径策略的机器）；
5. `Move-Item` 到 `$destBin\edge-headless`（即 `<stage>\bin\edge-headless`）；
6. 删除临时目录；
7. 完整性校验：`bin\node.exe`、`bin\hq-edge-server.cjs`、`bin\dsh.cmd` 任一缺失 → `Exit [ExitCodes]::ExtractionFailure`。

staging 树随后整体交给 NSIS 编译（NSIS 以 `<stage>\nsis` 为 cwd、`File "..\bin\..."` 相对引用，与现有其它运行时一致）。剔除 `.dsh` 后剩余最长路径在 CI 深度下实测 250 字符（<260），NSIS 3.08 可完整打包；`kicad-package.yml` 仍在 NSIS 打包前开启 `LongPathsEnabled`（CI runner 默认关闭，作为深度余量与未来资产变动的保险）。

## 安装位置（NSIS `install.nsi`）

- 常量：`EDGE_HEADLESS_REL=bin\edge-headless`（运行时树），`EDGE_HEADLESS_BIN_REL=bin\edge-headless\bin`（CLI 目录）。
- 安装时把 `<stage>\bin\edge-headless` 树原样装入 `$INSTDIR\bin\edge-headless`（沿用已有 `File "..\bin\edge-headless\*"` 相对引用风格）。
- 卸载时整树删除（`RMDir /r "$INSTDIR\bin\edge-headless"`）。

## shim 位置与注册表

| 作用域 | shim 目录 | 注册表键 |
|---|---|---|
| AllUsers | `$COMMONFILES64\KiCad\bin\dsh.cmd` | `HKLM\SOFTWARE\KiCad\DSH` → `EdgeHeadlessBin` = `$INSTDIR\bin\edge-headless\bin`（REG_EXPAND_SZ） |
| CurrentUser | `$LOCALAPPDATA\KiCad\bin\dsh.cmd` | `HKCU\SOFTWARE\KiCad\DSH` → `EdgeHeadlessBin`（同上） |

注册表根统一用 `SHCTX`（`$MultiUser.InstallMode` 决定 AllUsers=HKLM / CurrentUser=HKCU），安装器与卸载器均可用。

shim `nsis\support\dsh.cmd`（随安装器打包，CRLF）行为：
1. 读注册表 `HKLM → HKCU` 顺序取 `EdgeHeadlessBin`（`for /f "skip=2 tokens=2*"` 解析 `REG_SZ`）；
2. 若指向的目标存在且含 `dsh.cmd`，则 `call "%EDGE_HEADLESS_BIN%\dsh.cmd" %*` 并 `exit /b %ERRORLEVEL%`（参数、退出码原样透传；真实 `dsh.cmd` 为 `%~dp0node.exe "%~dp0dsh-cli.cjs" %*`，自包含、与工作目录无关）；
3. 否则回退：`dir /b /ad /o-d "%ProgramW6432%\KiCad"` 取“最新安装的版本目录”，若其中含运行时则调用之；
4. 都没有则以退出码 1 报错。
shim 不硬编码任何版本号；回退语义为“最新安装的版本优先”。

## PATH 作用域与幂等性

- 加入 PATH 的是 **shim 目录**（`$COMMONFILES64\KiCad\bin` 或 `$LOCALAPPDATA\KiCad\bin`），**不是** `edge-headless\bin`。
- AllUsers 写 `SYSTEM\CurrentControlSet\Control\Session Manager\Environment`（REG_EXPAND_SZ，原文读写，`%SystemRoot%` 等不被展开）；CurrentUser 写 `HKCU\Environment`。
- 安装：先判重（`${StrStr}` 检查 `<dir>;` 是否已在 `<PATH>;` 中），不重复追加。
- 卸载：纯指令手写扫描删除该 token，不碰无关条目，收尾去尾分号；PATH 为空则 `DeleteRegValue`。
- 增删后均 `SendMessage HWND_BROADCAST WM_SETTINGCHANGE` 通知环境刷新。
- 重复安装幂等：PATH 只出现一次。

## 升级行为

- 新版本安装覆盖旧版本：`edge-headless` 树整体替换；shim 文件同名覆盖；注册表 `EdgeHeadlessBin` 指向新 `$INSTDIR` 路径；PATH 条目不变（目录名稳定）。
- 多版本并存（不同 KiCad 版本目录各自携带运行时）：各版本安装器都会重写注册表指向自己；shim 优先读注册表（最后安装者生效），注册表缺失/失效时回退到最新目录。

## 卸载行为

- 删除本安装的 `$INSTDIR\bin\edge-headless` 树与 `dsh.cmd` 支持文件。
- 卸载前扫描同根下其它 KiCad 版本目录是否仍带运行时（`FindFirst/FindNext` 遍历，`$R2` 文件名变量判循环，排除 `$INSTDIR` 自身）：
  - 若**仍存在**其它运行时（`$R0=1`）：保留共享 shim 文件与 PATH 条目，只删除指向本安装的注册表值（值内容与本安装路径精确匹配时才删）。
  - 若**不存在**（`$R0=0`）：删除共享 shim 文件/目录、从 PATH 移除 shim 目录、删除注册表值，并广播环境刷新。
- 注意：NSIS `FindNext` 结束时置空的是**文件名变量**而非 handle，循环条件必须用文件名变量判断（否则死循环）。

## 验证记录

- 全量 `install.nsi` 以 NSIS 3.08 编译通过（exit 0；仅 mock staging 缺文件的 7010 告警与一条预期 6010 未引用函数告警）。
- ZIP 结构：单一根 `edge-headless\`；`bin\` 含 `node.exe`（≈93.5MB）、`hq-edge-server.cjs`（≈3.25MB）、`dsh.cmd`（162B）、`dsh-cli.cjs`（≈17.9KB）、`dsh`（POSIX 启动器，非 Windows 入口）。
- 真实链路：shim → 注册表 `EdgeHeadlessBin` → `dsh --help` 完整输出、`--version` = `0.1.5-rc.2`、exit 0。
- 回退扫描：无注册表 / 注册表指向失效路径时，均按最新目录正确回退。
- PATH 增删往返字节一致；重复 add 幂等。
- 卸载扫描循环：实测终止（迭代含 `.`/`..`，均无害）；检测到其它版本含运行时即 `R0=1`；排除 `$INSTDIR` 自身正确。

## 未做（有意保持）

- `.github/workflows/kicad-package.yml` 仅新增一步在打包前开启 `LongPathsEnabled`（CI runner 默认关闭；不是第二处下载，下载仍只归属 build.ps1）。
- 未修改 `HQ_EDGE_LAUNCHER` 契约。
- 未把 `edge-headless\bin` 加入 PATH；未用 `latest`；未用 npm。

# BMCShell IPMI

扩展包名 `bmcshell-tool-ipmi`。

执行当前目标的原生 IPMI 命令，支持二进制响应输出。 这是独立的 BMCShell 3.0 工具插件，基于本地 BMC Shell 2.22.0 发布仓的工具实现。

```bash
bmc plugin install --file .
bmc help tool ipmitool --usage
bmc use 192.0.2.10
bmc_v2_auth
bmc tool ipmitool
```

工具随目标会话激活。系统依赖为 `ipmitool`。代理由 `bmc proxy` 管理。发布时在本仓运行 `pwsh -File ./scripts/pack-release.ps1`，输出 `bmcshell-tool-ipmi@<version>.zip` 和 SHA256 清单。

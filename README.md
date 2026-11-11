# BMCShell IPMI

扩展包名 `bmcshell-tool-ipmi`。

执行原生 IPMI 命令，支持当前目标会话和二进制响应输出。这是独立的 BMCShell 3.0 工具插件，基于 BMC Shell 2.22.0 的工具实现。

```bash
bmc plugin install --file .
bmc tool ipmitool --help
bmc use 192.0.2.10
bmc_v2_auth
ipmitool chassis status
ipmitool raw 0x06 0x01 --bin > response.bin
```

工具随目标会话激活。带外默认使用 lanplus 和当前目标，省略认证选项时可使用当前目标的会话凭据。原生选项可直接传入，包括 `-I`、`-H`、`-U`、`-P` 和 `-b`。显式指定其他主机时，使用显式认证选项或 ipmitool 的原生认证流程。使用 `bmc proxy` 转发 LAN 或 LANPlus 时，需要同时更新 BMCShell 核心。

`--bin` 将 `raw` 等命令输出的十六进制字节写入标准输出，可接入管道或保存为文件。运行 `ipmitool -h` 可查看原生选项。

会话默认凭据通过 `-U` 和 `-P` 传递。普通调用在执行前向标准错误回显完整命令，例如 `==> ipmitool -I lanplus -U admin -P admin -H 192.0.2.10 chassis status`。参数使用 Bash 转义，密码明文显示。代理模式显示远端目标，`--bin` 模式关闭命令回显。显式传入的原生认证选项继续按原生方式处理。

终端中以浅灰色显示命令回显，并以青色突出 `lan print`、`mc info` 等报告的字段名。管道和重定向使用纯文本，设置 `NO_COLOR=1` 可关闭终端配色。

系统依赖为 `ipmitool`。若缺失，安装当前终端可运行的 Windows 版及其配套运行库，将可执行文件所在目录加入 PATH，然后在同一终端运行 `command ipmitool -V` 和 `bmc doctor -d`。

发布时在本仓运行 `pwsh -File ./scripts/pack-release.ps1`，输出 `bmcshell-tool-ipmi@<version>.zip` 和 SHA256 清单。

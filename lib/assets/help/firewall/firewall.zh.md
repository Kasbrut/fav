# 防火墙与端口开放

## 什么是防火墙

防火墙就像一个门卫，决定哪些网络流量被允许到达你的服务器。几乎每家云服务商都会在你的虚拟机前面运行一个防火墙，而它默认会阻止所有入站流量。

WireGuard 默认监听 **UDP 端口 51820**。为了让你的设备能够连接到服务器，必须在防火墙中明确放行这个端口。

## 你需要做什么

在你服务商的控制台中，找到防火墙设置（也可能叫做 *security group*、*cloud firewall* 或 *networking rules*），并添加一条放行以下内容的规则：

- **协议**：UDP
- **端口**：51820（或你所选择的端口）
- **来源**：任意（`0.0.0.0/0`——你的手机可能从多种网络发起连接）
- **方向**：入站

保存并应用。该规则通常在几秒内生效。

## 服务商文档

每家服务商都有各自的控制台。以下是各服务商自行维护、保持更新的官方文档链接。

| 服务商 | 文档 |
|----------|---------------|
| IONOS | https://www.ionos.com/help/server-cloud-infrastructure/firewall-policies/editing-a-firewall-policy/ |
| Hetzner Cloud | https://docs.hetzner.com/cloud/firewalls/overview |
| OVHcloud | https://help.ovhcloud.com （搜索 "VPS firewall"） |
| Aruba Cloud | https://kb.arubacloud.com （搜索 "firewall"） |
| DigitalOcean | https://docs.digitalocean.com/products/networking/firewalls/ |
| AWS Lightsail | https://docs.aws.amazon.com/lightsail/latest/userguide/lightsail-firewall.html |
| Google Cloud | https://cloud.google.com/firewall/docs/firewalls |
| Oracle Cloud | https://docs.oracle.com/iaas/Content/Network/Concepts/securityrules.htm |

> **注意**：某些服务商（特别是 **IONOS**）默认会阻止所有入站流量。如果你的安装成功了但仍然无法连接到 VPN，这是首先要检查的地方。

## 我用的是其他服务商

FAV 会配置 VPN 所需的转发和 NAT 规则，但不会修改 UFW 或其他主机防火墙来开放 WireGuard 端口。如果服务器启用了主机防火墙，请在不替换无关规则的情况下允许所选 UDP 端口。服务商控制面板中的独立防火墙仍需另行配置。

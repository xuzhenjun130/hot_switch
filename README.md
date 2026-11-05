# HotSwitch

macOS 菜单栏 CPU 温度显示（Apple Silicon），温度过高时通过 Home Assistant 自动打开风扇插座。

## 构建 & 运行
```bash
./scripts/build_app.sh        # 生成 build/HotSwitch.app
open build/HotSwitch.app
# 可选：cp -R build/HotSwitch.app /Applications/
```
开发调试：`swift run`

## 配置
点击菜单栏温度 → 「设置…」：
- **地址**：`http://192.168.100.143:8123`
- **长期访问令牌**：HA 个人资料 → 安全 → 长期访问令牌（保存在钥匙串，不写入代码）
- **插座 Entity ID**：如 `switch.xxx`，在 HA 开发者工具 → 状态 中查找
- **阈值**：默认 ≥70°C 开启，≤60°C 关闭

点「保存并测试连接」确认能读到插座状态。

## 控制逻辑
- 每 2 秒读取一次 CPU 温度，算法与 Hot 一致：有 pACC/eACC 传感器（M1–M3）时取其最大值；否则（如 M4）取所有 SMC `T*` 键与 HID 温度传感器（0–120°C，排除 tcal）中的最大值
- 连续 3 次（约 6 秒）≥ 开启阈值 → `POST /api/services/switch/turn_on`
- CPU 规则（设置中可关）：任一进程 CPU 占用 ≥ 阈值（默认 100%，即满一个核心）持续 N 秒（默认 30）→ 开启。占用由 `/bin/ps` 的累计 CPU 时间差计算，覆盖所有用户的进程；允许约 1% 的测量误差，并容忍单次采样低于阈值
- 只要还有进程高于 CPU 阈值，就不会因温度降低而关闭风扇
- 连续 15 次（约 30 秒）≤ 关闭阈值 → `POST /api/services/switch/turn_off`
- 两阈值之间保持不变（滞回，避免频繁开关）；失败每 30 秒重试
- 菜单中手动「开启/关闭」会关掉自动控制，需要时重新打开开关即可

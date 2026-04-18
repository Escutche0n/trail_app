# 技术架构原则

> 本文件描述不可轻易改变的技术基础。AI 可以扩展新模块，但不得打破以下原则。
> 架构级变更须 Elvis 明确同意。

---

## 存储

### 唯一持久化路径
- **Hive 加密盒** 是本地数据的唯一持久化出口
- 加密密钥存在 `flutter_secure_storage`（iOS Keychain `first_unlock_this_device` / Android EncryptedSharedPreferences）
- 不允许任何 SharedPreferences / UserDefaults / 明文文件作为持久化（临时 cache 除外）

### 时间写入
- 每次需要 `DateTime.now()` 写入**时间敏感字段**必须经过：
  ```dart
  TimeIntegrityService.instance.nowForWrite(op);
  ```
- 此函数在 tampered 时抛 `TimeTamperedException`
- 启动路径（首次写入 / 恢复）允许 fallback 到普通 `now()`，但必须在注释里说明

### 备份
- 导出：SignedEnvelope + HMAC-SHA256
- Domain-separated 签名（不同字段用不同 domain string 防交叉）
- 导入：先验签 → 再反序列化 → 最后落盘

---

## 时间完整性（防篡改）

四层防御缺一不可：

1. **启动时检查**：`initialize()` 对比 keychain 中的 `lastSeenMs`
2. **App resume 检查**：`onAppResumed` 时再对比一次
3. **后向跳变检查**：每次 `now()` 内部对比最近一次返回值
4. **前向跳变检查**：Stopwatch 单调锚 + wall-clock delta，> 10 分钟视为篡改

tampered 状态后：
- 所有 `nowForWrite` 抛异常
- UI 层捕获并显示 SnackBar（文案："检测到系统时间异常，请修正后再确认"）
- `now()` 返回基于 Stopwatch 的推算值，不返回 wall clock

---

## 星图架构（推导式 + overlay）

### 核心原则
- 星**不单独落盘**
- `stars = derive(frozenDates, bleEncounters)`
- `starId = hash(date + cause + friendHandle?)`（stable across devices）
- `starCoord / brightness / color = hash(starId)` 的确定性派生

### Overlay 表
- `starMeta[starId] = { name?, note?, createdAt }`
- 只存储**用户主动附加的元数据**，不存储可推导的属性
- 底层事件（frozenDates、bleEncounters）变化 → 星自动重算
- overlay 表通过 starId **软关联**：底层事件丢失时 overlay 条目变成孤儿（UI 隐藏，数据保留以防恢复）

### 禁止
- 不得为了"性能优化"把星对象 cache 到磁盘
- 不得允许用户手动修改星的坐标 / 亮度 / 颜色（打破确定性 → 打破"文物模型"哲学）

---

## BLE

### Payload 格式
- **Manufacturer Data v2**：10 字节（Company ID 0xFFF1 + 9 字节负载 + 1 字节 presence）
- v1（9 字节）向后兼容读取
- iOS localName：`tr@` + pairingHandle(6) + selfPrefix(8) + stateChar(1) + presence(2hex)

### 后台模式
- 当前 `Info.plist` 声明 `bluetooth-central` + `bluetooth-peripheral`
- **倾向删除**（等 Elvis 决策）
- 如保留，必须在 App Review Notes 说明近场场景

### 朋友状态机（4 态）
```
discoverable → pendingOutgoing / pendingIncoming → confirmed
                                    ↓
                                 (manual unfriend)
                                    ↓
                               discoverable
```

### Presence byte（v2）
- 每 8 秒最多 bump 一次
- 只在扫到已确认朋友时 bump
- 用于"mutual witness" —— 两端都看到对方 presence 在跳 = 互相在场

---

## UI

### 渲染
- CustomPainter 负责时间轴 + 星图渲染
- 60fps 目标（星图层静态部分可 cache 为 picture）

### 动画
- 严格限制：**静默为默认，动为例外**
- 允许的动画场景：
  - 节点点击反馈（bounce scale, 200ms）
  - 水平滚动磁吸（150ms easeOutCubic）
  - 垂直行磁吸（同上）
  - 冻结瞬间（星诞生 800ms）
  - BLE 相遇瞬间（朋友星闪烁一次后转为常驻慢闪）
  - 好友卡片"正在附近"脉冲（2s reverse）
- 禁止的动画场景：
  - 常驻背景粒子
  - 任何"装饰性呼吸 / 流光"
  - loading spinner（如果需要等待，用静态提示）

### 无障碍
- 所有交互点击区 ≥ 44×44pt（时间轴节点需透明扩展层）
- CustomPainter 内容需要 Semantics 覆盖层
- 关键 TextStyle 应允许 Dynamic Type 缩放（至少设置页 / 按钮 / 标题）

### 字体
- 硬编码 fontSize 可接受（为保持设计确定性）
- 使用系统字体，不引入自定义字体（避免包体积和授权问题）

---

## 代码组织

```
lib/
├── core/                 # 基础服务（time、ble、secure_box、storage）
├── services/             # 功能服务（haptic、notification）
├── models/               # 数据模型
├── pages/                # 顶层页面
└── widgets/              # 可复用组件
```

- 新功能优先在 `services/` 实现，让 `pages/` 保持薄
- `core/` 下的服务都是单例，初始化在 `main.dart`
- 不得在 `widgets/` 里直接访问 `core/`（通过 service 层）

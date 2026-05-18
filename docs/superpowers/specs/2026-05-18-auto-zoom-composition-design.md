# 设计：对齐前自动精确缩放到最佳构图

- 日期：2026-05-18
- 状态：已批准（brainstorming 完成）
- 涉及模块：`app/Cue/Camera/CameraSession.swift`、`app/Cue/App/RootView.swift`、`app/Cue/Compose/AlignmentChecker.swift`

## 1. 问题与目标

当前 AI 构图引导只用两小球指导用户**平移**手机对位，从不指导**取景大小（缩放）**。
缩放只在 AI 引导返回时按后端的 `suggested_zoom` 粗略地做一次，且发生在用户平移之前。
取景大小这一维度因此基本无人精确负责。

**目标**：在对齐前，App 自动把镜头变焦到「主体在画面里的大小 = AI 目标构图的大小」。
用户只负责平移对位，缩放完全由 App 精确完成。变焦范围扩展到 **0.5x–3x**。

**非目标**：
- 不改后端。AI 引导已返回带尺寸的目标框，本设计只是开始使用其尺寸。
- 对齐阶段（`.aligning`）不做任何缩放 —— 保持「单次缩放、不抖动」。

## 2. 关键事实：目标尺寸已存在

AI 引导（`AIGuidance`）已返回带尺寸的目标框，无需后端改动：

- Person：`pose_height`（剪影高度分数）+ 姿势模板的 `aspect` → 完整目标框
- Scene：`target_w` / `target_h` → 完整目标框

`RootViewModel.currentTarget()` 已经构造出这个带宽高的 `AlignmentTarget`。
当前 `AlignmentChecker.score()` **故意只比中心、忽略尺寸**。本设计新增「用目标框尺寸算缩放」，
对齐分数本身**不变**（仍只比中心距离）。

## 3. 缩放几何

原始 `videoZoomFactor` 线性放大画面，所以所需光学倍率为：

```
needed_optical = current_optical × (target_size / detected_size)
```

- `current_optical`：取引导返回那一刻相机的实际光学倍率（不假设为 1.0，从 `CameraSession.currentOpticalZoom` 读取）。
- `detected_size`：实测主体框尺寸，来自 `AlignmentChecker` 的实测主体框。
- `target_size`：`currentTarget()` 目标框尺寸。

**尺寸口径（detected 与 target 必须量同一个东西）**：

- **Person**：按**高度**匹配。`detected` 用 body-pose 关节包围盒高度，对 `pose_height`。
  - 只检测到人脸框（无骨架）时不可比 → 视为「不可比」，回退 `suggested_zoom`。
  - 关节包围盒高度与姿势剪影高度存在固定口径差，引入常量校准系数 `poseHeightCalibration`（初值 1.0，实现阶段在真机上标定，作为 `AlignmentChecker` 常量）。
- **Scene**：按**面积**匹配。`ratio = sqrt((target_w·target_h) / (detected_w·detected_h))`。
  - `detected` 用 `state.subjectBox`。

不可比或无检测时，`needed_optical` 回退为后端 `suggested_zoom`，按「范围内」处理（走当前路径）。

## 4. 相机层改动（`CameraSession`）

### 4.1 改用虚拟多摄设备

`makeInput(position:)` 后置镜头按优先级选择：
`builtInTripleCamera` → `builtInDualWideCamera` → `builtInDualCamera` → `builtInWideAngleCamera`（兜底）。
前置维持 `builtInWideAngleCamera`（前摄无超广角）。

虚拟多摄设备在普通 `AVCaptureSession` 里会随 `videoZoomFactor` 自动切换物理镜头，
**不需要** `AVCaptureMultiCamSession`。`sessionPreset = .photo`、人像旋转、photo 输出均照常工作。

### 4.2 光学倍率 ↔ 原始倍率映射

虚拟设备上 `videoZoomFactor = 1.0` 是超广角（UI 的 0.5x），主摄「1x」在原始倍率约 2.0。
新增纯值类型 `ZoomMapping`（无设备依赖、可单测）封装换算：

- 输入：`oneXRawFactor`（主摄 1x 对应的原始倍率）、`minRaw`、`maxRaw`。
  - `oneXRawFactor = device.virtualDeviceSwitchOverVideoZoomFactors.first ?? 1.0`
    （多摄设备首个切换点即 UW→W，等于 1x；单摄设备无切换点，为 1.0）。
  - `minRaw = device.minAvailableVideoZoomFactor`、`maxRaw = device.maxAvailableVideoZoomFactor`。
- `rawFor(optical:) = optical × oneXRawFactor`
- `minOptical = minRaw / oneXRawFactor`（多摄≈0.5，单摄=1.0）
- `maxOptical = min(maxRaw, 3.0 × oneXRawFactor) / oneXRawFactor`，上限取 3.0
- `clampOptical(_:)`：把光学倍率钳到 `[minOptical, maxOptical]`

> 实现备注：iOS 18 提供 `displayVideoZoomFactorMultiplier`，但本设计用
> `virtualDeviceSwitchOverVideoZoomFactors` 推导，避免依赖单一 iOS 版本。

### 4.3 接口改动

- `setZoom(_ optical: CGFloat)`：入参改为**光学倍率**（0.5–3.0 口径）。
  内部经 `ZoomMapping` 换算为原始 `videoZoomFactor` 再 `device.ramp(...)`。
- 新增只读属性：`currentOpticalZoom: CGFloat`、`minOpticalZoom: CGFloat`、`maxOpticalZoom: CGFloat`。
  这些在 `sessionQueue` 上更新、`@MainActor` 侧读取的最近值（用轻量同步快照，下游只需近似值）。
- idle 复位仍调 `setZoom(1.0)`，现在语义为「光学 1x 主摄」—— 保证待机预览不是超广角。
  `RootViewModel` 里 `setZoom(1.0)` 的三处调用（cancel、applyZoom 入口、capture 后复位）语义不变。

## 5. 流程与状态机（`RootViewModel`）

### 5.1 新增 `FlowState.framing(since: Date())`

仅在「变焦够不到目标尺寸、需要用户走动」时可见。范围内时不进入此状态。

### 5.2 引导返回后的分支

```
guidance 返回（subjectType ≠ empty）
  → 计算 needed_optical（§3）
  → 不可比/无检测：needed = suggested_zoom，按「范围内」处理
  → needed 在 [minOptical, maxOptical] 内：
        applyZoom(needed) → proceedToAlignment()                （常见，无感）
  → needed 超出范围：
        applyZoom(clampOptical(needed)) → state = .framing       （可见，等用户走动）
```

`proceedToAlignment()`（抽取的共用尾段）：
`sleep 600ms 等 ramp 稳定 → 校验未取消 → 已构图良好则直接拍 → 否则 beginTracking + state = .aligning`。
即当前 `requestGuidance` 第 127–149 行的逻辑原样抽成方法，两条路径共用。

### 5.3 `.framing` 状态行为

由预览帧驱动新方法 `updateFraming()`（`cameraDidEmitPreview` 中、与 `updateAlignment()` 并列）：

- 每帧用当前实测主体框重算 `needed_optical`。
- 去抖：连续 3 帧落在 `[minOptical, maxOptical]` 内才动作（消除单帧检测抖动）。
- 横幅提示（复用 `statusBanner`）：
  - `needed < minOptical`（主体太大）→「后退一点」
  - `needed > maxOptical`（主体太小）→「靠近一点」
- 一旦稳定回到范围内：`applyZoom(needed)` → 清横幅 → `proceedToAlignment()`。
- 超时：进入 `.framing` 超过 8s 仍未回到范围 → 用钳制后的倍率 best-effort，清横幅 → `proceedToAlignment()`。

### 5.4 其他状态机改动

- `toggleAIGuidance()`：`.framing` 并入可取消分支（与 `.analyzing` / `.aligning` 一致）。
- `cancelGuidance()`：从 `.framing` 取消时同样复位 `state = .idle`、`setZoom(1.0)`、清横幅。
- `RootView` 中 `isBusy` / `canFlip` / `aiIcon`：`.framing` 视同 analyzing/aligning
  （非 busy、不可翻转、AI 按钮显示 `xmark`）。
- `RootView.body`：`.framing` 时显示相机预览 + `CompositionOverlay` + `statusBanner`，
  不显示 `LoadingOverlay`（仅 `.analyzing`）、不显示 `AlignmentView`（仅 `.aligning`）。
  `isAnalyzing` 保持仅对 `.analyzing` 为真。

## 6. `AlignmentChecker` 改动

新增可单测的纯函数（不改动现有 `score()`）：

- `measuredSubject(kind:state:) -> (size: CGSize, comparable: Bool)?`
  - Person：有 body-pose 关节 → 关节包围盒尺寸、`comparable = true`；
    仅人脸 → 人脸框尺寸、`comparable = false`；都无 → `nil`。
  - Scene：`subjectBox` 尺寸、`comparable = true`；无 → `nil`。
- `neededOpticalZoom(target:measured:currentOptical:calibration:) -> Double`
  - Person 按高度比、Scene 按面积比（§3 公式），乘 `currentOptical`。
- 新增常量 `poseHeightCalibration: Double`（初值 1.0）。

## 7. 边界与风险

- **旧机型**（如 iPhone SE）只有单摄 → 走 `builtInWideAngleCamera` 兜底，`minOptical = 1.0`，
  无 0.5x；「后退」提示在 1x 触发。逻辑通用，无需特判。
- **前摄**：单摄、`minOptical = 1.0`，逻辑同上。
- **虚拟设备验证**：前/后摄翻转、人像旋转、photo 输出需在多摄设备上回归验证。
- **关节包围盒 vs 姿势剪影口径差**：靠 `poseHeightCalibration` 吸收，真机标定。
- **mid-ramp 帧**：缩放 ramp 约 500ms，期间帧的实际倍率不确定 —— 仅在 ramp 稳定后测量
  （`proceedToAlignment` 的 600ms 等待、`.framing` 等待用户走动时倍率已稳定）。
- `currentOpticalZoom` 跨 `sessionQueue`/`MainActor` 读取最近值，下游只需近似，可接受。

## 8. 测试策略

**单元测试（纯逻辑，无设备）**：
- `ZoomMapping`：`rawFor(optical:)`、`minOptical` / `maxOptical`、`clampOptical` 钳制
  （覆盖多摄 oneX=2.0 与单摄 oneX=1.0 两种）。
- `AlignmentChecker.neededOpticalZoom`：person 高度比、scene 面积比、`currentOptical ≠ 1` 情形。
- `AlignmentChecker.measuredSubject`：pose / face-only / scene / 空 各分支与 `comparable` 标志。

**真机/手动验证**：
- 多摄镜头随缩放自动切换；0.5x 下限可达。
- 主体太大 → `.framing` +「后退一点」；走远后自动结束并进入对齐。
- 主体太小 → `.framing` +「靠近一点」。
- `.framing` 超时兜底；`.framing` 期间按 AI 按钮可取消。
- 前摄回退、idle 预览为主摄 1x 非超广角。

## 9. 改动文件清单

- `app/Cue/Camera/CameraSession.swift`：多摄设备选择、`ZoomMapping`、`setZoom` 改光学口径、新增缩放属性。
- `app/Cue/Compose/AlignmentChecker.swift`：新增 `measuredSubject`、`neededOpticalZoom`、校准常量。
- `app/Cue/App/RootView.swift`：`FlowState.framing`、缩放计算分支、`updateFraming()`、
  `proceedToAlignment()` 抽取、状态机/UI 分支接入。
- 新增测试文件：`ZoomMapping` 与 `AlignmentChecker` 缩放逻辑的单元测试。

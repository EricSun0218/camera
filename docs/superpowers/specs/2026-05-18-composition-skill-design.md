# 设计：构图 skill（Composition Skill）

- 日期：2026-05-18
- 状态：已批准（brainstorming 完成）
- 涉及模块：`web/lib/composition-skill.ts`（新建）、`web/lib/prompts.ts`（删除）、`web/app/api/guidance/route.ts`（改）

## 1. 问题与目标

`/api/guidance`（AI 构图引导）当前用 `web/lib/prompts.ts` 的 `GUIDANCE_SYSTEM_PROMPT_V4` 作 system prompt。
该 prompt 约 80% 是机械部分（输出 schema、person/scene/empty 判定、JSON 格式），
真正的构图专业知识只有零星几条（三分法、头部空间、几个按类型的框尺寸）。
它**不是** `colorist-skill.ts` 那种结构化专家模块。

**目标**：新建 `web/lib/composition-skill.ts` —— 一个版本化的构图专家知识模块，
完全对标 `colorist-skill.ts`，成为 `/api/guidance` 的 system prompt。
模型产出 `target box / pose / zoom` 这些数字的**推理质量**大幅提升。

**非目标**：
- 不改 `AIGuidance` 输出 schema —— iOS 端零改动。
- 拍摄类型分类是**模型内部推理**，不作为输出字段（与 colorist 的 `scene`/`lighting`/`rationale` 不同）。

## 2. 文件结构

- **新建** `web/lib/composition-skill.ts`：导出 `COMPOSITION_SKILL`（完整 prompt 字符串）
  和 `COMPOSITION_SKILL_VERSION = 'composition-skill-v1'`。文件头注释对标
  `colorist-skill.ts` 的写法（说明用途、模型只输出 AIGuidance JSON、改此文件即可演进）。
- **删除** `web/lib/prompts.ts`：它当前只装 `GUIDANCE_SYSTEM_PROMPT_V4` 和一条注释，
  内容迁走后即空。`colorist` 当初也是这样从 `prompts.ts` 独立成模块的。
- **改** `web/app/api/guidance/route.ts`：import 从
  `import { GUIDANCE_SYSTEM_PROMPT_V4 } from '@/lib/prompts'` 换成
  `import { COMPOSITION_SKILL } from '@/lib/composition-skill'`，`system:` 字段同步。
- 实现前需 grep 确认 `GUIDANCE_SYSTEM_PROMPT_V4` / `@/lib/prompts` 无其它引用残留。

## 3. Skill 内容结构

`COMPOSITION_SKILL` 采用 `colorist-skill.ts` 的章节式结构：

1. **角色行** —— "You are Cue's composer …"，定位为一名大师级摄影师之眼。
2. **PHILOSOPHY（不可违背）** —— 核心原则，含 §4 的 Cue 专属约束。建议条目：
   - ONE SUBJECT, ONE STORY —— 选定唯一清晰主体，构图为它服务。
   - PLACEMENT IS INTENT —— 默认不居中；主体放三分线/交点，除非对称是刻意的。
   - ROOM TO BREATHE —— 主体视线/运动方向留余量（look-room），头部空间正确。
   - FILL WITH PURPOSE —— 主体应主宰画面；留白必须是刻意的负空间，不是失误。
   - EXPRESSIBLE GUIDANCE ONLY —— 见 §4。
3. **WORKFLOW（推理顺序）**：A 读懂画面、锁定唯一主体 → B 内部分类拍摄类型
   → C 选匹配的构图原则、定主体位置与大小 → D 翻译成输出数字。
4. **COMPOSITION PRINCIPLES** —— 构图法则库，每条「一句定义 + 何时用 + 何时失效」：
   三分法（默认）、引导线、框架式、视觉平衡/视觉重量、负空间、充满画面、
   对称与重复、纵深分层（前/中/后景）、简化、奇数法则、主体-背景分离、
   对角线与三角、黄金比例（作为三分法的微调，不单列模式）。
5. **PLACEMENT RULES** —— 头部空间；眼睛置于距顶约 1/3；视线/运动方向留 look-room
   （主体朝左则放右三分）；地平线放三分线、保持水平；危险区：勿在关节处裁切、
   勿让背景元素「长出」主体（merger）。
6. **SHOT-TYPE RECIPES** —— 按类型给具体配方，每类含「主体占画面比例 + 位置 +
   常见错误」：人像（单人）、合影、全身、抓拍/街拍、风光、建筑、美食、
   产品/静物、宠物/动物、室内、其他。数值需具体（如人像脸占画面高约 55–70%）。
7. **TASK** —— 步骤：① 定 subject_type（机械部分，见 §5）② 内部分类拍摄类型
   ③ 套用匹配配方 ④ 按 OUTPUT FORMAT 输出。
8. **OUTPUT FORMAT** —— 严格 JSON，原样保留（见 §5）。

内容素材来自已完成的网络调研（交叉验证多个权威摄影来源），覆盖上述全部法则与
按类型配方及其具体数值。调研结论摘要见本设计的姊妹研究记录（brainstorming 阶段产出）。

## 4. Cue 专属约束（关键）

这是泛泛构图教程不会有、但本 skill 必须写死的，让 skill 贴合本 App：

- **引导只能表达为「主体位置 + 主体大小 + zoom」**。用户通过**平移手机**对齐位置，
  App **自动缩放**到目标框大小（已上线的 auto-zoom 功能）。因此镜头**高度/角度**类
  构图建议（蹲到宠物视线、低角度显气势等）**无法表达** —— skill 明确说明不在此浪费推理。
- **目标框尺寸 = 取景大小**，现在直接驱动 auto-zoom。`target_w/h` 与 `pose_height`
  是一等输出，必须按「理想取景」精确给定，不可随意。
- **目标框须放在平移够得到的位置** —— 不假设用户走位。
- `suggested_zoom` 降级为粗略 fallback（iOS 已改为从目标框尺寸算精确 zoom）。
  skill 仍产出合理值，但推理重心在目标框本身。

## 5. 原样保留的机械部分

`/api/guidance` 用 `AIGuidanceSchema` 解析；解析失败会静默降级到 `defaultSceneGuidance`。
以下来自 `GUIDANCE_SYSTEM_PROMPT_V4` 的内容必须等价保留（措辞可融入新结构，语义不变）：

- person / scene / empty 三态判定，含**强烈偏向 scene、empty 几乎不用**的规则
  （镜头被遮挡 / 全黑 / 完全无法辨识才算 empty）。
- `pose_id` 的 8 个枚举值：`stand, arms_open, walk, wave, yoga, mind_body, dance, child_lift`。
- 各字段数值范围：`pose_x/y` 0..1、`pose_height` 0.3..0.95、`target_x/y` 0..1、
  `target_w/h` 0.1..1、`suggested_zoom` 1..3。
- person 模式输出 pose 字段、scene 模式输出 target 字段、empty 时省略其它字段。
- 严格 JSON 输出、无散文、无 markdown 围栏。

即：**新 skill = 等价保留的机械部分 + 大幅增强的构图专业知识**。

## 6. 测试与验证

prompt 字符串无法做有意义的单元测试，验证方式：

- `web` 端 `npm run build` / 类型检查通过（路由 import 改动正确）。
- grep 确认 `GUIDANCE_SYSTEM_PROMPT_V4` 与 `@/lib/prompts` 无残留引用。
- 轻量字符串断言（如有 web 测试框架）：`COMPOSITION_SKILL` 含 OUTPUT FORMAT 锚点
  与全部 8 个 `pose_id` 枚举值 —— 防止改写时把机械部分弄丢。
- 对 `/api/guidance` 用样张做一次真实 eval 调用，确认返回合法 `AIGuidance` JSON
  （防止 prompt 改写把输出格式带歪 —— 路由有 fallback 不会崩，但引导质量会静默退化）。

## 7. 改动文件清单

- 新建：`web/lib/composition-skill.ts`
- 删除：`web/lib/prompts.ts`
- 修改：`web/app/api/guidance/route.ts`（import + `system:` 字段）

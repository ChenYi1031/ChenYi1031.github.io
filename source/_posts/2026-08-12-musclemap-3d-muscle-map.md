---
title: MuscleMap：用 Three.js 打造 3D 肌肉激活图谱
date: 2026-08-12 10:00:00
tags:
  - Three.js
  - TypeScript
  - 3D
  - 可视化
  - 健身
categories:
  - 技术分享
description: MuscleMap 项目复盘：基于 Three.js 和真实解剖学模型，做一个能高亮训练动作目标肌群、还能播放动作模拟动画的 3D 肌肉图谱——模型加载、三级高亮、泵感动画、动作预览与无障碍支持的实现思路。
---

# MuscleMap：用 Three.js 打造 3D 肌肉激活图谱

MuscleMap 是我给自己健身做的一个小工具。起因很简单：练背的日子到底练到了哪些肌肉？硬拉和高位下拉的发力区别在哪？网上答案全是文字描述，很难有画面感。所以我做了一个 3D 可视化的肌肉图谱——选中一个训练动作，3D 人体模型上直接把**主要发力肌、次要发力肌、辅助稳定肌**用不同颜色高亮出来，还能播放动作模拟动画。

项目地址：[ChenYi1031/musclemap](https://github.com/ChenYi1031/musclemap)

## 功能设计

先想清楚要什么，再动手：

- **3D 人体肌肉模型**：不是示意图，而是真实解剖结构，12 块肌肉独立可交互
- **三级高亮**：主要发力肌 / 次要发力肌 / 辅助稳定肌，用三种颜色区分
- **三分化训练日**：按「背+二头」「胸+三头」「腿+核心」组织 23 个常用动作
- **反向查询**：点模型上的某块肌肉，反查有哪些动作练它——这个功能对排计划特别有用
- **动作模拟动画**：选中动作后，模型同步做对应动作，目标肌肉有"泵感"收缩

## 3D 模型方案

自己从零建 3D 解剖模型不现实，我选了开源的 [3DMuscleSelector](https://github.com/cadenmarinozzi/3DMuscleSelector) 作为基础。它最大的优点是：人体不是一个整体 mesh，而是**按肌肉拆分成 12 个独立网格**（胸大肌、背阔肌、三角肌、二头肌、三头肌、股四头肌、臀大肌等）。

这一点直接决定了后面所有交互的实现方式——每块肌肉是一个独立的 Object3D，可以独立改材质、独立响应 raycast：

```typescript
// 加载模型后，按名称把肌肉网格注册进映射表
const muscleMap = new Map<string, THREE.Mesh>();
model.traverse((child) => {
  if (child.isMesh && MUSCLE_NAMES.has(child.name)) {
    muscleMap.set(child.name, child);
    child.userData.baseColor = (child.material as THREE.MeshStandardMaterial).color.clone();
  }
});
```

## 三级高亮的实现

高亮的核心不是"换个颜色"这么简单，直接改 color 会显得很突兀。我做两层处理：

1. **颜色过渡**：不瞬间切换，而是每帧向目标颜色做插值（lerp），肌肉看起来是"充血"而不是"变色"
2. **层级区分**：主要发力肌用深红 + 脉冲动画（emissive 强度做正弦波动），次要发力肌用中红，辅助稳定肌用浅红——一眼就能分清主次

```typescript
function highlight(muscle: THREE.Mesh, level: MuscleLevel) {
  const target = LEVEL_COLORS[level];
  const mat = muscle.material as THREE.MeshStandardMaterial;
  // 每帧 lerp 到目标色，实现平滑过渡
  mat.color.lerp(target, 0.12);
  // 主要发力肌额外加 emissive 脉冲
  if (level === 'primary') {
    mat.emissiveIntensity = 0.25 + 0.15 * Math.sin(performance.now() * 0.004);
  }
}
```

悬停时的轻量高亮也复用同一套逻辑，只是目标色更淡，鼠标移开自然过渡回去。

## 动作模拟动画：泵感

这是整个项目最花时间也最出效果的部分。选中「二头弯举」后，模型不只是一块肌肉变红，而是**真的在做弯举**：小臂绕肘关节旋转，二头肌跟着节奏"收缩"。

实现分两部分：

- **关节运动**：23 个动作各配一组关键帧（哪些关节、什么角度、什么节奏），用简单的插值驱动。深蹲是髋膝同时屈伸，硬拉是俯身，转体是腰——每个动作手工调出来的
- **泵感收缩**：目标肌肉的网格沿特定轴做节奏性的增厚（scale 微调），配合动作节奏同步呼吸感。幅度必须克制，scale 放太大会穿模、太小看不出来，最后定在 5%~8% 的脉冲幅度

## 动作预览模式

后来又加了一个更彻底的模式：一键切换到**绑定骨骼的 3D 角色**（Mixamo 风格骨骼），由角色真实表演所选动作的肢体运动——屈膝下蹲、屈肘弯举、举腿、卷腹都由骨骼驱动，比在人体模型上挪顶点自然得多。

肌肉模型负责"哪里发力"，骨骼角色负责"动作长什么样"，两个视角互补。

## 交互与无障碍

- 鼠标拖拽旋转（左右 180°），滚轮缩放，正面/背面视角平滑切换
- 肌肉悬停高亮反馈 + 主要发力肌脉冲动画
- `prefers-reduced-motion` 支持：系统开启"减少动态效果"时自动关闭所有动画。3D 应用很容易忽略这一点，但对晕动症用户很关键

```css
@media (prefers-reduced-motion: reduce) {
  .muscle-pulse { animation: none; }
}
```

JS 侧同样监听 `matchMedia('(prefers-reduced-motion: reduce)')`，把动画开关收进一个全局配置。

## 小结

这个项目的体量不大（23 个动作、12 块肌肉），但把 Three.js 的几个核心环节都走了一遍：模型加载与网格拆分、raycast 拾取、材质与 emissive 动画、骨骼动画、无障碍适配。最大的收获是体会到 **3D 交互的难点不在渲染，而在"动效的克制"**——泵感幅度、颜色过渡速度、视角切换缓动，每一个参数都是试出来的。

如果你也想做类似的东西，建议第一步就是确认模型是不是按部件拆分好的 mesh，这决定了后面 80% 的交互能不能做。

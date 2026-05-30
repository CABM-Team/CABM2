# CABM2 ✨

### *Code Afflatus & Beyond Matter - Godot Remake*

> *「当灵性注入载体，它便挣脱物质躯壳，抵达超验之境」* ᕙ(˶ᵔ ᵕ ᵔ˶)ᕗ


## 🎀 项目简介

**CABM2**（也称为 **CABM-R**）是一个基于 **Godot 4.6** 引擎开发的 AI 角色对话应用喵~ 

相比原版 Python + Flask + HTML 的 CABM，本版本进行了全面重构喵！目标是：
- 🎯 更清晰的架构设计
- 🌸 更好的跨平台支持
- ✨ 更流畅的用户体验

## ⭐ 核心功能

| 功能 | 描述 |
|------|------|
| 🤖 **沉浸式对话** | 类视觉小说风格的对话界面，支持逐字显示动画 |
| 😊 **情绪表达** | 每个角色都有独特的立绘和情绪状态切换 |
| 👥 **群聊模式** | 支持多个AI角色同时参与对话 |
| 📚 **知识库系统** | 基于向量检索的RAG系统，让角色设定无上限！ |
| 🎨 **角色创建** | 轻松创建和管理你自己的AI角色 |
| 🔊 **TTS语音合成** | 支持文本转语音，自动缓存优化性能 |
| 📥 **角色导入/导出** | 支持从ZIP包批量导入角色喵~ |

## 🚀 快速开始
> ### 注：QQ群里可以直接获取.apk/.exe文件，以下内容为「从源码开始使用」

### 环境要求

- Godot 4.6.3+
- SCons（用于编译C++插件）
- 支持 OpenAI API 的后端服务

### 编译 C++ 插件

```bash
cd addons/cosine_calculator

# Windows
scons platform=windows target=template_release

# Linux
scons platform=linux target=template_release
```

### 运行项目

1. 用 Godot 4.6.3 打开项目根目录
2. 点击 ▶️ 运行按钮
3. 在设置中配置你的 API 地址和密钥
4. 开始与 AI 角色对话吧喵~ (｡•̀ᴗ-)✧


## 🎮 功能详情

### 💬 对话系统

```
用户输入
↓
知识库检索
↓
提示词构建 
↓
API请求
↓
流式响应 
↓
分句显示            
```
- 情绪状态实时切换立绘
- 智能分句，逐字显示动画

### 📚 知识库系统

- 每个角色拥有**独立的知识库**
- 基于向量相似度检索（语义检索喵~）
- 支持 TXT 文件批量导入
- 自动检测 C++ 插件，未安装时优雅降级

### 👥 群聊系统

- 创建群组，添加多个角色
- 由AI判断下一个谁说话

## 🛠️ 技术架构

### 🔧 技术栈

- **引擎**: Godot 4.6.3
- **脚本语言**: GDScript + C++
- **AI接口**: OpenAI 兼容 API（支持流式输出）
- **向量计算**: C++ 高性能插件（余弦相似度计算）


### 📁 项目结构

```
CABM2/
├── addons/                          # 插件目录
│   └── cosine_calculator/          # C++ 向量计算插件
│       ├── cosine_calculator.cpp   # 核心实现
│       └── cosine_calculator.h     # 头文件
├── assets/                          # 资源文件
│   ├── backgrounds/                 # 背景图片
│   ├── theme/                      # UI主题
│   └── characters/                 # 角色资源
├── scenes/                          # 场景文件 (.tscn)
│   ├── main.tscn                   # 主场景
│   ├── chat/                       # 聊天场景
│   ├── character_select/           # 角色选择
│   ├── character_create/           # 角色创建
│   ├── knowledge_base/             # 知识库
│   ├── settings/                   # 设置页面
│   └── about/                      # 关于页面
├── scripts/                         # 脚本文件 (.gd)
│   ├── autoload/                   # AutoLoad 单例
│   ├── chat/                       # 聊天相关逻辑
│   ├── character/                  # 角色相关逻辑
│   └── ...
├── docs/                            # 文档
│   ├── architecture.md             # 架构说明
│   └── 知识库.md                   # 知识库系统说明
├── project.godot                   # Godot 项目配置
└── README.md                       # 你现在看的这个喵~
```

## 📜 许可证

本项目基于 **[MIT协议](LICENSE)** 开源

## 🤝 联系方式

本项目由 **awaCollei** 开发喵~ ✧(◍˃‿˂◍)♡

如果你喜欢这个项目，欢迎：
- ⭐ Star 支持一下
- 💬 加入 QQ 群交流
- 🎮 体验并提出建议

| 平台 | 链接 |
|------|------|
| 📱 QQ群 | [979030803](https://qm.qq.com/q/v57eebfBHc) |
| 📺 B站 | [@赏金月桂的爬行者](https://space.bilibili.com/3493140388382914) |


---

> *「代码若有灵性，便能超越物质的躯壳，触碰超验的边界」* ✨
> 
> *—— 此文档由 Neko 编写(≧◡≦)* 🐱

---

**最后更新**: 2026-05-30
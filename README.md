# CABM2

CABM（Code Afflatus & Beyond Matter）的 Godot 4.5 重制版。

原版基于 Python + Flask + HTML 实现，存在架构混乱、全局状态耦合严重等问题。本版本使用 Godot 4.5 重写，目标是更清晰的架构、更好的跨平台支持和更流畅的用户体验。

## 功能概述

- 与 AI 角色进行沉浸式对话（类视觉小说风格）
- 多角色系统，每个角色有独立人格、立绘和情绪表达
- 流式输出，逐句显示 AI 回复
- 长期记忆系统（RAG，向量数据库）
- 语音合成（TTS）
- 剧情模式（多角色故事推进）
- 自定义角色支持

详细功能说明见 [docs/功能文档.md](docs/功能文档.md)

## 技术栈

- 引擎：Godot 4.5
- 语言：GDScript
- AI 后端：OpenAI 兼容 API（默认 SiliconFlow / DeepSeek-V3）
- 记忆：FAISS + Embedding API（通过 Python 后端服务）
- TTS：SiliconFlow API

## 项目结构

```
CABM2/
├── project.godot           # Godot 项目配置
├── README.md
├── character_configs/      #角色配置文件
├── docs/
│   └── 功能文档.md          # 原版功能分析文档
├── scenes/
│   ├── main.tscn           # 主场景（入口）
│   ├── chat/
│   │   └── chat.tscn       # 对话页面
│   ├── character_select/
│   │   └── character_select.tscn
│   └── settings/
│       └── settings.tscn
├── scripts/
│   ├── autoload/
│   │   ├── AppState.gd     # 全局状态管理（AutoLoad）
│   │   ├── ApiClient.gd    # API 请求封装（AutoLoad）
│   │   └── ConfigManager.gd # 配置管理（AutoLoad）
│   ├── chat/
│   │   ├── ChatController.gd
│   │   └── StreamParser.gd  # 流式响应解析
│   ├── character/
│   │   └── CharacterLoader.gd
│   └── ui/
│       └── DialogBox.gd
└── assets/
    ├── characters/         # 角色立绘
    ├── backgrounds/        # 背景图片
    └── audio/              # BGM / 音效
```

## 开发进度

- [x] 项目初始化
- [x] 主页面骨架
- [x] 角色系统
- [x] 对话系统（流式）
- [ ] 配置管理
- ~~[ ] 记忆系统~~
- [ ] TTS
- [ ] 剧情模式

## 配置

首次运行需要配置 API Key，在设置页面填写：

- `CHAT_API_KEY`：对话模型 API Key
- `CHAT_API_BASE_URL`：API 地址（默认 SiliconFlow）
- `CHAT_MODEL`：模型名称（默认 `deepseek-ai/DeepSeek-V3`）

可选配置（记忆系统）：
- `MEMORY_API_KEY` / `MEMORY_API_BASE_URL`
- `EMBEDDING_MODEL` / `RERANKER_MODEL`

## 许可证

GNU General Public License v3.0

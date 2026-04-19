# 对话系统架构说明

## 文件职责划分

### 1. ChatController.gd
**职责**: 对话主循环控制器
- 消息输入输出
- 角色立绘切换（根据 mood）
- 逐字显示动画
- 用户交互（点击继续、输入消息）
- 历史记录显示（从 JSON 中提取 msg 字段）
- 思考动画（"." ".." "..."）

### 2. PromptBuilder.gd
**职责**: 构建完整提示词
- 将原始消息数组转换为 API 请求格式
- 注入情绪格式要求到 system 消息
- 构建 mood 列表说明
- 指定 AI 返回格式：`{"mood": <int>, "msg": <string>}`

### 3. ApiClient.gd
**职责**: 发送流式请求和提取字段
- 发送 HTTP 流式请求
- 解析 SSE 数据流
- 提取 `msg` 字段（逐字 emit，用于显示）
- 提取 `mood` 字段（整数或字符串）
- 累积完整的 JSON 响应（用于保存历史）
- 错误处理

### 4. sentence_splitter.gd
**职责**: 分句
- 按标点符号分句
- 处理括号内容
- 处理省略号规则
- 流式分句（维护状态）

### 5. AppState.gd
**职责**: 全局状态管理
- 管理当前角色数据
- 管理对话历史
- 历史记录裁剪（保留 system 消息）

## 数据流

```
用户输入
  ↓
ChatController._send_message()
  ↓
AppState.add_message("user", text)
  ↓
PromptBuilder.build_messages() → 构建完整提示词（要求返回 JSON）
  ↓
ApiClient.chat_completion() → 发送请求
  ↓
ApiClient 解析流式响应
  ├─ stream_mood → ChatController._on_stream_mood() → 切换立绘
  ├─ stream_chunk → ChatController._on_stream_chunk() → 显示 msg 字段
  └─ stream_full_json → ChatController._on_stream_full_json() → 保存完整 JSON
       ↓
     SentenceSplitter.split_stream() → 分句
       ↓
     ChatController._enqueue_sentence() → 加入队列
       ↓
     ChatController._show_text() → 逐字显示
       ↓
     AppState.add_message("assistant", full_json) → 保存完整 JSON
       ↓
     HistoryManager.save_history() → 持久化到磁盘
```

## AI 响应格式

AI 返回的是 JSON 格式：
```json
{
  "mood": 2,
  "msg": "你好呀！今天过得怎么样？"
}
```

### 数据处理策略

1. **保存到历史**: 保存完整的 JSON 字符串
   - `AppState.chat_history` 中 assistant 消息的 content 字段存储完整 JSON
   - `HistoryManager` 保存到 JSONL 文件时也是完整 JSON

2. **发送给 AI**: 发送完整的 JSON 字符串
   - `AppState.get_messages_for_api()` 返回包含完整 JSON 的消息数组
   - AI 可以看到之前的完整响应格式，保持上下文一致性

3. **显示给用户**: 只显示 `msg` 字段
   - `ChatController._extract_msg_from_json()` 提取 msg 字段用于显示
   - 历史记录页面、角色卡片都使用此方法提取显示内容

## 重构要点

1. **职责分离**: 每个文件只负责一个明确的功能
2. **单一分句**: 只在 `sentence_splitter.gd` 中分句，其他地方不再重复分句
3. **提示词构建**: 从 ApiClient 中分离出 PromptBuilder，便于维护和测试
4. **流式解析**: ApiClient 专注于 HTTP 和字段提取，不处理分句逻辑
5. **数据完整性**: 保存和传输完整 JSON，显示时才提取字段
6. **字段命名**: 使用 `msg` 而非 `content`，避免与 HTTP 响应体的 content 字段混淆

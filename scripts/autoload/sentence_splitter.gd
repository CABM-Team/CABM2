# sentence_splitter.gd
# 统一管理文本分句逻辑的模块
# 实现了对普通句子和括号内句子的智能切分
class_name SentenceSplitter

# 定义中文标点符号，用于切分句子
const CHINESE_PUNCTUATION = ["。", "！", "？", "；"]

# 定义省略号
const ELLIPSIS = "……"

# 定义中文括号
const LEFT_PAREN_CN = "（"
const RIGHT_PAREN_CN = "）"

# 定义英文括号
const LEFT_PAREN_EN = "("
const RIGHT_PAREN_EN = ")"

# 定义所有左括号和右括号集合，方便查找
const ALL_LEFT_PARENS = [LEFT_PAREN_CN, LEFT_PAREN_EN]
const ALL_RIGHT_PARENS = [RIGHT_PAREN_CN, RIGHT_PAREN_EN]

# 省略号分割规则参数
const ELLIPSIS_MAX_LENGTH = 30      # 超过30字强制分割
const ELLIPSIS_MIN_INTERVAL = 6     # 与上一个省略号间隔超过6字则分割

# 专门用于流式分句的状态对象
class StreamState:
	var buffer: String = ""
	var in_paren: bool = false
	var last_ellipsis_pos: int = -1   # 记录上一个省略号在buffer中的位置

	func _init():
		buffer = ""
		in_paren = false
		last_ellipsis_pos = -1

# 内部方法：切分一个文本块（普通文本或括号内的文本）
# chunk_text: 要切分的文本字符串
# is_in_paren: 一个布尔值，指示这个文本块是否来自括号内部
# 返回一个数组，每个元素是一个包含 "text" 和 "no_tts" 标志的字典
static func _split_chunk(chunk_text: String, is_in_paren: bool) -> Array:
	var sentences = []
	var buffer = chunk_text.strip_edges()
	if buffer.is_empty():
		return []
	
	var last_ellipsis_pos = -1  # 用于记录当前处理过程中的上一个省略号位置

	while not buffer.is_empty():
		var earliest_pos = -1
		var found_punct_type = ""  # "normal", "ellipsis"
		var found_left_paren = false
		var found_right_paren = false
		
		# 括号优先级最高：先查找括号
		# 查找左括号
		for paren_char in ALL_LEFT_PARENS:
			var l_pos = buffer.find(paren_char)
			if l_pos != -1 and (earliest_pos == -1 or l_pos < earliest_pos):
				earliest_pos = l_pos
				found_left_paren = true
				found_punct_type = ""
		
		# 查找右括号
		for paren_char in ALL_RIGHT_PARENS:
			var r_pos = buffer.find(paren_char)
			if r_pos != -1 and (earliest_pos == -1 or r_pos < earliest_pos):
				earliest_pos = r_pos
				found_right_paren = true
				found_punct_type = ""
		
		# 如果没有找到括号，再查找省略号
		if not found_left_paren and not found_right_paren:
			var ellipsis_pos = buffer.find(ELLIPSIS)
			if ellipsis_pos != -1 and (earliest_pos == -1 or ellipsis_pos < earliest_pos):
				earliest_pos = ellipsis_pos
				found_punct_type = "ellipsis"
		
		# 如果没有找到括号和省略号，再查找普通标点
		if not found_left_paren and not found_right_paren and found_punct_type != "ellipsis":
			for punct in CHINESE_PUNCTUATION:
				var pos = buffer.find(punct)
				if pos != -1 and (earliest_pos == -1 or pos < earliest_pos):
					earliest_pos = pos
					found_punct_type = "normal"
		
		var sentence_text = ""
		if earliest_pos == -1:
			# 如果没有找到任何切分点，整个剩余部分就是一句话
			sentence_text = buffer
			buffer = "" # 清空 buffer
		else:
			# 找到了切分点，根据类型处理
			if found_left_paren:
				# 遇到左括号：立即切分括号之前的内容
				sentence_text = buffer.substr(0, earliest_pos).strip_edges()
				buffer = buffer.substr(earliest_pos)  # 保留左括号，让外层括号处理逻辑处理
				if not sentence_text.is_empty():
					var result_text = sentence_text
					if is_in_paren:
						result_text = LEFT_PAREN_CN + sentence_text + RIGHT_PAREN_CN
					sentences.append({"text": result_text, "no_tts": is_in_paren})
				# 这里不继续处理，跳出循环让外层括号处理逻辑处理括号内容
				break
				
			elif found_right_paren:
				# 遇到右括号：立即切分括号之前的内容（包括右括号？）
				# 注意：右括号本身不应该被包含在句子中
				sentence_text = buffer.substr(0, earliest_pos).strip_edges()
				buffer = buffer.substr(earliest_pos + 1)  # 跳过右括号
				if not sentence_text.is_empty():
					var result_text = sentence_text
					if is_in_paren:
						# 如果是在括号内，这里不应该再添加括号，因为外层会处理
						pass
					sentences.append({"text": result_text, "no_tts": is_in_paren})
				last_ellipsis_pos = -1
				
			elif found_punct_type == "ellipsis":
				# 处理省略号：根据规则决定是否切分
				var before_text = buffer.substr(0, earliest_pos)
				var before_len = before_text.length()
				
				# 计算从上一个省略号到当前省略号之间的字数
				var chars_since_last_ellipsis = before_len
				if last_ellipsis_pos != -1:
					chars_since_last_ellipsis = before_len - last_ellipsis_pos - ELLIPSIS.length()
				
				# 判断是否需要切分
				var should_split = false
				if before_len > ELLIPSIS_MAX_LENGTH:
					# 当前句子字数超过30，强制分割
					should_split = true
				elif last_ellipsis_pos == -1:
					# 第一个省略号，如果前面内容不为空，且超过最小间隔，则切分
					if before_len > ELLIPSIS_MIN_INTERVAL:
						should_split = true
				elif chars_since_last_ellipsis > ELLIPSIS_MIN_INTERVAL:
					# 距离上一个省略号超过6字，切分
					should_split = true
				
				if should_split:
					# 切分：将省略号及之前的内容作为一句
					var end_pos = earliest_pos + ELLIPSIS.length()
					sentence_text = buffer.substr(0, end_pos)
					buffer = buffer.substr(end_pos)
					last_ellipsis_pos = -1  # 重置，因为已经切分出去了
				else:
					# 不切分：跳过这个省略号，继续找下一个切分点
					# 将省略号视为普通文本，继续处理
					var next_pos = _find_next_split_point(buffer, earliest_pos + ELLIPSIS.length())
					if next_pos == -1:
						# 没有更多切分点，整个剩余部分作为一句
						sentence_text = buffer
						buffer = ""
					else:
						sentence_text = buffer.substr(0, next_pos)
						buffer = buffer.substr(next_pos)
						last_ellipsis_pos = -1  # 重置
			else:
				# 处理普通标点：包含连续的标点，以最后一个为准
				var end_pos = earliest_pos + 1
				# 检查并包含连续的标点符号
				while end_pos < buffer.length() and buffer[end_pos] in CHINESE_PUNCTUATION:
					end_pos += 1
				
				sentence_text = buffer.substr(0, end_pos)
				buffer = buffer.substr(end_pos)
				last_ellipsis_pos = -1  # 重置，因为普通标点切分会重置省略号计数

		if not sentence_text.is_empty():
			sentence_text = sentence_text.strip_edges()
			if not sentence_text.is_empty():
				var result_text = sentence_text
				# 如果是在括号内，根据规则用括号包裹句子
				if is_in_paren:
					# 输出时统一使用中文括号
					result_text = LEFT_PAREN_CN + sentence_text + RIGHT_PAREN_CN
				
				sentences.append({"text": result_text, "no_tts": is_in_paren})

	return sentences

# 查找下一个有效的切分点（普通标点或省略号）
static func _find_next_split_point(text: String, start_pos: int) -> int:
	var min_pos = -1
	
	# 先查找括号（优先级最高）
	for paren_char in ALL_LEFT_PARENS + ALL_RIGHT_PARENS:
		var pos = text.find(paren_char, start_pos)
		if pos != -1 and (min_pos == -1 or pos < min_pos):
			min_pos = pos
	
	# 如果没有括号，查找普通标点
	if min_pos == -1:
		for punct in CHINESE_PUNCTUATION:
			var pos = text.find(punct, start_pos)
			if pos != -1 and (min_pos == -1 or pos < min_pos):
				min_pos = pos
	
	# 如果没有标点，查找省略号
	if min_pos == -1:
		var ellipsis_pos = text.find(ELLIPSIS, start_pos)
		if ellipsis_pos != -1:
			min_pos = ellipsis_pos
	
	if min_pos == -1:
		return -1
	
	# 如果是括号，返回括号位置（不包含括号本身）
	for paren_char in ALL_LEFT_PARENS + ALL_RIGHT_PARENS:
		if min_pos == text.find(paren_char, start_pos):
			return min_pos
	
	# 如果是省略号，返回包含省略号的位置
	if min_pos == text.find(ELLIPSIS, start_pos):
		return min_pos + ELLIPSIS.length()
	
	# 如果是普通标点，包含连续的标点
	var end_pos = min_pos + 1
	while end_pos < text.length() and text[end_pos] in CHINESE_PUNCTUATION:
		end_pos += 1
	return end_pos

# 公开方法：将包含括号的完整文本切分为句子数组
# text: 完整的输入文本
# 返回一个句子数组，格式同上
static func split_text(text: String) -> Array:
	var results = []
	var regex = RegEx.new()
	regex.compile("([（\\(][^）\\)]*?[）\\)])")
	var last_index = 0
	var matches = regex.search_all(text)

	for match in matches:
		# 1. 处理括号块之前的部分
		var pretext = text.substr(last_index, match.get_start() - last_index)
		if not pretext.strip_edges().is_empty():
			results.append_array(_split_chunk(pretext, false))
			
		# 2. 处理括号块本身
		var block_text = match.get_string()
		# 尝试按中文右括号和英文右括号分割，取较长的那一段作为内容
		var content_cn = block_text.substr(1, block_text.rfind(RIGHT_PAREN_CN) - 1)
		var content_en = block_text.substr(1, block_text.rfind(RIGHT_PAREN_EN) - 1)
		var content = content_cn if content_cn.length() > content_en.length() else content_en

		if not content.strip_edges().is_empty():
			# 注意：这里传入 true，因为内容是括号内的
			results.append_array(_split_chunk(content, true))
			
		last_index = match.get_end()
		
	# 3. 处理最后一个括号块之后剩余的部分
	var posttext = text.substr(last_index)
	if not posttext.strip_edges().is_empty():
		results.append_array(_split_chunk(posttext, false))
		
	return results

# 公开方法：流式切分文本
# state: StreamState 状态对象，由调用方维护
# new_text: 新到来的文本内容
# is_end: 是否是流的最后一部分
# 返回一个新提取出来的句子数组，格式同上
static func split_stream(state: StreamState, new_text: String, is_end: bool = false) -> Array:
	state.buffer += new_text
	var results = []
	
	while not state.buffer.is_empty():
		var earliest_pos = -1
		var found_punct_type = ""  # "normal", "ellipsis"
		var found_left_paren = false
		var found_right_paren = false
		
		# 1. 查找最早出现的特殊字符（括号优先级最高）
		
		# 先查找括号（优先级最高）
		if not state.in_paren:
			# 不在括号内时，查找左括号
			for paren_char in ALL_LEFT_PARENS:
				var l_pos = state.buffer.find(paren_char)
				if l_pos != -1 and (earliest_pos == -1 or l_pos < earliest_pos):
					earliest_pos = l_pos
					found_left_paren = true

					found_punct_type = ""
		else:
			# 在括号内时，查找右括号
			for paren_char in ALL_RIGHT_PARENS:
				var r_pos = state.buffer.find(paren_char)
				if r_pos != -1 and (earliest_pos == -1 or r_pos < earliest_pos):
					earliest_pos = r_pos
					found_right_paren = true

					found_punct_type = ""
		
		# 如果没有找到括号，再查找省略号
		if not found_left_paren and not found_right_paren:
			var ellipsis_pos = state.buffer.find(ELLIPSIS)
			if ellipsis_pos != -1 and (earliest_pos == -1 or ellipsis_pos < earliest_pos):
				earliest_pos = ellipsis_pos
				found_punct_type = "ellipsis"
		
		# 如果没有找到括号和省略号，再查找普通标点
		if not found_left_paren and not found_right_paren and found_punct_type != "ellipsis":
			for punct in CHINESE_PUNCTUATION:
				var pos = state.buffer.find(punct)
				if pos != -1 and (earliest_pos == -1 or pos < earliest_pos):
					# 特殊处理括号内：如果标点后面紧跟右括号，则不在此处切分
					var end_pos = pos + 1
					while end_pos < state.buffer.length() and state.buffer[end_pos] in CHINESE_PUNCTUATION:
						end_pos += 1
					
					# 检查紧跟的是不是右括号
					var is_followed_by_right_paren = end_pos < state.buffer.length() and state.buffer[end_pos] in ALL_RIGHT_PARENS
					
					if state.in_paren and is_followed_by_right_paren:
						continue # 忽略这个标点，留给右括号处理
					
					earliest_pos = pos
					found_punct_type = "normal"

		# 2. 如果没找到任何切分点，根据 is_end 决定是否结束
		if earliest_pos == -1:
			if is_end:
				var final_text = state.buffer.strip_edges()
				if not final_text.is_empty():
					var result_text = final_text
					if state.in_paren:
						result_text = LEFT_PAREN_CN + final_text + RIGHT_PAREN_CN
					results.append({ "text": result_text, "no_tts": state.in_paren})
				state.buffer = ""
			break
			
		# 3. 处理切分点
		if found_left_paren:
			# 遇到左括号：立即切分括号之前的内容，并进入括号模式
			var pretext = state.buffer.substr(0, earliest_pos).strip_edges()
			if not pretext.is_empty():
				results.append({ "text": pretext, "no_tts": false})
			state.in_paren = true
			state.buffer = state.buffer.substr(earliest_pos + 1)
			state.last_ellipsis_pos = -1  # 重置省略号计数
			continue
			
		if found_right_paren:
			var content = state.buffer.substr(0, earliest_pos).strip_edges()
			if not content.is_empty():
				# 输出时统一使用中文括号
				results.append({ "text": LEFT_PAREN_CN + content + RIGHT_PAREN_CN, "no_tts": true})
			state.in_paren = false
			state.buffer = state.buffer.substr(earliest_pos + 1)
			state.last_ellipsis_pos = -1  # 重置省略号计数
			continue
			
		if found_punct_type == "ellipsis":
			# 处理省略号
			var before_text = state.buffer.substr(0, earliest_pos)
			var before_len = before_text.length()
			
			# 计算从上一个省略号到当前省略号之间的字数
			var chars_since_last_ellipsis = before_len
			if state.last_ellipsis_pos != -1:
				chars_since_last_ellipsis = before_len - state.last_ellipsis_pos - ELLIPSIS.length()
			
			# 判断是否需要切分
			var should_split = false
			if before_len > ELLIPSIS_MAX_LENGTH:
				# 当前句子字数超过30，强制分割
				should_split = true
			elif state.last_ellipsis_pos == -1:
				# 第一个省略号，如果前面内容不为空，且超过最小间隔，则切分
				if before_len > ELLIPSIS_MIN_INTERVAL:
					should_split = true
			elif chars_since_last_ellipsis > ELLIPSIS_MIN_INTERVAL:
				# 距离上一个省略号超过6字，切分
				should_split = true
			
			if should_split:
				# 切分：将省略号及之前的内容作为一句
				var end_pos = earliest_pos + ELLIPSIS.length()
				var sentence = state.buffer.substr(0, end_pos).strip_edges()
				if not sentence.is_empty():
					var result_text = sentence
					if state.in_paren:
						result_text = LEFT_PAREN_CN + sentence + RIGHT_PAREN_CN
					results.append({ "text": result_text, "no_tts": state.in_paren})
				state.buffer = state.buffer.substr(end_pos)
				state.last_ellipsis_pos = -1  # 重置
			else:
				# 不切分：跳过这个省略号，继续找下一个切分点
				var next_pos = _find_next_split_point(state.buffer, earliest_pos + ELLIPSIS.length())
				if next_pos == -1:
					# 没有更多切分点，等待更多内容
					break
				else:
					var sentence = state.buffer.substr(0, next_pos).strip_edges()
					if not sentence.is_empty():
						var result_text = sentence
						if state.in_paren:
							result_text = LEFT_PAREN_CN + sentence + RIGHT_PAREN_CN
						results.append({ "text": result_text, "no_tts": state.in_paren})
					state.buffer = state.buffer.substr(next_pos)
					state.last_ellipsis_pos = -1  # 重置
			
		elif found_punct_type == "normal":
			# 处理普通标点：包含连续标点，以最后一个为准
			var end_pos = earliest_pos + 1
			while end_pos < state.buffer.length() and state.buffer[end_pos] in CHINESE_PUNCTUATION:
				end_pos += 1
				
			var sentence = state.buffer.substr(0, end_pos).strip_edges()
			if not sentence.is_empty():
				var result_text = sentence
				if state.in_paren:
					result_text = LEFT_PAREN_CN + sentence + RIGHT_PAREN_CN
				results.append({ "text": result_text, "no_tts": state.in_paren})
			state.buffer = state.buffer.substr(end_pos)
			state.last_ellipsis_pos = -1  # 重置

	return results

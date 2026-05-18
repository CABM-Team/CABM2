## UUIDUtil.gd
## UUID v4 生成工具（基于随机数）
## AutoLoad 单例，也可作为静态方法使用

extends Node

## 生成一个标准 UUID v4 字符串
## 格式：xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
func v4() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var b := PackedByteArray()
	b.resize(16)
	for i in 16:
		b[i] = rng.randi() % 256

	# 设置版本位：version 4
	b[6] = (b[6] & 0x0F) | 0x40
	# 设置 variant 位：10xx
	b[8] = (b[8] & 0x3F) | 0x80

	return "%s-%s-%s-%s-%s" % [
		b.slice(0, 4).hex_encode(),
		b.slice(4, 6).hex_encode(),
		b.slice(6, 8).hex_encode(),
		b.slice(8, 10).hex_encode(),
		b.slice(10, 16).hex_encode()
	]

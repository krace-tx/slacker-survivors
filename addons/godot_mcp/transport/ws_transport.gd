@tool
extends RefCounted

## 专职网络传输层 (WebSocket Transport)
## 只负责底层 TCP 监听、WebSocket 握手、报文读写与连接保活。
## 严格绑定 127.0.0.1 本地回环地址，杜绝局域网未授权访问。

signal client_connected(client_id: int)
signal client_disconnected(client_id: int)
signal message_received(client_id: int, message: String)

class ClientPeer:
	var tcp: StreamPeerTCP
	var id: int
	var ws: WebSocketPeer = null
	var state: int = -1  # -1: 握手中, 0: 已连接, 1: 异常/断开
	var handshake_time: int

	func _init(p_tcp: StreamPeerTCP, p_id: int) -> void:
		tcp = p_tcp
		id = p_id
		handshake_time = Time.get_ticks_msec()

	func upgrade_to_websocket() -> bool:
		ws = WebSocketPeer.new()
		# 协商支持的标准子协议，兼容各端 WebSocket 客户端
		ws.supported_protocols = PackedStringArray(["json"])
		var err := ws.accept_stream(tcp)
		return err == OK

var tcp_server := TCPServer.new()
var port: int = 9080
var bind_address: String = "127.0.0.1"
var handshake_timeout_ms: int = 5000
var clients: Dictionary = {}
var next_client_id: int = 1


func start(p_port: int = 9080, p_bind_address: String = "127.0.0.1") -> Error:
	port = p_port
	bind_address = p_bind_address
	if tcp_server.is_listening():
		return OK
	var err := tcp_server.listen(port, bind_address)
	if err == OK:
		print("[MCP Transport] Listening on ws://%s:%d" % [bind_address, port])
	else:
		printerr("[MCP Transport] Failed to listen on %s:%d, error code: %d" % [bind_address, port, err])
	return err


func stop() -> void:
	for id in clients.keys():
		var client: ClientPeer = clients[id]
		if client.ws != null and client.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			client.ws.close()
	clients.clear()
	if tcp_server.is_listening():
		tcp_server.stop()
	print("[MCP Transport] Server stopped.")


func is_active() -> bool:
	return tcp_server.is_listening()


func poll() -> void:
	if not tcp_server.is_listening():
		return

	# 1. 接收新 TCP 连接
	while tcp_server.is_connection_available():
		var tcp := tcp_server.take_connection()
		if tcp == null:
			continue
		var id := next_client_id
		next_client_id += 1
		var client := ClientPeer.new(tcp, id)
		clients[id] = client
		if not client.upgrade_to_websocket():
			printerr("[MCP Transport Client %d] Upgrade to WebSocket failed immediately." % id)
			clients.erase(id)

	# 2. 轮询现有客户端
	var now := Time.get_ticks_msec()
	var to_remove: Array[int] = []

	for id in clients.keys():
		var client: ClientPeer = clients[id]
		if client.ws == null:
			to_remove.append(id)
			continue

		client.ws.poll()
		var state := client.ws.get_ready_state()

		if client.state == -1:  # 握手中
			if state == WebSocketPeer.STATE_OPEN:
				client.state = 0
				client_connected.emit(id)
			elif state != WebSocketPeer.STATE_CONNECTING:
				to_remove.append(id)
			elif now - client.handshake_time > handshake_timeout_ms:
				printerr("[MCP Transport Client %d] WebSocket handshake timeout." % id)
				to_remove.append(id)

		elif client.state == 0:  # 已建立连接
			if state == WebSocketPeer.STATE_OPEN:
				while client.ws.get_available_packet_count() > 0:
					var packet := client.ws.get_packet()
					var text := packet.get_string_from_utf8()
					message_received.emit(id, text)
			elif state == WebSocketPeer.STATE_CLOSING or state == WebSocketPeer.STATE_CLOSED:
				to_remove.append(id)

	for id in to_remove:
		if clients.has(id):
			client_disconnected.emit(id)
			clients.erase(id)


func send_text(client_id: int, text: String) -> Error:
	if not clients.has(client_id):
		return ERR_DOES_NOT_EXIST
	var client: ClientPeer = clients[client_id]
	if client.ws == null or client.ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	return client.ws.send_text(text)

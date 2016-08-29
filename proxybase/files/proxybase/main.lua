local ski = require("ski")
local log = require("log")
local lfs = require("lfs")
local tcp = require("ski.tcp")
local sandc = require("sandc")
local common = require("common")
local sandc1 = require("sandc1")
local js = require("cjson.safe")

local remote_mqtt, local_mqtt
local read, save_safe = common.read, common.save_safe

local cfgpath = "/etc/config/cloud.json"

local g_kvmap, g_devid
local default_cfg = {ac_host = "192.168.0.213", ac_port = 61886, account = "yjs"} -- TODO

-- 读取本唯一ID
local function read_id()
	local id = read("ifconfig eth0 | grep HWaddr | awk '{print $5}'", io.popen):gsub("[ \t\n]", ""):lower() assert(#id == 17)
	g_devid = id
end

-- 加载cloud的配置，如果没有，设置为default
local function load()
	if lfs.attributes(cfgpath) then
		g_kvmap = js.decode(read(cfgpath))
	end

	g_kvmap = g_kvmap and g_kvmap or default_cfg
end

-- 保存状态到文件
local function save_status(st, host, port)
	local m = {state = st, host = host, port = port}
	save_safe("/tmp/memfile/cloudcli.json", js.encode(m))
end

-- 附加认证内容
local function get_connect_payload()
	local account = g_kvmap.account
	local map = {account = account, devid = g_devid}
	return account, map
end

local function remote_topic()
	return "a/dev/" .. g_devid
end

-- 本地sands客户端
local function start_local()
	local  unique = "a/ac/proxy"
	local mqtt = sandc.new(unique)
	mqtt:set_auth("ewrdcv34!@@@zvdasfFD*s34!@@@fadefsasfvadsfewa123$", "1fff89167~!223423@$$%^^&&&*&*}{}|/.,/.,.,<>?")
	mqtt:pre_subscribe(unique)
	mqtt:set_callback("on_message", function(topic, payload)
		print(topic, payload)
		if not remote_mqtt then
			log.error("skip %s %s", topic, payload:sub(1, 100))
			return
		end

		local map = js.decode(payload)
		if not (map and map.data and map.out_topic) then
			log.error("invalid payload %s %s", topic, payload:sub(1, 100))
			return
		end

		map.data.tpc = remote_topic()

		remote_mqtt:publish(map.out_topic, js.encode(map.data))
	end)

	mqtt:set_callback("on_disconnect", function(st, e) log.fatal("remote mqtt disconnect %s %s", st, e) end)

	local host, port = "127.0.0.1", 61886
	local r, e = mqtt:connect(host, port)
	local _ = r or log.fatal("connect fail %s", e)
	mqtt:run()

	local_mqtt = mqtt

	log.info("connect ok %s %s", host, port)
end

-- 查找host对应的ip，测试host/port是否可连接
local function try_connect(host, port)
	local ip = host
	local pattern = "^%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?$"
	if not ip:find(pattern) then
		local cmd = string.format("nslookup '%s' 2>/dev/null | grep -A 1 'Name:' | grep Addr | awk '{print $3}'", host) -- TODO
		-- local cmd = string.format("timeout nslookup '%s' 2>/dev/null | grep -A 1 'Name:' | grep Addr | awk '{print $3}'", host)
		ip = read(cmd, io.popen)
		if not ip then
			log.error("%s fail", cmd)
			return
		end

		ip = ip:gsub("[ \t\r\n]", "")
		if not ip:find(pattern) then
			log.error("%s fail", cmd)
			return
		end
	end

	local max_timeout = 10
	local start = ski.time()

	for i = 1, 3 do
		if ski.time() - start > max_timeout then
			return
		end

		local cli = tcp.connect(ip, port)
		if cli then
			print("connect ok", ip, port)
			cli:close()
			return ip, port
		end

		log.debug("try connect %s %s fail", ip, port)
		ski.sleep(3)
	end
end

-- 测试云端服务器，直到可以连接
local function get_active_addr()
	while true do
		local host, port = try_connect(g_kvmap.ac_host, g_kvmap.ac_port)
		if host then
			return host, port
		end

		log.debug("try connect %s %s fail", g_kvmap.ac_host or "", g_kvmap.ac_port or "")
		ski.sleep(3)
	end
end

-- 本地sands客户端
local function start_local()
	local unique, ip, port = "a/ac/proxy", "127.0.0.1", 61886
	local mqtt = sandc.new(unique)
	mqtt:set_auth("ewrdcv34!@@@zvdasfFD*s34!@@@fadefsasfvadsfewa123$", "1fff89167~!223423@$$%^^&&&*&*}{}|/.,/.,.,<>?")
	mqtt:pre_subscribe(unique)
	mqtt:set_callback("on_disconnect", function(st, e) log.fatal("mqtt disconnect %s %s %s %s %s", unique, ip, port, st, e) end)

	mqtt:set_callback("on_message", function(topic, payload)
		print("222", topic, payload)
		if not remote_mqtt then
			log.error("skip %s %s", topic, payload:sub(1, 100))
			return
		end

		local map = js.decode(payload)
		if not (map and map.data and map.out_topic) then
			log.error("invalid payload %s %s", topic, payload:sub(1, 100))
			return
		end

		map.data.tpc = remote_topic()
		print(map.out_topic, js.encode(map.data))
		remote_mqtt:publish(map.out_topic, js.encode(map.data))
	end)

	local r, e = mqtt:connect(ip, port)
	local _ = r or log.fatal("connect fail %s", e)

	mqtt:run()
	log.info("connect ok %s %s %s", unique, ip, port)

	local_mqtt = mqtt
end

local function start_remote()
	local ip, port = get_active_addr()
	local unique = remote_topic()

	local mqtt = sandc1.new(unique)
	mqtt:set_auth("ewrdcv34!@@@zvdasfFD*s34!@@@fadefsasfvadsfewa123$", "1fff89167~!223423@$$%^^&&&*&*}{}|/.,/.,.,<>?")
	mqtt:pre_subscribe(unique)
	mqtt:set_callback("on_disconnect", function(st, e) print(14, st, e)  log.fatal("mqtt disconnect %s %s %s %s %s", unique, ip, port, st, e) end)

	local account, connect_data = get_connect_payload()
	mqtt:set_connect("a/ac/query/connect", js.encode({pld = connect_data}))
	mqtt:set_will("a/ac/query/will", js.encode({devid = g_devid, account = account}))
	mqtt:set_extend(js.encode({account = account, devid = g_devid}))

	mqtt:set_callback("on_message", function(topic, payload)
		print("111", topic, payload)
		if not local_mqtt then
			log.error("skip %s %s", topic, payload)
			return
		end

		local map = js.decode(payload)
		if not (map and map.mod and map.pld) then
			log.error("invalid message %s %s", topic, payload)
			return
		end

		local_mqtt:publish(map.mod, payload)
	end)

	local r, e = mqtt:connect(ip, port)
	local _ = r or log.fatal("connect fail %s", e)

	mqtt:run()
	log.info("connect ok %s %s %s", unique, ip, port)

	remote_mqtt = mqtt
end

local function main()
	save_status(0)
	local _ = read_id(), load()

	-- cloudcli会向云端注册，如果帐号不对，会touch /tmp/invalid_account
	if not lfs.attributes("/tmp/invalid_account") then
		ski.go(start_local)

		-- ac_host默认是""
		while g_kvmap.ac_host == "" do
			ski.sleep(1)
		end

		ski.go(start_remote)
	end
end

ski.run(main)
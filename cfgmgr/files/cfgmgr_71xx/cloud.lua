local fp = require("fp")
local ski = require("ski")
local lfs = require("lfs")
local log = require("log")
local js = require("cjson.safe")
local common = require("common")
local cfglib = require("cfglib")

local read, save_safe = common.read, common.save_safe

local udp_map = {}
local udpsrv, mqtt, reply

local default_cloud = {ac_host = "", ac_port = 61886, account = "", description = ""}

local function init(u, p)
	udpsrv, mqtt = u, p
	reply = cfglib.gen_reply(udpsrv)
end

udp_map["cloud_get"] = function(p, ip, port)
	local path = '/etc/config/cloud.json'
	if not lfs.attributes(path) then
		return reply(ip, port, 0, default_cloud)
	end

	local s, e = read(path)
	if not s then
		return reply(ip, port, 0, default_cloud)
	end

	reply(ip, port, 0, s)
end

udp_map["cloud_set"] = function(p, ip, port)
	p.cmd = nil

	local path = '/etc/config/cloud.json'
	if lfs.attributes(path) then
		local s = read(path)
		if s then
			local m = js.decode(s) or {}
			if fp.same(m, p) then
				return reply(ip, port, 0, "ok")
			end
		end
	end

	local s = js.encode(p)
	save_safe(path, s)

	log.info("cloud change %s", s)

	-- 发送消息给proxybase
	mqtt:publish("a/local/proxybase", s)
	reply(ip, port, 0, "ok")
end

return {init = init, dispatch_udp = cfglib.gen_dispatch_udp(udp_map)}
local ski = require("ski")
local log = require("log")
local js = require("cjson.safe")
local common = require("common")
local ipops = require("ipops")
local bit = require("bit")

local read = common.read

local function load_board()
	local path = "/etc/config/board.json"
	local s = read(path)	assert(s)
	local m = js.decode(s)	assert(m)
	local ports, options, networks = m.ports, m.options, m.networks	assert(ports and options and networks)
	local port_map = {}
	local switchs = {}

	for _, dev in ipairs(ports) do
		if dev.type == "switch" then
			local ports = {}
			for idx, port in ipairs(dev.outer_ports) do
				table.insert(port_map, {ifname=dev.ifname .. "." .. idx, mac = port.mac})
				table.insert(ports, {vlan = idx, ports = port.num .. " " .. dev.inner_port .. "t"})
			end
			table.insert(switchs, {device = dev.device, ports = ports})
		elseif dev.type == "ether" then
			table.insert(port_map, {ifname=dev.ifname, mac = dev.outer_ports[1].mac})
		end
	end

	return {switchs = switchs, ports = port_map, options = options, networks = networks}
end

local function generate_board_cmds(board)
	local cmd = ""
	for idx, switch in ipairs(board.switchs) do
		cmd = cmd .. string.format("while uci delete network.@switch[0] >/dev/null 2>&1; do :; done\n")
		cmd = cmd .. string.format("obj=`uci add network switch`\n")
		cmd = cmd .. string.format("test -n \"$obj\" && {\n")
		cmd = cmd .. string.format("	uci set network.$obj.name='%s'\n", switch.device)
		cmd = cmd .. string.format("	uci set network.$obj.reset='1'\n")
		cmd = cmd .. string.format("	uci set network.$obj.enable_vlan='1'\n")
		cmd = cmd .. string.format("	uci set network.$obj.enable_vlan='1'\n")
		cmd = cmd .. string.format("}\n")
		cmd = cmd .. string.format("while uci delete network.@switch_vlan[0] >/dev/null 2>&1; do :; done\n")
		for i, port in ipairs(switch.ports) do
			cmd = cmd .. string.format("obj=`uci add network switch_vlan`\n")
			cmd = cmd .. string.format("test -n \"$obj\" && {\n")
			cmd = cmd .. string.format("	uci set network.$obj.device='%s'\n", switch.device)
			cmd = cmd .. string.format("	uci set network.$obj.vlan='%u'\n", port.vlan)
			cmd = cmd .. string.format("	uci set network.$obj.ports='%s'\n", port.ports)
			cmd = cmd .. string.format("}\n")
		end
	end
	return cmd
end

local function load_network()
	local path = "/etc/config/network.json"
	local s = read(path)	assert(s)
	local m = js.decode(s)	assert(m)
	return m.network
end

local function generate_network_cmds(board, network)
	local uci_network = {}
	local uci_zone = {
		lan = {id = 0, ifname = {}, network = {}},
		wan = {id = 1, ifname = {}, network = {}}
	}
	local cmd = ""
	cmd = cmd .. string.format("while uci delete dhcp.@dhcp[0] >/dev/null 2>&1; do :; done\n")
	cmd = cmd .. string.format("while uci delete network.@interface[1] >/dev/null 2>&1; do :; done\n")
	for name, option in pairs(network) do
		uci_network[name] = option
		if #option.ports > 1 then
			uci_network[name].type = 'bridge'
		end
		if not option.mac or option.mac == "" then
			uci_network[name].mac = board.ports[option.ports[1]].mac
		end
		uci_network[name].ifname=""
		for _, i in ipairs(option.ports) do
			if uci_network[name].ifname == "" then
				uci_network[name].ifname = board.ports[i].ifname
			else
				uci_network[name].ifname = uci_network[name].ifname .. " " .. board.ports[i].ifname
			end
		end

		cmd = cmd .. string.format("uci set network.%s=interface\n", name)
		cmd = cmd .. string.format("uci set network.%s.macaddr='%s'\n", name, uci_network[name].mac)
		cmd = cmd .. string.format("uci set network.%s.ifname='%s'\n", name, uci_network[name].ifname)
		if uci_network[name].type and uci_network[name].type ~= "" then
			cmd = cmd .. string.format("uci set network.%s.type='%s'\n", name, uci_network[name].type)
		end
		if uci_network[name].mtu and uci_network[name].mtu ~= "" then
			cmd = cmd .. string.format("uci set network.%s.mtu='%s'\n", name, uci_network[name].mtu)
		end
		if uci_network[name].metric and uci_network[name].metric ~= "" then
			cmd = cmd .. string.format("uci set network.%s.metric='%s'\n", name, uci_network[name].metric)
		end
		if uci_network[name].proto == "static" then
			cmd = cmd .. string.format("uci set network.%s.proto='static'\n", name)
			cmd = cmd .. string.format("uci set network.%s.ipaddr='%s'\n", name, uci_network[name].ipaddr)
		elseif uci_network[name].proto == "dhcp" then
			cmd = cmd .. string.format("uci set network.%s.proto='dhcp'\n", name)
		elseif uci_network[name].proto == "pppoe" then
			cmd = cmd .. string.format("uci set network.%s.proto='pppoe'\n", name)
			cmd = cmd .. string.format("uci set network.%s.username='%s'\n", name, uci_network[name].pppoe_account)
			cmd = cmd .. string.format("uci set network.%s.password='%s'\n", name, uci_network[name].pppoe_password)
		else
			cmd = cmd .. string.format("uci set network.%s.proto='none'\n", name)
		end
		if uci_network[name].proto == "static" and uci_network[name].dhcpd and uci_network[name].dhcpd["enabled"] == 1 then
			local ipaddr, netmask = ipops.get_ip_and_mask(uci_network[name].ipaddr)
			local startip = ipops.ipstr2int(uci_network[name].dhcpd["start"])
			local endip = ipops.ipstr2int(uci_network[name].dhcpd["end"])
			local s, e = bit.bxor(startip, bit.band(ipaddr, netmask)), bit.bxor(endip - bit.band(ipaddr, netmask))

			cmd = cmd .. string.format("uci set dhcp.%s=dhcp\n", name)
			cmd = cmd .. string.format("uci set dhcp.%s.interface='%s'\n", name, name)
			cmd = cmd .. string.format("uci set dhcp.%s.start='%u'\n", name, s)
			cmd = cmd .. string.format("uci set dhcp.%s.end='%u'\n", name, e)
			cmd = cmd .. string.format("uci set dhcp.%s.leasetime='%s'\n", name, uci_network[name].dhcpd["leasetime"])
			cmd = cmd .. string.format("uci set dhcp.%s.force='1'\n", name)
			cmd = cmd .. string.format("uci set dhcp.%s.subnet='%s'\n", name, uci_network[name].ipaddr)
			cmd = cmd .. string.format("uci set dhcp.%s.dynamicdhcp='%u'\n", name, uci_network[name].dhcpd["dynamicdhcp"] or 1)
			if uci_network[name].dhcpd["dns"] then
				cmd = cmd .. string.format("uci add_list dhcp.%s.dhcp_option='6,%s'\n", name, uci_network[name].dhcpd["dns"])
			end
		end

		if name:find("^lan") then
			table.insert(uci_zone.lan.network, name)
		else
			table.insert(uci_zone.wan.network, name)
		end
		if uci_network[name].proto == "static" or uci_network[name].proto == "dhcp" then
			if uci_network[name].type == 'bridge' then
				if name:find("^lan") then
					table.insert(uci_zone.lan.ifname, "br-" .. name)
				else
					table.insert(uci_zone.wan.ifname, "br-" .. name)
				end
			else
				if name:find("^lan") then
					table.insert(uci_zone.lan.ifname, uci_network[name].ifname)
				else
					table.insert(uci_zone.wan.ifname, uci_network[name].ifname)
				end
			end
		elseif uci_network[name].proto == "pppoe" then
			if name:find("^lan") then
				table.insert(uci_zone.lan.ifname, "pppoe-" .. name)
			else
				table.insert(uci_zone.wan.ifname, "pppoe-" .. name)
			end
		end
	end

	cmd = cmd .. string.format("while uci delete nos-zone.@zone[0] >/dev/null 2>&1; do :; done\n")
	for name, zone in pairs(uci_zone) do
		cmd = cmd .. string.format("obj=`uci add nos-zone zone`\n")
		cmd = cmd .. string.format("test -n \"$obj\" && {\n")
		cmd = cmd .. string.format("	uci set nos-zone.$obj.name='%s'\n", name)
		cmd = cmd .. string.format("	uci set nos-zone.$obj.id='%s'\n", zone.id)
		for _, ifname in ipairs(zone.ifname) do
			cmd = cmd .. string.format("	uci add_list nos-zone.$obj.ifname='%s'\n", ifname)
		end
		cmd = cmd .. string.format("}\n")
	end
	cmd = cmd .. string.format("while uci delete firewall.@zone[0] >/dev/null 2>&1; do :; done\n")
	for name, zone in pairs(uci_zone) do
		cmd = cmd .. string.format("obj=`uci add firewall zone`\n")
		cmd = cmd .. string.format("test -n \"$obj\" && {\n")
		cmd = cmd .. string.format("	uci set firewall.$obj.name='%s'\n", name)
		cmd = cmd .. string.format("	uci set firewall.$obj.id='%s'\n", zone.id)
		cmd = cmd .. string.format("	uci set firewall.$obj.input='ACCEPT'\n")
		cmd = cmd .. string.format("	uci set firewall.$obj.output='ACCEPT'\n")
		cmd = cmd .. string.format("	uci set firewall.$obj.forward='%s'\n", name:find("^lan") and "ACCEPT" or "REJECT")
		cmd = cmd .. string.format("	uci set firewall.$obj.mtu_fix='1'\n")
		for _, network in ipairs(zone.network) do
			cmd = cmd .. string.format("	uci add_list firewall.$obj.network='%s'\n", network)
		end
		cmd = cmd .. string.format("}\n")
	end
	return cmd
end

local function network_reload()
	local board = load_board()
	local network = load_network()
	local cmd = ""
	cmd = cmd .. generate_board_cmds(board)
	cmd = cmd .. generate_network_cmds(board, network)
	cmd = cmd .. string.format("uci commit network\n")
	cmd = cmd .. string.format("uci commit nos-zone\n")
	cmd = cmd .. string.format("uci commit firewall\n")
	cmd = cmd .. string.format("sleep 1\n")
	cmd = cmd .. string.format("/etc/init.d/network restart\n")
	cmd = cmd .. string.format("/etc/init.d/dnsmasq restart\n")
	cmd = cmd .. string.format("/etc/init.d/nos-zone restart\n")
	cmd = cmd .. string.format("/etc/init.d/firewall restart\n")
	print(cmd)
	os.execute(cmd)
end

local tcp_map = {}
local mqtt
local function init(p)
	mqtt = p
	network_reload()
end

local function dispatch_tcp(cmd)
	local f = tcp_map[cmd.cmd]
	if f then
		return true, f(cmd.data)
	end
end

tcp_map["network"] = function(p)
	network_reload()
end

return {init = init, dispatch_tcp = dispatch_tcp}
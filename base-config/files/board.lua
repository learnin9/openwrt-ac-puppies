local js = require("cjson.safe")
local common = require("common")

local read = common.read

local function load_board()
	local path = "/etc/config/board.json"
	local s = read(path)	assert(s)
	local m = js.decode(s)	assert(m)
	local ports, options, networks = m.ports, m.options, m.networks	assert(ports and options and networks)
	local port_map = {}

	for _, dev in ipairs(ports) do
		if dev.type == "switch" then
			for idx, port in ipairs(dev.outer_ports) do
				table.insert(port_map, {ifname=dev.ifname .. "." .. idx, mac = port.mac})
			end
		elseif dev.type == "ether" then
			table.insert(port_map, {ifname=dev.ifname, mac = dev.outer_ports[1].mac})
		end
	end

	return {ports = port_map, options = options, networks = networks}
end

local board = load_board()
--local s = js.encode(m)
--print(s)

local network = {}

if board.options[1] then
	network.name = board.options[1].name
	network.network = {}
	for ifname, ports in pairs(board.options[1].map) do
		network.network[ifname] = board.networks[ifname]
		network.network[ifname].ports = ports
	end
end

print(js.encode(network))
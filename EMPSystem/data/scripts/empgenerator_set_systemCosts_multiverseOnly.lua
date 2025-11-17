--[[if mods.multiverse ~= nil then
	local node_child_iter = mods.multiverse.node_child_iter
	--25
	--40
	--9999
	local crewNames = {}
	do
		local doc = RapidXML.xml_document("data/names.xml")
		for node in node_child_iter(doc:first_node("FTL") or doc) do
			if node:name() == "nameList" then
				for nameNode in node_child_iter(node) do
					nameNode:value("apple", 5)
					crewNames[nameNode:value()] = true
					print("crewName:" .. nameNode:value())
				end
			end
		end
		doc:clear()
	end
end--]]
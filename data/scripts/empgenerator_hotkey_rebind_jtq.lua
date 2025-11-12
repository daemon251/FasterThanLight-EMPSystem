--code from ins+

EMPHotkeys = {}

EMPHotkeys.keyNames = {}

EMPHotkeys.keyNames[0] = "UNBINDED" --only unbinded because if zero in logic, not executed at all.
EMPHotkeys.keyNames[48] = "0"
EMPHotkeys.keyNames[49] = "1"
EMPHotkeys.keyNames[50] = "2"
EMPHotkeys.keyNames[51] = "3"
EMPHotkeys.keyNames[52] = "4"
EMPHotkeys.keyNames[53] = "5"
EMPHotkeys.keyNames[54] = "6"
EMPHotkeys.keyNames[55] = "7"
EMPHotkeys.keyNames[56] = "8"
EMPHotkeys.keyNames[57] = "9"
EMPHotkeys.keyNames[64] = "@"
EMPHotkeys.keyNames[38] = "&"
EMPHotkeys.keyNames[42] = "*"
EMPHotkeys.keyNames[96] = "`"
EMPHotkeys.keyNames[92] = "\\" -- Yes this is normal
EMPHotkeys.keyNames[8] = "BACKSPACE"
EMPHotkeys.keyNames[318] = "BREAK"
EMPHotkeys.keyNames[301] = "CAPS LOCK"
EMPHotkeys.keyNames[94] = "^"
EMPHotkeys.keyNames[12] = "CLEAR"
EMPHotkeys.keyNames[58] = ":"
EMPHotkeys.keyNames[44] = ","
EMPHotkeys.keyNames[314] = "COMPOSE"
EMPHotkeys.keyNames[127] = "DELETE"
EMPHotkeys.keyNames[36] = "$"
EMPHotkeys.keyNames[274] = "DOWN"
EMPHotkeys.keyNames[279] = "END"
EMPHotkeys.keyNames[61] = "="
EMPHotkeys.keyNames[27] = "ESCAPE" --Blacklisted
EMPHotkeys.keyNames[321] = "EURO"
EMPHotkeys.keyNames[33] = "!"
EMPHotkeys.keyNames[282] = "F1"
EMPHotkeys.keyNames[283] = "F2"
EMPHotkeys.keyNames[284] = "F3"
EMPHotkeys.keyNames[285] = "F4"
EMPHotkeys.keyNames[286] = "F5"
EMPHotkeys.keyNames[287] = "F6"
EMPHotkeys.keyNames[288] = "F7"
EMPHotkeys.keyNames[289] = "F8"
EMPHotkeys.keyNames[290] = "F9"
EMPHotkeys.keyNames[291] = "F10"
EMPHotkeys.keyNames[292] = "F11"
EMPHotkeys.keyNames[293] = "F12"
EMPHotkeys.keyNames[294] = "F13"
EMPHotkeys.keyNames[295] = "F14"
EMPHotkeys.keyNames[296] = "F15"
EMPHotkeys.keyNames[62] = ">"
EMPHotkeys.keyNames[36] =  "#"
EMPHotkeys.keyNames[315] = "HELP"
EMPHotkeys.keyNames[278] = "HOME"
EMPHotkeys.keyNames[277] = "INSERT"
EMPHotkeys.keyNames[256] = "NUM 0"
EMPHotkeys.keyNames[257] = "NUM 1"
EMPHotkeys.keyNames[258] = "NUM 2"
EMPHotkeys.keyNames[259] = "NUM 3"
EMPHotkeys.keyNames[260] = "NUM 4"
EMPHotkeys.keyNames[261] = "NUM 5"
EMPHotkeys.keyNames[262] = "NUM 6"
EMPHotkeys.keyNames[263] = "NUM 7"
EMPHotkeys.keyNames[264] = "NUM 8"
EMPHotkeys.keyNames[265] = "NUM 9"
EMPHotkeys.keyNames[266] = "NUM ."
EMPHotkeys.keyNames[267] = "NUM /"
EMPHotkeys.keyNames[268] = "NUM *"
EMPHotkeys.keyNames[269] = "NUM -"
EMPHotkeys.keyNames[270] = "NUM +"
EMPHotkeys.keyNames[271] = "NUM ENTER"
EMPHotkeys.keyNames[272] = "NUM ="
EMPHotkeys.keyNames[308] = "LEFT ALT"
EMPHotkeys.keyNames[306] = "LEFT CTRL"
EMPHotkeys.keyNames[276] = "LEFT"
EMPHotkeys.keyNames[91] = "["
EMPHotkeys.keyNames[40] = "("
EMPHotkeys.keyNames[60] = "LESS"
EMPHotkeys.keyNames[310] = "LEFT META"
EMPHotkeys.keyNames[304] = "LEFT SHIFT"
EMPHotkeys.keyNames[311] = "LEFT SUPER"
EMPHotkeys.keyNames[319] = "MENU"
EMPHotkeys.keyNames[45] = "-"
EMPHotkeys.keyNames[313] = "MODE"
EMPHotkeys.keyNames[300] = "NUM LOCK"
EMPHotkeys.keyNames[281] = "PAGE DOWN"
EMPHotkeys.keyNames[280] = "PAGE UP"
EMPHotkeys.keyNames[19] = "PAUSE"
EMPHotkeys.keyNames[46] = "."
EMPHotkeys.keyNames[43] = "+"
EMPHotkeys.keyNames[320] = "POWER"
EMPHotkeys.keyNames[316] = "PRNT SCRN"
EMPHotkeys.keyNames[63] = "?"
EMPHotkeys.keyNames[34] = "\"" -- Yes this is normal too
EMPHotkeys.keyNames[39] = "'"
EMPHotkeys.keyNames[307] = "RIGHT ALT"
EMPHotkeys.keyNames[305] = "RIGHT CTRL"
EMPHotkeys.keyNames[13] = "Return"
EMPHotkeys.keyNames[275] = "RIGHT"
EMPHotkeys.keyNames[93] = "]"
EMPHotkeys.keyNames[41] = ")"
EMPHotkeys.keyNames[309] = "RIGHT META"
EMPHotkeys.keyNames[303] = "RIGHT SHIFT"
EMPHotkeys.keyNames[312] = "RIGHT SUPER"
EMPHotkeys.keyNames[302] = "SCROLL LOCK"
EMPHotkeys.keyNames[59] = ";"
EMPHotkeys.keyNames[47] = "/"
EMPHotkeys.keyNames[32] = "SPACE"
EMPHotkeys.keyNames[317] = "SYS RQ"
EMPHotkeys.keyNames[9] = "TAB"
EMPHotkeys.keyNames[95] = "_"
EMPHotkeys.keyNames[322] = "UNDO"
EMPHotkeys.keyNames[273] = "UP"
EMPHotkeys.keyNames[97] = "A"
EMPHotkeys.keyNames[98] = "B"
EMPHotkeys.keyNames[99] = "C"
EMPHotkeys.keyNames[100] = "D"
EMPHotkeys.keyNames[101] = "E"
EMPHotkeys.keyNames[102] = "F"
EMPHotkeys.keyNames[103] = "G"
EMPHotkeys.keyNames[104] = "H"
EMPHotkeys.keyNames[105] = "I"
EMPHotkeys.keyNames[106] = "J"
EMPHotkeys.keyNames[107] = "K"
EMPHotkeys.keyNames[108] = "L"
EMPHotkeys.keyNames[109] = "M"
EMPHotkeys.keyNames[110] = "N"
EMPHotkeys.keyNames[111] = "O"
EMPHotkeys.keyNames[112] = "P"
EMPHotkeys.keyNames[113] = "Q"
EMPHotkeys.keyNames[114] = "R"
EMPHotkeys.keyNames[115] = "S"
EMPHotkeys.keyNames[116] = "T"
EMPHotkeys.keyNames[117] = "U"
EMPHotkeys.keyNames[118] = "V"
EMPHotkeys.keyNames[119] = "W"
EMPHotkeys.keyNames[120] = "X"
EMPHotkeys.keyNames[121] = "Y"
EMPHotkeys.keyNames[122] = "Z"

function EMPHotkeys.getKeyName(key)
	local name = EMPHotkeys.keyNames[key]
	if name then
		return name
	end
	return "Error: Key Not Identified"
end

local function Set(tab)
	local ret = {}
	for _, value in ipairs(tab) do
		ret[value] = true
	end
	return ret
end

-- Blacklisted keys cannot be selected for hotkeys, if they somehow are then they will be reset to default on run start
local blacklistedKeys = Set {
	0, -- Every key not recognized by the game
	27, -- Escape
}

script.on_init(function()
	--if blacklistedKeys[Hyperspace.metaVariables.ins_dehack_hotkey] then Hyperspace.metaVariables.ins_dehack_hotkey = 305 end
	--if blacklistedKeys[Hyperspace.metaVariables.ins_speed_up_hotkey] then Hyperspace.metaVariables.ins_speed_up_hotkey = 93 end
	--if blacklistedKeys[Hyperspace.metaVariables.ins_speed_down_hotkey] then Hyperspace.metaVariables.ins_speed_down_hotkey = 91 end
	--if blacklistedKeys[Hyperspace.metaVariables.ins_speed_reset_hotkey] then Hyperspace.metaVariables.ins_speed_reset_hotkey = 36 end
end)

EMPHotkeys.powerToggle = false
EMPHotkeys.powerInverseToggle = false
EMPHotkeys.decreaseChargeToggle = false
EMPHotkeys.increaseChargeToggle = false
EMPHotkeys.aimToggle = false

script.on_game_event("EMP_POWERKEY_CONFIG_START", false, function() EMPHotkeys.powerToggle = true end)
script.on_game_event("EMP_POWERKEY_CONFIG_END_1", false, function() EMPHotkeys.powerToggle = false end)
script.on_game_event("EMP_POWERKEY_CONFIG_END_2", false, function() EMPHotkeys.powerToggle = false end)
script.on_game_event("EMP_INVERSEPOWERKEY_CONFIG_START", false, function() EMPHotkeys.powerInverseToggle = true end)
script.on_game_event("EMP_INVERSEPOWERKEY_CONFIG_END_1", false, function() EMPHotkeys.powerInverseToggle = false end)
script.on_game_event("EMP_INVERSEPOWERKEY_CONFIG_END_2", false, function() EMPHotkeys.powerInverseToggle = false end)
script.on_game_event("EMP_DECREASECHARGEKEY_CONFIG_START", false, function() EMPHotkeys.decreaseChargeToggle = true end)
script.on_game_event("EMP_DECREASECHARGEKEY_CONFIG_END_1", false, function() EMPHotkeys.decreaseChargeToggle = false end)
script.on_game_event("EMP_DECREASECHARGEKEY_CONFIG_END_2", false, function() EMPHotkeys.decreaseChargeToggle = false end)
script.on_game_event("EMP_INCREASECHARGEKEY_CONFIG_START", false, function() EMPHotkeys.increaseChargeToggle = true end)
script.on_game_event("EMP_INCREASECHARGEKEY_CONFIG_END_1", false, function() EMPHotkeys.increaseChargeToggle = false end)
script.on_game_event("EMP_INCREASECHARGEKEY_CONFIG_END_2", false, function() EMPHotkeys.increaseChargeToggle = false end)
script.on_game_event("EMP_AIMKEY_CONFIG_START", false, function() EMPHotkeys.aimToggle = true end)
script.on_game_event("EMP_AIMKEY_CONFIG_END_1", false, function() EMPHotkeys.aimToggle = false end)
script.on_game_event("EMP_AIMKEY_CONFIG_END_2", false, function() EMPHotkeys.aimToggle = false end)

script.on_internal_event(Defines.InternalEvents.ON_KEY_DOWN, function(key)
	if EMPHotkeys.powerToggle then
		if blacklistedKeys[key] then
			Hyperspace.Sounds:PlaySoundMix("powerDownSystem", -1, false)
			return
		end
		Hyperspace.metaVariables.EMPPowerKey = key
	end
    if EMPHotkeys.powerInverseToggle then
		if blacklistedKeys[key] then
			Hyperspace.Sounds:PlaySoundMix("powerDownSystem", -1, false)
			return
		end
		Hyperspace.metaVariables.EMPInverseKey = key
	end
	if EMPHotkeys.decreaseChargeToggle then
		if blacklistedKeys[key] then
			Hyperspace.Sounds:PlaySoundMix("powerDownSystem", -1, false)
			return
		end
		Hyperspace.metaVariables.EMPDecreaseChargeKey = key
	end
	if EMPHotkeys.increaseChargeToggle then
		if blacklistedKeys[key] then
			Hyperspace.Sounds:PlaySoundMix("powerDownSystem", -1, false)
			return
		end
		Hyperspace.metaVariables.EMPIncreaseChargeKey = key
	end
	if EMPHotkeys.aimToggle then
		if blacklistedKeys[key] then
			Hyperspace.Sounds:PlaySoundMix("powerDownSystem", -1, false)
			return
		end
		Hyperspace.metaVariables.EMPAimEMPKey = key
	end
end)

script.on_internal_event(Defines.InternalEvents.PRE_CREATE_CHOICEBOX, function(event)
	if event.eventName ~= "EMP_CONFIG" then return end
	local choices = event:GetChoices()
	for i = 0, choices:size() - 1 do
		local choice = choices[i]
		if choice.text:GetText() == "EMP_POWERKEY" then
			choice.text.isLiteral = true
			choice.text.data = "EMP Power Bind (Current Bind: " .. EMPHotkeys.getKeyName(Hyperspace.metaVariables.EMPPowerKey) .. ")"
		elseif choice.text:GetText() == "EMP_INVERSEPOWERKEY" then
			choice.text.isLiteral = true
			choice.text.data = "EMP Inverse Power Selecter Bind (Current Bind: " .. EMPHotkeys.getKeyName(Hyperspace.metaVariables.EMPInverseKey) .. ")"
		elseif choice.text:GetText() == "EMP_INCREASECHARGEKEY" then
			choice.text.isLiteral = true
			choice.text.data = "Increase Charge Bind (Current Bind: " .. EMPHotkeys.getKeyName(Hyperspace.metaVariables.EMPIncreaseChargeKey) .. ")"
		elseif choice.text:GetText() == "EMP_DECREASEECHARGEKEY" then
			choice.text.isLiteral = true
			choice.text.data = "Decrease Charge Bind (Current Bind: " .. EMPHotkeys.getKeyName(Hyperspace.metaVariables.EMPDecreaseChargeKey) .. ")"
		elseif choice.text:GetText() == "EMP_AIMKEY" then
			choice.text.isLiteral = true
			choice.text.data = "Aim EMP Bind (Current Bind: " .. EMPHotkeys.getKeyName(Hyperspace.metaVariables.EMPAimEMPKey) .. ")"
		end
	end
end)
--todo

--various save load glitches
--doors weird ... fixed?

--1.2.x
--notification 
--short range sensors / slug .. done
--misclick prevention toggle .. done
--diameter mult change .. done
--mv events
--selection fix

--CONFIG
mods.EMPGenerator = {}

mods.EMPGenerator.systemStats = {	[1] = {minCD = 15, maxCD = 25, minDiameter = 36, maxDiameter = 96 * 0.75},
									[2] = {minCD = 12, maxCD = 25, minDiameter = 36, maxDiameter = 96 * 1.25},
									[3] = {minCD = 09, maxCD = 25, minDiameter = 36, maxDiameter = 96 * 1.75},
									[4] = {minCD = 06, maxCD = 25, minDiameter = 36, maxDiameter = 96 * 2.25}}

--level cost determined in blueprints

--these values can be changed by other mods whenever (make sure to do this after it is done by this mod though)
mods.EMPGenerator.CutoffXNormal = 882 --VANILLA setting, changed later if needed 
mods.EMPGenerator.CutoffXBoss = 756 --VANILLA setting, changed later if needed

mods.EMPGenerator.systemId = Hyperspace.ShipSystem.NameToSystemId("empgenerator") --shorthand

mods.EMPGenerator.CutoffX = -1 --leftmost x cord of enemy box, set later on tick. Don't write to this from outside this file.
mods.EMPGenerator.BarChargeSetting = 0.5 -- 0 to 1
local InCombat = false
local OSClockLastTick = 0 --used to get DeltaTime, since I dont think there is a native function for that (at least accessible through lua)

function mods.EMPGenerator.GetRealTimeSinceLastIteration()
	local value = (os.clock() - OSClockLastTick)
	return value
end

function mods.EMPGenerator.GetGameTimeSinceLastIteration()
	if Hyperspace.Global.GetInstance():GetCApp().world.space.gamePaused == false then
		return Hyperspace.FPS.SpeedFactor / 16
	else
		return 0
	end
end

function mods.EMPGenerator.ClearSelections()
	--clears all crew from being selected, etc
	local crewControl = Hyperspace.Global.GetInstance():GetCApp().gui.crewControl
	crewControl.selectedCrew:clear()
	crewControl.potentialSelectedCrew:clear()
end

function mods.EMPGenerator.secondarySensorsActive()
	if Hyperspace.Global.GetInstance():GetShipManager(0):HasAugmentation("LIFE_SCANNER") > 0 then return true end

	--seems kind of expensive to iterate through all crew like this
	local crewList = Hyperspace.ships.player.vCrewList 
	for i = 0, crewList:size() - 1 do
		if crewList[i].iShipId == 0 and crewList[i]:IsTelepathic() == true then
			return true
		end
	end

	local crewList2 = Hyperspace.ships.enemy.vCrewList 
	for i = 0, crewList2:size() - 1 do
		if crewList2[i].iShipId == 0 and crewList2[i]:IsTelepathic() == true then
			return true
		end
	end
	return false
end

--world point
function mods.EMPGenerator.pointInShield(targetShip, point) --targetship is Int
	if Hyperspace.Global.GetInstance():GetShipManager(targetShip).shieldSystem.shields.power.first < 1 and Hyperspace.Global.GetInstance():GetShipManager(targetShip).shieldSystem.shields.power.super.first < 1 then return false end
	local shipManager = Hyperspace.Global.GetInstance():GetShipManager(targetShip)
	local a = shipManager.shieldSystem.baseShield.a --horizontal
	local b = shipManager.shieldSystem.baseShield.b --vertical
	local center = shipManager.shieldSystem.baseShield.center
	--if (x/a)^2 + (y/b)^2 <= 1, then inside
	local xRelative = point.x - center.x
	local yRelative = point.y - center.y
	local val = (xRelative / a) ^ 2 + (yRelative / b) ^ 2
	if val > 1 then return false 
	else return true end
end

function mods.EMPGenerator.pointInSuperShield(targetShip, point)
	if mods.EMPGenerator.pointInShield(targetShip, point) == false then return false
	elseif Hyperspace.Global.GetInstance():GetShipManager(targetShip).shieldSystem.shields.power.super.first > 0 then
		return true
	else
		return false
	end
end

function mods.EMPGenerator.GetCurrentSysPower(system)
	return system.powerState.first + system.iBonusPower + system.iBatteryPower
end

-- helper method to iterate through cvector
local function vter(cvec)
    local i = -1
    local n = cvec:size()
    return function()
        i = i + 1
        if i < n then return cvec[i] end
    end
end

--only for player
--assume only one other system in room
function mods.EMPGenerator.getOtherSystemInStackedEMPRoom(system)
	if system == nil then return nil end
	--seems kind of expensive to check this all the time?
	local systemOut = nil
	local systemId = system.roomId
	for i = 0, Hyperspace.Global.GetInstance():GetShipManager(0).vSystemList:size() - 1 do
		local systemI = Hyperspace.Global.GetInstance():GetShipManager(0).vSystemList[i]
		if systemI.roomId == systemId and systemI ~= system then
			systemOut = systemI
			return systemOut
		end
	end

	return systemOut
end

local ShipLoopActive = false --this is silly

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
	ShipLoopActive = true --set to false later if needed
end)

mods.EMPGenerator.PowerKeyActive = false
mods.EMPGenerator.PowerKeyActiveLastTick = false

mods.EMPGenerator.InversePowerKeyActive = false
mods.EMPGenerator.IncreaseChargeKeyActive = false
mods.EMPGenerator.DecreaseChargeKeyActive = false
mods.EMPGenerator.AimEMPKeyActive = false

mods.EMPGenerator.EMPGenerator_targetting = false --player
mods.EMPGenerator.EMPGenerator_targettingBlocked = false --player
mods.EMPGenerator.EMPGenerator_targettingTargetCount = 0

script.on_internal_event(Defines.InternalEvents.SYSTEM_BOX_KEY_DOWN, function(systemBox, key, shift)
	if Hyperspace.App.world.bStartedGame and key ~= 0 then 
		if key == Hyperspace.metaVariables.EMPInverseKey then 
			mods.EMPGenerator.InversePowerKeyActive = true --like shift, normally reduces power
		end


		if key == Hyperspace.metaVariables.EMPPowerKey then
			mods.EMPGenerator.PowerKeyActive = true
			mods.EMPGenerator.timeEndFlash = 0.150 + os.clock()
		elseif key == Hyperspace.metaVariables.EMPAimEMPKey then
			mods.EMPGenerator.AimEMPKeyActive = true
			if mods.EMPGenerator.EMPGenerator_targetting == true then mods.EMPGenerator.AimEMPKeyActive = false mods.EMPGenerator.EMPGenerator_targetting = false end
		elseif key == Hyperspace.metaVariables.EMPIncreaseChargeKey then
			mods.EMPGenerator.IncreaseChargeKeyActive = true
		elseif key == Hyperspace.metaVariables.EMPDecreaseChargeKey then
			mods.EMPGenerator.DecreaseChargeKeyActive = true
		end
	end
end)

script.on_internal_event(Defines.InternalEvents.ON_KEY_UP, function(key)
	if Hyperspace.App.world.bStartedGame and key ~= 0 then 
		if key == Hyperspace.metaVariables.EMPInverseKey then 
			mods.EMPGenerator.InversePowerKeyActive = false --like shift, normally reduces power
		end

		if key == Hyperspace.metaVariables.EMPPowerKey then
			mods.EMPGenerator.PowerKeyActive = false
		elseif key == Hyperspace.metaVariables.EMPAimEMPKey then
			mods.EMPGenerator.AimEMPKeyActive = false
			--Empgenerator_targetting = false 
		elseif key == Hyperspace.metaVariables.EMPIncreaseChargeKey then
			mods.EMPGenerator.IncreaseChargeKeyActive = false
		elseif key == Hyperspace.metaVariables.EMPDecreaseChargeKey then
			mods.EMPGenerator.DecreaseChargeKeyActive = false
		end
	end
end)

mods.EMPGenerator.timeEndFlash = -1

function mods.EMPGenerator.setSystemSelectionStateLogic(system)
	--local state = system:GetSelected()
	if os.clock() < mods.EMPGenerator.timeEndFlash then
		system:SetSelected(1)
	end

	--doesnt highlight overlay on system icon in the ship, do it otherwhere

	--mods.EMPGenerator.GetRealTimeSinceLastIteration()
end

function mods.EMPGenerator.getStunDuration(systemLevel, barcharge, isEnemy)
	--probably bad for crew to be able to be permastunned
	if isEnemy then
		return 5 + 2.5 * barcharge
	else --for player EMP system
		return 5 + 2.5 * barcharge
	end
end

function mods.EMPGenerator.getCDAndDiameter(systemLevel, barcharge)
	local data = {}
	--local performance = 1 
	--[[if systemLevel > 0 and systemLevel < #mods.EMPGenerator.LevelPerformances + 1 then performance = mods.EMPGenerator.LevelPerformances[systemLevel] end
		
	---1 to 1 with chargebar
	--Diameter: 2/3 base to 3/2 * performance 
	--CooldownMult: 3 / (4 * performance) to 4 / 3
	local exponent = (barcharge - 0.5)
	local diameterMult = (1.5000 ^ (exponent * 2)) * (performance ^ (exponent + 0.5))
	local cooldownMult = (1.3333 ^ (exponent * 2)) * (performance ^ (exponent - 0.5))
	
	if systemLevel == 0 then 
		diameterMult = 1 
		cooldownMult = 1 
	end--]]

	if systemLevel > 0 then 
		local ss = mods.EMPGenerator.systemStats[systemLevel] 
		--linear
		local cooldown = (ss.maxCD * barcharge + ss.minCD * (1 - barcharge))
		local diameter = (ss.maxDiameter * barcharge + ss.minDiameter * (1 - barcharge))

		data.Cooldown = cooldown
		data.Diameter = diameter
	end

	return data
end

--Handles tooltips and mousever descriptions per level
function mods.EMPGenerator.get_level_description_empgenerator(systemId, level, tooltip)
    if systemId == Hyperspace.ShipSystem.NameToSystemId("empgenerator") and level > 0 then
		local s = ""
		s = "CD: " .. string.format("%02.0f",mods.EMPGenerator.systemStats[level].minCD) .. "-" .. string.format("%02.0f",mods.EMPGenerator.systemStats[level].maxCD) .. 
		"s Range: " .. string.format("%.0f",mods.EMPGenerator.systemStats[level].minDiameter) .. "-" .. string.format("%.0f",mods.EMPGenerator.systemStats[level].maxDiameter) .. "px"
		--this will render above power state which sucks but nothing can be done about this except rewriting the tooltip later which I dont feel like doing
		if tooltip then 
			--s = s .. "\n\nMin. Cooldown: " .. string.format("%.2f",mods.EMPGenerator.systemStats[level].minCD)
			--s = s .. "\nMax. Diameter: " .. string.format("%.0f",mods.EMPGenerator.systemStats[level].maxDiameter)

			s = s .. "\n\nAdd Power: " .. EMPHotkeys.keyNames[Hyperspace.metaVariables.EMPPowerKey]
			s = s .. "\nRemove Power: " .. EMPHotkeys.keyNames[Hyperspace.metaVariables.EMPInverseKey] .. " + " .. EMPHotkeys.keyNames[Hyperspace.metaVariables.EMPPowerKey]
		end

		return s
    end
end

script.on_internal_event(Defines.InternalEvents.GET_LEVEL_DESCRIPTION, mods.EMPGenerator.get_level_description_empgenerator)

--Utility function to check if the SystemBox instance is for our customs system
function mods.EMPGenerator.is_empgenerator(systemBox)
    local systemName = Hyperspace.ShipSystem.SystemIdToName(systemBox.pSystem.iSystemType)
    return systemName == "empgenerator" 
end

mods.EMPGenerator.playerEMPHackFiredOnce = false
mods.EMPGenerator.enemyEMPHackFiredOnce = false

--Offsets of the button
local empgeneratorButtonOffset_x = 35
local empgeneratorButtonOffset_y = -57

mods.EMPGenerator.playerSystemBox = nil --preferable not to reference this unless you HAVE to

--Handles initialization of custom system box
local function empgenerator_construct_system_box(systemBox)
    if mods.EMPGenerator.is_empgenerator(systemBox) and systemBox.bPlayerUI == true then
        systemBox.extend.xOffset = 54

        local activateButton = Hyperspace.Button()
		mods.EMPGenerator.playerSystemBox = systemBox
        activateButton:OnInit("", Hyperspace.Point(empgeneratorButtonOffset_x, empgeneratorButtonOffset_y))
        activateButton.hitbox.x = 10
        activateButton.hitbox.y = 12
        activateButton.hitbox.w = 22
        activateButton.hitbox.h = 67
        systemBox.table.activateButton = activateButton

        systemBox.pSystem.bBoostable = false -- make the system unmannable
    end
end

script.on_internal_event(Defines.InternalEvents.CONSTRUCT_SYSTEM_BOX, empgenerator_construct_system_box)

--Handles mouse movement
local function empgenerator_mouse_move(systemBox, x, y)
    if mods.EMPGenerator.is_empgenerator(systemBox) and systemBox.table.activateButton ~= nil then
        local activateButton = systemBox.table.activateButton
        activateButton:MouseMove(x - empgeneratorButtonOffset_x, y - empgeneratorButtonOffset_y, false)
    end
    return Defines.Chain.CONTINUE
end
script.on_internal_event(Defines.InternalEvents.SYSTEM_BOX_MOUSE_MOVE, empgenerator_mouse_move)

mods.EMPGenerator.RedCircleImage = nil

--adapted from kokoro, and thank god they figured this out because I would have anguished figuring this out
function mods.EMPGenerator.convertScreenPosToWorldPos(mousePosition, forPlayerShip)
	if forPlayerShip then 
		local cApp = Hyperspace.Global.GetInstance():GetCApp()
		local combatControl = cApp.gui.combatControl
		local playerPosition = combatControl.playerShipPosition
		return Hyperspace.Point(mousePosition.x - playerPosition.x, mousePosition.y - playerPosition.y)
	else --enemy ship
		local cApp = Hyperspace.Global.GetInstance():GetCApp()
		local combatControl = cApp.gui.combatControl
		local position = combatControl.position
		local targetPosition = combatControl.targetPosition
		local enemyShipOriginX = position.x + targetPosition.x
		local enemyShipOriginY = position.y + targetPosition.y
		return Hyperspace.Point(mousePosition.x - enemyShipOriginX, mousePosition.y - enemyShipOriginY)
	end
end

function mods.EMPGenerator.convertWorldPosToScreenPos(worldPosition, forPlayerShip)
	if forPlayerShip then 
		--mousePosition.x - playerPosition.x = worldPosition.x
		--mousePosition.x = playerPosition.x + worldPosition.x
		local cApp = Hyperspace.Global.GetInstance():GetCApp()
		local combatControl = cApp.gui.combatControl
		local playerPosition = combatControl.playerShipPosition
		return Hyperspace.Point(playerPosition.x + worldPosition.x, playerPosition.y + worldPosition.y)
	else --enemy ship
		--mousePosition.x - enemyShipOriginX = worldPosition.x
		--mousePosition.x = enemyShipOriginX + worldPosition.x
		local cApp = Hyperspace.Global.GetInstance():GetCApp()
		local combatControl = cApp.gui.combatControl
		local position = combatControl.position
		local targetPosition = combatControl.targetPosition
		local enemyShipOriginX = position.x + targetPosition.x
		local enemyShipOriginY = position.y + targetPosition.y
		return Hyperspace.Point(enemyShipOriginX + worldPosition.x, enemyShipOriginY + worldPosition.y)
	end
end

mods.EMPGenerator.DotImage = nil

local function deleteProjectiles(x, y, r, preview)
	local spaceManager = Hyperspace.Global.GetInstance():GetCApp().world.space
	local projectileList = spaceManager.projectiles
	local i = 0
	while i < projectileList:size() do
		local projectile = projectileList[i]
		local x2 = projectile:GetWorldCenterPoint().x
		local y2 = projectile:GetWorldCenterPoint().y
	
		local projOnLeft = false
		local empOnLeft = false
		if x < mods.EMPGenerator.CutoffX or InCombat == false then empOnLeft = true end
		if projectile.currentSpace == 0 then projOnLeft = true end
		
		local pointCursorWorld = mods.EMPGenerator.convertScreenPosToWorldPos(Hyperspace.Point(x, y), empOnLeft)
	
		local distSq = (x2 - pointCursorWorld.x) * (x2 - pointCursorWorld.x) + (y2 - pointCursorWorld.y) * (y2 - pointCursorWorld.y)
		
		if distSq < r * r and projOnLeft == empOnLeft then 
			if preview then
				local pointCursorScreen = mods.EMPGenerator.convertWorldPosToScreenPos(Hyperspace.Point(x2, y2), empOnLeft)
				local width = 13
				local height = 13
				--fix graphic, often misaligned 
				if projectile:GetType() ~= 5 and projectile:GetType() ~= 6 then --5 is beam I think, 6 is asb
					Graphics.CSurface.GL_BlitImage(mods.EMPGenerator.DotImage, pointCursorScreen.x - width / 2, pointCursorScreen.y - height / 2, width, height, 0, Graphics.GL_Color(1, 0, 0, 1), false)
					mods.EMPGenerator.EMPGenerator_targettingTargetCount = mods.EMPGenerator.EMPGenerator_targettingTargetCount + 1
				end
			else
				if projectile:GetType() ~= 5 and projectile:GetType() ~= 6 then --5 is beam I think, 6 is asb
					--projectile:Kill() --add vfx to dis
					--kills after frame pause, fix somehow, THEREFORE
					--projectile.position = Hyperspace.Pointf(2000, 2000) --yeet this mf outta here so that it isnt seen before its cleared by next tick
					mods.EMPGenerator.EMPGenerator_targettingTargetCount = mods.EMPGenerator.EMPGenerator_targettingTargetCount + 1
					if projectile:GetType() == 4 then -- bomb 
						--projectile.death_animation
						local xProj = projectile.position.x
						local yProj = projectile.position.y
						local onLeft = false
						local space = 1
						if xProj < mods.EMPGenerator.CutoffX then
							onLeft = true
							space = 0
						end
						local wPoint = Hyperspace.Pointf(xProj, yProj)
						local wPointf = Hyperspace.Pointf(wPoint.x, wPoint.y)
						local blueprint = Hyperspace.Blueprints:GetWeaponBlueprint("THIS_BLUEPRINT_IS_MEANT_TO_BE_NIL") --produces default wp blueprint, should give default blast death effect which we want

						local laser = Hyperspace.Global.GetInstance():GetCApp().world.space:CreateLaserBlast(blueprint, wPointf, space, 0, wPointf, space, 0)
						laser.death_animation.fScale = 1
						laser.death_animation:Start(false)

						projectile:Kill()
					else
						projectile.death_animation:Start(false)
					end
				end
			end
		end
		i = i + 1
	end
end

local function stunDrones(x, y, r, duration, preview)
	local spaceManager = Hyperspace.Global.GetInstance():GetCApp().world.space
	local droneList = spaceManager.drones --doesnt count ship drones I think

	local i = 0
	while i < droneList:size() do
		local drone = droneList[i]
		local x2 = drone:GetWorldCenterPoint().x
		local y2 = drone:GetWorldCenterPoint().y
		
		local droneOnLeft = false
		local empOnLeft = false
		if x < mods.EMPGenerator.CutoffX or InCombat == false then empOnLeft = true end
		if drone:GetSpaceId() == 0 then droneOnLeft = true end
		
		local pointCursorWorld = mods.EMPGenerator.convertScreenPosToWorldPos(Hyperspace.Point(x, y), empOnLeft)
		
		local distSq = (x2 - pointCursorWorld.x) * (x2 - pointCursorWorld.x) + (y2 - pointCursorWorld.y) * (y2 - pointCursorWorld.y)
			
		if distSq < r * r and droneOnLeft == empOnLeft then 
			local isHackingDrone = false
			local isHackingDroneAirborne = false
			local isHackingDroneHacking = false
			if drone.prefRoom ~= nil then
				isHackingDrone = true
				local system = nil
				if drone.arrived == true then system = Hyperspace.Global.GetInstance():GetShipManager(drone:GetSpaceId()):GetSystemInRoom(drone.prefRoom) end
				if system ~= nil then --blow the drone up if its currently hacking
					if system.iHackEffect == 2 then 
						isHackingDroneHacking = true
					end
				end
				isHackingDroneAirborne = not drone.arrived
			end
			if preview then
				local pointCursorScreen = mods.EMPGenerator.convertWorldPosToScreenPos(Hyperspace.Point(x2, y2), empOnLeft)
				local width = 13
				local height = 13
				if isHackingDrone == false or isHackingDroneHacking == true or isHackingDroneAirborne == true then
					Graphics.CSurface.GL_BlitImage(mods.EMPGenerator.DotImage, pointCursorScreen.x - width / 2, pointCursorScreen.y - height / 2, width, height, 0, Graphics.GL_Color(0, 0, 1, 1), false)
					mods.EMPGenerator.EMPGenerator_targettingTargetCount = mods.EMPGenerator.EMPGenerator_targettingTargetCount + 1
				end 
			else
				if isHackingDrone == false then
					drone.ionStun = drone.ionStun + duration
					mods.EMPGenerator.EMPGenerator_targettingTargetCount = mods.EMPGenerator.EMPGenerator_targettingTargetCount + 1
				else --this is a hacking drone
					--local system = Hyperspace.Global.GetInstance():GetShipManager(drone:GetSpaceId()):GetSystemInRoom(drone.prefRoom)
					if isHackingDroneHacking == true then --blow the drone up if its currently hacking
						drone:BlowUp(true)
						mods.EMPGenerator.EMPGenerator_targettingTargetCount = mods.EMPGenerator.EMPGenerator_targettingTargetCount + 1
					elseif isHackingDroneAirborne == true then
						drone.ionStun = drone.ionStun + duration
						mods.EMPGenerator.EMPGenerator_targettingTargetCount = mods.EMPGenerator.EMPGenerator_targettingTargetCount + 1
					end
				end
			end
		end
		i = i + 1
	end
end

local function doesEnemyShipHaveFriendlyCrew()
    local crewList1 = Hyperspace.ships.player.vCrewList 
	local crewList2 = Hyperspace.ships.enemy.vCrewList

    for i = 0, crewList1:size() - 1 do
		local crew = crewList1[i]
        if crew.iShipId == 1 then return true end
    end

    for i = 0, crewList2:size() - 1 do
		local crew = crewList2[i]
        if crew.iShipId == 1 and crew.bMindControlled == true then return true end
    end

    return false
end

local function isPlayerHackingEnemy()
    local pShip = Hyperspace.Global.GetInstance():GetShipManager(0)
    local hacking = pShip.hackingSystem
    if hacking ~= nil then
        if hacking.effectTimer.first > 0 then return true end
    end
    return false
end

local function isEnemyShipCloakHidden()
    local enemyCloaked = false
    if Hyperspace.Global.GetInstance():GetShipManager(1) ~= nil then
        if Hyperspace.Global.GetInstance():GetShipManager(1).cloakSystem ~= nil then
            if Hyperspace.Global.GetInstance():GetShipManager(1).cloakSystem.bTurnedOn == true then
                enemyCloaked = true
            end
        end
    end
    if enemyCloaked == false then return false end
    if doesEnemyShipHaveFriendlyCrew() == true then return false end
    --if isPlayerHackingEnemy() == true then return false end

    return true
end

local function stunCrew(x, y, r, duration, preview)
	local empOnLeft = false
	if x < mods.EMPGenerator.CutoffX or InCombat == false then empOnLeft = true end
	
	local crewList = nil
	if empOnLeft == true then
		crewList = Hyperspace.ships.player.vCrewList 
	else
		crewList = Hyperspace.ships.enemy.vCrewList
	end
	
	for i = 0, crewList:size() - 1 do
		local crew = crewList[i]
		local x2 = crew:GetPosition().x
		local y2 = crew:GetPosition().y
		
		local pointCursorWorld = mods.EMPGenerator.convertScreenPosToWorldPos(Hyperspace.Point(x, y), empOnLeft)
		
		local distSq = (x2 - pointCursorWorld.x) * (x2 - pointCursorWorld.x) + (y2 - pointCursorWorld.y) * (y2 - pointCursorWorld.y)

		if distSq < r * r then 
			if preview then
				local pointCursorScreen = mods.EMPGenerator.convertWorldPosToScreenPos(Hyperspace.Point(x2, y2), empOnLeft)
				local width = 13
				local height = 13
				local index = 1
				if empOnLeft then index = 0 end

                --check for secondary sensors
				if (Hyperspace.ShipGraph.GetShipInfo(index):GetRoomBlackedOut(crew.iRoomId) == false or mods.EMPGenerator.secondarySensorsActive() == true) and not (isEnemyShipCloakHidden() == true and empOnLeft == false) then
					Graphics.CSurface.GL_BlitImage(mods.EMPGenerator.DotImage, pointCursorScreen.x - width / 2, pointCursorScreen.y - height / 2, width, height, 0, Graphics.GL_Color(1, 1, 0, 1), false)
					mods.EMPGenerator.EMPGenerator_targettingTargetCount = mods.EMPGenerator.EMPGenerator_targettingTargetCount + 1
				end
			else
				crew.fStunTime = crew.fStunTime + duration
				mods.EMPGenerator.EMPGenerator_targettingTargetCount = mods.EMPGenerator.EMPGenerator_targettingTargetCount + 1
			end
		end
	end
end

mods.EMPGenerator.EMPdoorList = {}
mods.EMPGenerator.EMPdoorOpenList = {}
mods.EMPGenerator.TimeUntilResetEMPDoorList = {}

local function arrContainsElement(arr, element)
	for i = 1, #arr do
		if element == arr[i] then return true end
	end
	return false
end

local function forceOpenDoors(x, y, r, preview)
	local empOnLeft = false
	if x < mods.EMPGenerator.CutoffX or InCombat == false then empOnLeft = true end

	local shipManager = nil
	if empOnLeft == true then
		shipManager = Hyperspace.Global.GetInstance():GetShipManager(0)
	else
		shipManager = Hyperspace.Global.GetInstance():GetShipManager(1)
	end
	local doorList = shipManager.ship.vDoorList
	--EMPdoorList = {}
	--EMPdoorOpenList = {}
	for i = 0, doorList:size() - 1 do
		local door = doorList[i]
		
		--WORLD COORDS
		local x2 = door.x
		local y2 = door.y

		local pointCursorWorld = mods.EMPGenerator.convertScreenPosToWorldPos(Hyperspace.Point(x, y), empOnLeft)
		
		local distSq = (x2 - pointCursorWorld.x) * (x2 - pointCursorWorld.x) + (y2 - pointCursorWorld.y) * (y2 - pointCursorWorld.y)

		if distSq < r * r then
			if preview then
                if not (isEnemyShipCloakHidden() == true and empOnLeft == false) then
                    local pointCursorScreen = mods.EMPGenerator.convertWorldPosToScreenPos(Hyperspace.Point(x2, y2), empOnLeft)

                    local width = 13
                    local height = 13

                    --dont exactly know why door position is 1px off... well it needs to be corrected now
                    local xOffset = 0
                    local yOffset = 0
                    if door.bVertical == true then yOffset = 1 
                    else xOffset = 1 end

                    Graphics.CSurface.GL_BlitImage(mods.EMPGenerator.DotImage, pointCursorScreen.x - width / 2 + xOffset, pointCursorScreen.y - height / 2 + yOffset, width, height, 0, Graphics.GL_Color(0, 0, 1, 1), false)
                end
            else
				--make doors return to original state after
				if empOnLeft == false and arrContainsElement(mods.EMPGenerator.EMPdoorList, door) == false then --the player can close their own doors!
					mods.EMPGenerator.EMPdoorList[#mods.EMPGenerator.EMPdoorList + 1] = door
					mods.EMPGenerator.EMPdoorOpenList[#mods.EMPGenerator.EMPdoorOpenList + 1] = door.bOpen
					mods.EMPGenerator.TimeUntilResetEMPDoorList[#mods.EMPGenerator.TimeUntilResetEMPDoorList + 1] = 10
				end

				door.health = 0
				door:ApplyDamage(1)
			end
			mods.EMPGenerator.EMPGenerator_targettingTargetCount = mods.EMPGenerator.EMPGenerator_targettingTargetCount + 1
		end
	end
end

local function applyIonDamage(x, y, r, preview, ionCount)
	local empOnLeft = false
	if x < mods.EMPGenerator.CutoffX or InCombat == false then empOnLeft = true end
	
	local shipManager = nil
	if empOnLeft == true then
		shipManager = Hyperspace.Global.GetInstance():GetShipManager(0)
	else
		shipManager = Hyperspace.Global.GetInstance():GetShipManager(1)
	end
	local systemList = shipManager.vSystemList
	for i = 0, systemList:size() - 1 do
		local system = systemList[i]
		
		--WORLD COORDS
		local x2 = system.location.x
		local y2 = system.location.y

		local pointCursorWorld = mods.EMPGenerator.convertScreenPosToWorldPos(Hyperspace.Point(x, y), empOnLeft)
		
		local distSq = (x2 - pointCursorWorld.x) * (x2 - pointCursorWorld.x) + (y2 - pointCursorWorld.y) * (y2 - pointCursorWorld.y)

		if distSq < r * r and system.iLockCount > 0 then
			if preview then
				local pointCursorScreen = mods.EMPGenerator.convertWorldPosToScreenPos(Hyperspace.Point(x2, y2), empOnLeft)

				local width = 13
				local height = 13
				Graphics.CSurface.GL_BlitImage(mods.EMPGenerator.DotImage, pointCursorScreen.x - width / 2, pointCursorScreen.y - height / 2, width, height, 0, Graphics.GL_Color(0, 1, 1, 1), false)
			else 
				system:IonDamage(ionCount)
			end
			mods.EMPGenerator.EMPGenerator_targettingTargetCount = mods.EMPGenerator.EMPGenerator_targettingTargetCount + 1
		end
	end
end

local function createFires(shipManager, empSystem, x, y, r, preview, count)
    local empOnLeft = false
	if x < mods.EMPGenerator.CutoffX or InCombat == false then empOnLeft = true end
    local roomList = nil
    if empOnLeft == true then
        roomList = Hyperspace.Global.GetInstance():GetShipManager(0).ship.vRoomList
    else
        roomList = Hyperspace.Global.GetInstance():GetShipManager(1).ship.vRoomList
    end
	for i = 0, roomList:size() - 1 do
		local room = roomList[i]
        local rw = room.rect.w
	    local rh = room.rect.h

        local x2 = room.rect.x + rw / 2
        local y2 = room.rect.y + rh / 2

        local pointCursorWorld = mods.EMPGenerator.convertScreenPosToWorldPos(Hyperspace.Point(x, y), empOnLeft)
        
        local distSq = (x2 - pointCursorWorld.x) * (x2 - pointCursorWorld.x) + (y2 - pointCursorWorld.y) * (y2 - pointCursorWorld.y)

        if distSq < r * r then
            if preview then
                local pointCursorScreen = mods.EMPGenerator.convertWorldPosToScreenPos(Hyperspace.Point(x2, y2), empOnLeft)

                local width = 13
                local height = 13
                Graphics.CSurface.GL_BlitImage(mods.EMPGenerator.DotImage, pointCursorScreen.x - width / 2, pointCursorScreen.y - height / 2, width, height, 0, Graphics.GL_Color(1, 0.5, 0, 1), false)
            else 
                local index = 1
                if empOnLeft == true then
                    index = 0
                end

                if math.random() <= 0.20 * count then
                    Hyperspace.Global.GetInstance():GetShipManager(index):StartFire(i)
                end
            end
            mods.EMPGenerator.EMPGenerator_targettingTargetCount = mods.EMPGenerator.EMPGenerator_targettingTargetCount + 1
        end

        --iterate over every tile in the room
        --[[for j = 0, rw/35 - 1 do
            for k = 0, rh/35 - 1 do
                --WORLD COORDS
                local x2 = room.rect.x + 35/2 + 35 * j
                local y2 = room.rect.y + 35/2 + 35 * k

                local pointCursorWorld = mods.EMPGenerator.convertScreenPosToWorldPos(Hyperspace.Point(x, y), empOnLeft)
                
                local distSq = (x2 - pointCursorWorld.x) * (x2 - pointCursorWorld.x) + (y2 - pointCursorWorld.y) * (y2 - pointCursorWorld.y)

                if distSq < r * r then
                    if preview then
                        local pointCursorScreen = mods.EMPGenerator.convertWorldPosToScreenPos(Hyperspace.Point(x2, y2), empOnLeft)

                        local width = 13
                        local height = 13
                        Graphics.CSurface.GL_BlitImage(mods.EMPGenerator.DotImage, pointCursorScreen.x - width / 2, pointCursorScreen.y - height / 2, width, height, 0, Graphics.GL_Color(1, 0.5, 0, 1), false)
                    else 
                        local index = 1
                        if empOnLeft == true then
                            index = 0
                        end

                        if math.random() <= 0.1 * count then
                            Hyperspace.Global.GetInstance():GetShipManager(index):StartFire(i)
                        end
                    end
                    mods.EMPGenerator.EMPGenerator_targettingTargetCount = mods.EMPGenerator.EMPGenerator_targettingTargetCount + 1
                end
            end
        end--]]
        if preview == false then
            shipManager:StartFire(empSystem:GetRoomId())
        end
	end
end

local function createEMPVFX(x, y, r)
	local onLeft = false
	local space = 1
	if x < mods.EMPGenerator.CutoffX then
		onLeft = true
		space = 0
	end
	if Hyperspace.Global.GetInstance():GetShipManager(1) ~= nil then
		if Hyperspace.Global.GetInstance():GetShipManager(1).bDestroyed == true then
			onLeft = true
			space = 0
		end
	end
	local wPoint = mods.EMPGenerator.convertScreenPosToWorldPos(Hyperspace.Pointf(x, y), onLeft)
	local wPointf = Hyperspace.Pointf(wPoint.x, wPoint.y)
	local blueprint = Hyperspace.Blueprints:GetWeaponBlueprint("EMPGENERATOR_EFFECT_VESSEL")

	local laser = Hyperspace.Global.GetInstance():GetCApp().world.space:CreateLaserBlast(blueprint, wPointf, space, 0, wPointf, space, 0)
	laser.death_animation.fScale = (r * 2 * 64.0 / 55.0) / 256
	laser.death_animation:Start(false)
end

function mods.EMPGenerator.fireEMPTest(x, y, r)
	mods.EMPGenerator.EMPGenerator_targettingTargetCount = 0
	deleteProjectiles(x, y, r, false)
	stunDrones(x, y, r, 6.5, false)
	stunCrew(x, y, r, 6.5, false)
	forceOpenDoors(x, y, r, false)
	--if(shipManager:HasAugmentation("EMPGENERATOR_ION_UPGRADE")) == 1 then
	--	applyIonDamage(x, y, r, false, 1)
	--end
	createEMPVFX(x, y, r)

	Hyperspace.Sounds:PlaySoundMix("ionHit3", -1, false)
end

function mods.EMPGenerator.fireEMP(x, y, r, cooldownIn, stunDuration, shipManager, empSystem)
	--local system = shipManager:GetSystem(Hyperspace.ShipSystem.NameToSystemId("empgenerator"))
	mods.EMPGenerator.EMPGenerator_targettingTargetCount = 0

	local empOnLeft = false
	if x < mods.EMPGenerator.CutoffX or InCombat == false then empOnLeft = true end

	local space = 0
	if empOnLeft == false then space = 1 end

	local canBypassSuperShields = false
	if shipManager:HasAugmentation("ZOLTAN_BYPASS") ~= 0 then canBypassSuperShields = true end

	deleteProjectiles(x, y, r, false) --these shouldnt be sensitive to super shield
	stunDrones(x, y, r, stunDuration, false) --these shouldnt be sensitive to super shield
	if shipManager.iShipId == space or mods.EMPGenerator.pointInSuperShield(space, mods.EMPGenerator.convertScreenPosToWorldPos(Hyperspace.Mouse.position, empOnLeft)) == false or canBypassSuperShields == true then
		stunCrew(x, y, r, stunDuration, false)
		forceOpenDoors(x, y, r, false)
		if(shipManager:HasAugmentation("EMPGENERATOR_ION_UPGRADE")) > 0 or (shipManager:HasAugmentation("EX_EMPGENERATOR_ION_UPGRADE")) > 0 then
			local count = shipManager:HasAugmentation("EMPGENERATOR_ION_UPGRADE") + shipManager:HasAugmentation("EX_EMPGENERATOR_ION_UPGRADE")
			applyIonDamage(x, y, r, false, count)
		end

        if(shipManager:HasAugmentation("EMPGENERATOR_FIRE_UPGRADE")) > 0 or (shipManager:HasAugmentation("EX_EMPGENERATOR_FIRE_UPGRADE")) > 0 then
			local count = shipManager:HasAugmentation("EMPGENERATOR_FIRE_UPGRADE") + shipManager:HasAugmentation("EX_EMPGENERATOR_FIRE_UPGRADE")
			createFires(shipManager, empSystem, x, y, r, false, count)
		end
	end
	createEMPVFX(x, y, r)

	Hyperspace.Sounds:PlaySoundMix("ionHit3", -1, false)

	local cooldownTime = cooldownIn
	local ionDamage = math.floor(cooldownTime / 5)
	local remainingTime = cooldownTime - ionDamage * 5

	empSystem:LockSystem(ionDamage + 1) --only does int
	empSystem.lockTimer:Start(5)
	empSystem.lockTimer.currTime = 5 - remainingTime
end

mods.EMPGenerator.HoldingChargeBar = false

--Handles click events 
local function empgenerator_click(systemBox, shift)
    if mods.EMPGenerator.is_empgenerator(systemBox) then
		local activateButton = systemBox.table.activateButton
		if (mods.EMPGenerator.EMPGenerator_targettingTargetCount > 0 or Hyperspace.metaVariables.EMPPreventMisclicks == 0) or (activateButton.bHover and activateButton.bActive) then
			if activateButton.bHover and activateButton.bActive then
				local mousePos = Hyperspace.Mouse.position 
				local yCursorPos = mousePos.y
				if yCursorPos > 644 then
					mods.EMPGenerator.EMPGenerator_targetting = true --Indicate that we are now targeting the system
					mods.EMPGenerator.ClearSelections()
				else
					mods.EMPGenerator.HoldingChargeBar = true
					--from 607 to 644
					local frac =  (644 - yCursorPos) / 37
					--lower Y (higher on screen) is more radius, more cooldown
					mods.EMPGenerator.BarChargeSetting = frac
				end
			elseif Hyperspace.Global.GetInstance():GetCApp().world.bStartedGame and mods.EMPGenerator.EMPGenerator_targetting == true then 
				mods.EMPGenerator.ClearSelections() --DOESNT WORK THIS EARLY IN
				if mods.EMPGenerator.EMPGenerator_targettingBlocked == false then
					mods.EMPGenerator.EMPGenerator_targetting = false 
					local mousePos = Hyperspace.Mouse.position 
					local xCursorPos = mousePos.x
					local yCursorPos = mousePos.y

					local data = mods.EMPGenerator.getCDAndDiameter(mods.EMPGenerator.GetCurrentSysPower(systemBox.pSystem), mods.EMPGenerator.BarChargeSetting)
					
					mods.EMPGenerator.fireEMP(xCursorPos, yCursorPos, data.Diameter / 2, data.Cooldown, mods.EMPGenerator.getStunDuration(mods.EMPGenerator.GetCurrentSysPower(systemBox.pSystem), mods.EMPGenerator.BarChargeSetting, false), Hyperspace.Global.GetInstance():GetShipManager(0), systemBox.pSystem)
				else
					mods.EMPGenerator.EMPGenerator_targetting = false --this removes some funny (funny as in bad) behavior we dont want.
				end
			end
		elseif mods.EMPGenerator.EMPGenerator_targetting == true and mods.EMPGenerator.EMPGenerator_targettingBlocked == false and activateButton.bHover == false then
			Hyperspace.Sounds:PlaySoundMix("powerUpFail", -1, false) --should we play this sound?
		end
    end
    return Defines.Chain.CONTINUE
end
script.on_internal_event(Defines.InternalEvents.SYSTEM_BOX_MOUSE_CLICK, empgenerator_click)

--handle rendering while targetting the system
script.on_render_event(Defines.RenderEvents.MOUSE_CONTROL, function()
	--scuffed way to tell if player is in event, map, main menu, etc. I don't think there's a better way to do this
    if mods.EMPGenerator.EMPGenerator_targetting == true and (ShipLoopActive == true or Hyperspace.Global.GetInstance():GetCApp().gui.bPaused == true) then

		local system = Hyperspace.Global.GetInstance():GetShipManager(0):GetSystem(Hyperspace.ShipSystem.NameToSystemId("empgenerator"))

		local data = mods.EMPGenerator.getCDAndDiameter(mods.EMPGenerator.GetCurrentSysPower(system), mods.EMPGenerator.BarChargeSetting)

        local mousePos = Hyperspace.Mouse.position 

		local D = data.Diameter
		local startX = D 
		
		local flip = true
		if InCombat then
			if mousePos.x < mods.EMPGenerator.CutoffX then --left, cut off right part
				startX = mousePos.x + D / 2 - mods.EMPGenerator.CutoffX
				flip = false
			else --right, cut off left part
				startX = mods.EMPGenerator.CutoffX + D / 2 - mousePos.x
				flip = true
			end
			if startX < 0 then startX = 0 end
		else
			startX = 0
		end
		--Graphics.CSurface.GL_BlitImage(CursorImage, mousePos.x - D / 2, mousePos.y - D / 2, D, D, 0, Graphics.GL_Color(1, 1, 1, 1), false)
		
		local var1 = (D - startX) / D
		local width = D * var1
		
		local xCorrection = (D - width) / 2
		if flip then xCorrection = -xCorrection end
		
		mods.EMPGenerator.EMPGenerator_targettingTargetCount = 0

		if mods.EMPGenerator.EMPGenerator_targettingBlocked == false then
		Graphics.CSurface.GL_BlitImagePartial(mods.EMPGenerator.RedCircleImage, mousePos.x - width / 2 - xCorrection, mousePos.y - D / 2, width, D, 0, var1, 0, 1, 1, Graphics.GL_Color(1, 1, 1, 1), flip)
			deleteProjectiles(mousePos.x, mousePos.y, data.Diameter / 2, true)
			stunDrones(mousePos.x, mousePos.y, data.Diameter / 2, nil, true)

			local empOnLeft = false
			if mousePos.x < mods.EMPGenerator.CutoffX or InCombat == false then empOnLeft = true end

			local space = 0
			if empOnLeft == false then space = 1 end

			local canBypassSuperShields = false
			if Hyperspace.Global.GetInstance():GetShipManager(0):HasAugmentation("ZOLTAN_BYPASS") ~= 0 then canBypassSuperShields = true end

			if Hyperspace.Global.GetInstance():GetShipManager(0).iShipId == space or mods.EMPGenerator.pointInSuperShield(space, mods.EMPGenerator.convertScreenPosToWorldPos(Hyperspace.Mouse.position, empOnLeft)) == false or canBypassSuperShields == true then
				if(Hyperspace.Global.GetInstance():GetShipManager(0):HasAugmentation("EMPGENERATOR_FIRE_UPGRADE")) > 0 or (Hyperspace.Global.GetInstance():GetShipManager(0):HasAugmentation("EX_EMPGENERATOR_FIRE_UPGRADE")) > 0 then
					createFires(nil, nil, mousePos.x, mousePos.y, data.Diameter / 2, true, 1)
				end
                if(Hyperspace.Global.GetInstance():GetShipManager(0):HasAugmentation("EMPGENERATOR_ION_UPGRADE")) > 0 or (Hyperspace.Global.GetInstance():GetShipManager(0):HasAugmentation("EX_EMPGENERATOR_ION_UPGRADE")) > 0 then
					applyIonDamage(mousePos.x, mousePos.y, data.Diameter / 2, true, 1)
				end
                forceOpenDoors(mousePos.x, mousePos.y, data.Diameter / 2, true)
                stunCrew(mousePos.x, mousePos.y, data.Diameter / 2, nil, true) --order matters, because draw order matters
			end
		end
	end
	ShipLoopActive = false --set to true if it is true in ShipLoop
end, function() end)

--handle cancelling targetting by right clicking
script.on_internal_event(Defines.InternalEvents.ON_MOUSE_R_BUTTON_DOWN, function(x,y) 
	local activateButton = mods.EMPGenerator.playerSystemBox.table.activateButton
	if activateButton.bHover and activateButton.bActive then
		local mousePos = Hyperspace.Mouse.position 
		local yCursorPos = mousePos.y
		if yCursorPos > 644 then
			mods.EMPGenerator.EMPGenerator_targetting = false
		else
			--mods.EMPGenerator.HoldingChargeBar = true
			local frac = 0.5
			mods.EMPGenerator.BarChargeSetting = frac
		end
	elseif mods.EMPGenerator.EMPGenerator_targetting == true then
		mods.EMPGenerator.EMPGenerator_targetting = false
	end
    return Defines.Chain.CONTINUE
end)

--Utility function to see if the system is ready for use
function mods.EMPGenerator.empgenerator_ready(shipSystem)
   	return not shipSystem:GetLocked() and shipSystem:Functioning()
end

-- raahhhhhh
function mods.EMPGenerator.setEMPSystemCostsForMV()

end

function mods.EMPGenerator.setAugmentRarity(augmentID, rarity)
	--this works???
	Hyperspace.Global.GetInstance():GetBlueprints():GetAugmentBlueprint(augmentID).desc.rarity = rarity
end

mods.EMPGenerator.Cursor1Image = nil
mods.EMPGenerator.Cursor2Image = nil
mods.EMPGenerator.Grid_off_image = nil
mods.EMPGenerator.Grid_on_image = nil
mods.EMPGenerator.Grid_select_image = nil
mods.EMPGenerator.Grid_purple_image = nil
mods.EMPGenerator.Charging_off_image = nil
mods.EMPGenerator.Charging_on_image = nil
mods.EMPGenerator.Charging_select_image = nil

mods.EMPGenerator.systemOverlay = nil

mods.EMPGenerator.buttonBase = nil
local function OnInitLogic()
	mods.EMPGenerator.RedCircleImage = Hyperspace.Resources:GetImageId("mouse/mouse_empgenerator_1024.png")
	
	mods.EMPGenerator.Grid_off_image = Hyperspace.Resources:GetImageId("systemUI/button_empgenerator_grid_off.png")
	mods.EMPGenerator.Grid_on_image = Hyperspace.Resources:GetImageId("systemUI/button_empgenerator_grid_on.png")
	mods.EMPGenerator.Grid_select_image = Hyperspace.Resources:GetImageId("systemUI/button_empgenerator_grid_select2.png")
	mods.EMPGenerator.Grid_purple_image = Hyperspace.Resources:GetImageId("systemUI/button_empgenerator_grid_select2.png")
	mods.EMPGenerator.Charging_off_image = Hyperspace.Resources:GetImageId("systemUI/button_empgenerator2_charging_off.png")
	mods.EMPGenerator.Charging_on_image = Hyperspace.Resources:GetImageId("systemUI/button_empgenerator2_charging_on.png")
	mods.EMPGenerator.Charging_select_image = Hyperspace.Resources:GetImageId("systemUI/button_empgenerator2_charging_select.png")

	mods.EMPGenerator.Cursor1Image = Hyperspace.Resources:GetImageId("mouse/cursor_EMP.png")
	mods.EMPGenerator.Cursor2Image = Hyperspace.Resources:GetImageId("mouse/cursor_EMP2.png")

	mods.EMPGenerator.systemOverlay = Hyperspace.Resources:GetImageId("icons/s_empgenerator_overlay2.png")

	EMPImage = Hyperspace.Resources:GetImageId("effects/empgenerator_system_effect.png")
	
	mods.EMPGenerator.DotImage = Hyperspace.Resources:GetImageId("mouse/DotImage.png")
	--mods.EMPGenerator.systemId = Hyperspace.ShipSystem.NameToSystemId("empgenerator") 
	
    mods.EMPGenerator.buttonBase = Hyperspace.Resources:CreateImagePrimitiveString("systemUI/button_empgenerator_base.png", empgeneratorButtonOffset_x, empgeneratorButtonOffset_y, 0, Graphics.GL_Color(1, 1, 1, 1), 1, false)

	if mods.multiverse ~= nil then --multiverse
		mods.EMPGenerator.CutoffXNormal = 873
		mods.EMPGenerator.CutoffXBoss = 747
		mods.EMPGenerator.setAugmentRarity("EMPGENERATOR_ION_UPGRADE", 0) --becomes internal upgrade, dont make it spawn in stores
        mods.EMPGenerator.setAugmentRarity("EMPGENERATOR_FIRE_UPGRADE", 0) --becomes internal upgrade, dont make it spawn in stores

	elseif mods.vertexutil ~= nil then --ins probably
		mods.EMPGenerator.CutoffXNormal = 873
		mods.EMPGenerator.CutoffXBoss = 747
		mods.EMPGenerator.setAugmentRarity("EMPGENERATOR_ION_UPGRADE", 3) 
        mods.EMPGenerator.setAugmentRarity("EMPGENERATOR_FIRE_UPGRADE", 4)
	else --vanilla nd shiz
		mods.EMPGenerator.CutoffXNormal = 882 --VANILLA setting
		mods.EMPGenerator.CutoffXBoss = 756 --VANILLA setting
		mods.EMPGenerator.setAugmentRarity("EMPGENERATOR_ION_UPGRADE", 3) 
        mods.EMPGenerator.setAugmentRarity("EMPGENERATOR_FIRE_UPGRADE", 4)
	end

	if Hyperspace.metaVariables.playerEMPHackFiredOnce == 1 then mods.EMPGenerator.playerEMPHackFiredOnce = true end
	if Hyperspace.metaVariables.enemyEMPHackFiredOnce == 1 then mods.EMPGenerator.enemyEMPHackFiredOnce = true end
end

--[[script.on_render_event(Defines.RenderEvents.SYSTEM_BOX, 
function() 
    return Defines.Chain.CONTINUE
end, 
function() 
	Hyperspace.Mouse.iTeleporting = 1
end)--]]

--copied from a lily system
--sets cursor
local playerCursorRestore = nil
local playerCursorRestoreInvalid = nil

script.on_internal_event(Defines.InternalEvents.ON_TICK, function()
    local shipManager = Hyperspace.ships.player
	local sys = mods.EMPGenerator.playerSystemBox
	local buttonHover = false
	if sys ~= nil then
		if sys.activateButton ~= nil then
			buttonHover = sys.activateButton.bHover
		end
	end

	--if (Hyperspace.Mouse.valid == false or buttonHover == true) and Hyperspace.Mouse.animateDoor == 0 then 
	--[[if Hyperspace.Mouse.animateDoor == 0 then --for now
		mods.EMPGenerator.EMPGenerator_targettingBlocked = false
	else
		mods.EMPGenerator.EMPGenerator_targettingBlocked = true
	end--]]

	if Hyperspace.Global.GetInstance():GetCApp().gui.event_pause == true or Hyperspace.Global.GetInstance():GetCApp().gui.menu_pause == true then
		mods.EMPGenerator.EMPGenerator_targettingBlocked = true
	else
		mods.EMPGenerator.EMPGenerator_targettingBlocked = false
	end

    if shipManager ~= nil and mods.EMPGenerator.EMPGenerator_targetting == true and mods.EMPGenerator.EMPGenerator_targettingBlocked == false then
        if playerCursorRestore == nil then
            playerCursorRestore = Hyperspace.Mouse.validPointer
            playerCursorRestoreInvalid = Hyperspace.Mouse.invalidPointer
        end
		if mods.EMPGenerator.EMPGenerator_targettingTargetCount > 0 then
			if Hyperspace.Mouse.validPointer ~= mods.EMPGenerator.Cursor1Image then
				Hyperspace.Mouse.validPointer = mods.EMPGenerator.Cursor1Image
				Hyperspace.Mouse.invalidPointer = mods.EMPGenerator.Cursor1Image
			end
		else
			if Hyperspace.Mouse.validPointer ~= mods.EMPGenerator.Cursor2Image then
				Hyperspace.Mouse.validPointer = mods.EMPGenerator.Cursor2Image
				Hyperspace.Mouse.invalidPointer = mods.EMPGenerator.Cursor2Image
			end
		end
    elseif playerCursorRestore ~= nil then
        Hyperspace.Mouse.validPointer = playerCursorRestore
        Hyperspace.Mouse.invalidPointer = playerCursorRestoreInvalid
        playerCursorRestore = nil
        playerCursorRestoreInvalid = nil
    end
end)

local function replaceCrew(crewToReplace, race)
	local name = crewToReplace:GetName()
	local roomId = crewToReplace.iRoomId
	crewToReplace:Kill(true) --ouch!
	Hyperspace.Global.GetInstance():GetShipManager(0):AddCrewMemberFromString(name, race, false, roomId, true, true)
end

local function countSpecies(speciesName)
	local count = 0
	for i = 0, Hyperspace.Global.GetInstance():GetShipManager(0).vCrewList:size() - 1 do
		if Hyperspace.Global.GetInstance():GetShipManager(0).vCrewList[i]:GetSpecies() == speciesName then
			count = count + 1
		end
	end
	return count
end

local function multiverseShipPatch()
	if Hyperspace.Global.GetInstance():GetShipManager(0).myBlueprint.blueprintName == "PLAYER_SHIP_EMPGENERATOR" then
		Hyperspace.Global.GetInstance():GetShipManager(0):AddAugmentation("HIDDEN FOR_MULTIVERSE")
		Hyperspace.Global.GetInstance():GetShipManager(0):AddAugmentation("HIDDEN SHIP_KESTREL")

		while countSpecies("lanius") < 1 do
			replaceCrew(Hyperspace.Global.GetInstance():GetShipManager(0).vCrewList[0], "lanius") --bp uses anaerobic, mv uses lanius, so has to fix here
		end
		
	elseif Hyperspace.Global.GetInstance():GetShipManager(0).myBlueprint.blueprintName == "PLAYER_SHIP_EMPGENERATOR_2" then
		Hyperspace.Global.GetInstance():GetShipManager(0):AddAugmentation("HIDDEN FOR_MULTIVERSE")
		Hyperspace.Global.GetInstance():GetShipManager(0):AddAugmentation("HIDDEN SHIP_STEALTH")
	elseif Hyperspace.Global.GetInstance():GetShipManager(0).myBlueprint.blueprintName == "PLAYER_SHIP_EMPGENERATOR_3" then
		Hyperspace.Global.GetInstance():GetShipManager(0):AddAugmentation("HIDDEN FOR_MULTIVERSE")
		Hyperspace.Global.GetInstance():GetShipManager(0):AddAugmentation("HIDDEN SHIP_LANIUS")

		while countSpecies("lanius") < 2 do
			local crew1 = Hyperspace.Global.GetInstance():GetShipManager(0).vCrewList[0] 
			local crew2 = Hyperspace.Global.GetInstance():GetShipManager(0).vCrewList[1]

			replaceCrew(crew1, "lanius") --bp uses anaerobic, mv uses lanius, so has to fix here
			replaceCrew(crew2, "lanius") --bp uses anaerobic, mv uses lanius, so has to fix here
		end
	end

	if(Hyperspace.Global.GetInstance():GetShipManager(0):HasAugmentation("EMPGENERATOR_ION_UPGRADE")) > 0 then
		--replace it with the external version
		Hyperspace.Global.GetInstance():GetShipManager(0):AddAugmentation("EX_EMPGENERATOR_ION_UPGRADE")
		Hyperspace.Global.GetInstance():GetShipManager(0):RemoveAugmentation("EMPGENERATOR_ION_UPGRADE")
	end

    if(Hyperspace.Global.GetInstance():GetShipManager(0):HasAugmentation("EMPGENERATOR_FIRE_UPGRADE")) > 0 then
		--replace it with the external version
		Hyperspace.Global.GetInstance():GetShipManager(0):AddAugmentation("EX_EMPGENERATOR_FIRE_UPGRADE")
		Hyperspace.Global.GetInstance():GetShipManager(0):RemoveAugmentation("EMPGENERATOR_FIRE_UPGRADE")
	end

    if mods.multiverse.systemIcons[Hyperspace.ShipSystem.NameToSystemId("empgenerator")] == nil then
        mods.multiverse.systemIcons[Hyperspace.ShipSystem.NameToSystemId("empgenerator")] = mods.multiverse.register_system_icon("empgenerator")
    end
end

script.on_internal_event(Defines.InternalEvents.GET_RUN_SEED, function()
	Hyperspace.metaVariables.EMPButtonAlreadyAdded = 0 

	--applies at start of run
	if mods.multiverse ~= nil then 
		multiverseShipPatch()
	end
end)

--applies in hangar
script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function()
	if mods.multiverse ~= nil and Hyperspace.Global.GetInstance():GetShipManager(0).iCustomizeMode == 2 then 
		multiverseShipPatch()
	end
end)

script.on_init(function()
	--OnInitLogic() 	--doesnt always run for some reason, fixed elsewhere
	--this seems to run on run start instead, so this goes here.
	--Hyperspace.CustomEventsParser.GetInstance():LoadEvent(Hyperspace.Global.GetInstance():GetCApp().world, "ADD_EMP_CONFIG_BUTTON", false, -1)
end)

local function getCurrentGridImage(systemBox)
	--need purple
	local activateButton = systemBox.table.activateButton
	if systemBox.pSystem.iHackEffect == 2 then
		if (os.clock() / 1.5) - math.floor(os.clock() / 1.5) > 0.5 then --2/3s per img sounds abt right?
			return mods.EMPGenerator.Grid_purple_image
		else
			return mods.EMPGenerator.Grid_on_image
		end
	end
	if activateButton.bActive then
		if activateButton.bHover and Hyperspace.Mouse.position.y > 644 then --select
			return mods.EMPGenerator.Grid_select_image
		else
			return mods.EMPGenerator.Grid_on_image
		end
	else
		return mods.EMPGenerator.Grid_off_image
	end	
end

local function getCurrentBarImage(systemBox)
	--need purple? maybe?
	local activateButton = systemBox.table.activateButton
	if activateButton.bActive and systemBox.pSystem.iHackEffect ~= 2 then
		if activateButton.bHover and Hyperspace.Mouse.position.y <= 644 then --select
			return mods.EMPGenerator.Charging_select_image
		else
			return mods.EMPGenerator.Charging_on_image
		end
	else
		return mods.EMPGenerator.Charging_off_image
	end	
end

local function autoLookForProjectilesToEMP(owner)
	local shootData = {x = -1, y = -1, shootNow = false}

	local spaceManager = Hyperspace.Global.GetInstance():GetCApp().world.space
	local projectileList = spaceManager.projectiles
	local i = 0
	while i < projectileList:size() do
		local projectile = projectileList[i]
		if projectile.ownerId == (1 - owner) and projectile.currentSpace == (1 - owner) then 
			local x2 = projectile:GetWorldCenterPoint().x
			local y2 = projectile:GetWorldCenterPoint().y
			
			local ownerIsEnemy = true
			if owner == 0 then ownerIsEnemy = false end

			local pointScreen = mods.EMPGenerator.convertWorldPosToScreenPos(Hyperspace.Point(x2, y2), ownerIsEnemy)

			if pointScreen.x > mods.EMPGenerator.CutoffX and owner == 1 then return shootData end --dont let it shoot right of player screen, AI is too stupid to allow it to stun its own ship.
			if pointScreen.x <= mods.EMPGenerator.CutoffX and owner == 0 then return shootData end 

			shootData.x = pointScreen.x
			shootData.y = pointScreen.y
			shootData.shootNow = true

			return shootData
		end
		i = i + 1
	end

	return shootData
end

local function autoLookForDronesToEMP(owner)
	local shootData = {x = -1, y = -1, shootNow = false}

	local spaceManager = Hyperspace.Global.GetInstance():GetCApp().world.space
	local droneList = spaceManager.drones

	local i = 0
	local counter = 0

	--local activeDroneList = {}

	while i < droneList:size() do
		local idrone = droneList[i]
		if idrone.iShipId == (1 - owner) and idrone.deployed == true and idrone.powered and idrone ~= nil then 
			counter = counter + 1
			--activeDroneList[counter] = idrone
		end
		i = i + 1
	end

	if counter == 0 then return shootData end

	--local drone = activeDroneList[math.random(0, #activeDroneList - 1)] --somehow is nil?

	i = 0
	local workingIndex = 0
	if counter > 1 then
		workingIndex = math.random(0, counter - 1) --seriously... you cant random between 0 and 0... are you really that pedantic
	end
	counter = 0

	while i < droneList:size() do
		local idrone = droneList[i]
		if idrone.iShipId == (1 - owner) and idrone.deployed == true and idrone.powered and idrone ~= nil then 
			if counter == workingIndex then
				local x2 = idrone:GetWorldCenterPoint().x
				local y2 = idrone:GetWorldCenterPoint().y

				local projOnLeft = false
				if idrone.currentSpace == 0 then projOnLeft = true end
				
				local pointScreen = mods.EMPGenerator.convertWorldPosToScreenPos(Hyperspace.Point(x2, y2), projOnLeft)

				shootData.x = pointScreen.x
				shootData.y = pointScreen.y
				shootData.shootNow = true

				return shootData
			end
			counter = counter + 1
			--activeDroneList[counter] = idrone
		end
		i = i + 1
	end
	return shootData  --should never be reached
end

local function autoLookForCrewToEMP(owner)
	local shootData = {x = -1, y = -1, shootNow = false}
	
	local crewList1 = nil
	if owner == 1 then
		crewList1 = Hyperspace.ships.player.vCrewList 
	else
		crewList1 = Hyperspace.ships.enemy.vCrewList 
	end
	--local crewList2 = Hyperspace.ships.enemy.vCrewList --lets not even bother with enemy stunning on their own ship, they are too stupid for this to make sense
	
	local count = 0
	--local crewListPlayer = {}
	for i = 0, crewList1:size() - 1 do
		local crew = crewList1[i]
		if crew.iShipId == (1 - owner) and crew:IsCrew() and crew ~= nil then --if you remove the second condition, the AI becomes schizophrenic and can EMP the mythical ship crew member.
			count = count + 1
			--crewListPlayer[count] = crew
		end
	end

	if count == 0 then return shootData end

	local i = 0
	local workingIndex = 0
	if count > 1 then
		workingIndex = math.random(0, count - 1) --seriously... you cant random between 0 and 0... are you really that pedantic
	end
	count = 0

	while i < crewList1:size() do
		local crew = crewList1[i]
		if crew.iShipId == (1 - owner) and crew:IsCrew() and crew ~= nil then 
			if count == workingIndex then
				local x2 = crew:GetLocation().x
				local y2 = crew:GetLocation().y

				local crewOnLeft = true
				if owner == 0 then crewOnLeft = false end

				local pointScreen = mods.EMPGenerator.convertWorldPosToScreenPos(Hyperspace.Point(x2, y2), crewOnLeft)

				shootData.x = pointScreen.x
				shootData.y = pointScreen.y
				shootData.shootNow = true

				return shootData
			end
			count = count + 1
			--activeDroneList[counter] = idrone
		end
		i = i + 1
	end
	return shootData  --should never be reached
end

--these arent saved on save/quit so the player can save quit every 7 seconds to prevent the enemy from ever using the system... whatever
mods.EMPGenerator.TimeUntilEnemyEMPsCrew = -1 --7.5 --s   make the enemy reluctant to use EMP on crew members
mods.EMPGenerator.EnemyGoingToStunCrew = false

mods.EMPGenerator.AIwaitTimeCrew = 7.5
mods.EMPGenerator.AIwaitTimeDrones = 0.50
mods.EMPGenerator.AIwaitTimeProjectiles = 0.15

--make it so projectiles and drones arent instantly destroyed at source
mods.EMPGenerator.TimeUntilEnemyEMPsTarget = -1
mods.EMPGenerator.EnemyGoingToEMPTarget = false

local function enemyAILogicOnTick()
	local system = Hyperspace.Global.GetInstance():GetShipManager(1):GetSystem(Hyperspace.ShipSystem.NameToSystemId("empgenerator"))

	local EMPdata = mods.EMPGenerator.getCDAndDiameter(mods.EMPGenerator.GetCurrentSysPower(system), mods.EMPGenerator.BarChargeSetting)

	if Hyperspace.Global.GetInstance():GetCApp().world.space.gamePaused == false then 
		mods.EMPGenerator.TimeUntilEnemyEMPsCrew = mods.EMPGenerator.TimeUntilEnemyEMPsCrew - mods.EMPGenerator.GetGameTimeSinceLastIteration() 
		mods.EMPGenerator.TimeUntilEnemyEMPsTarget = mods.EMPGenerator.TimeUntilEnemyEMPsTarget - mods.EMPGenerator.GetGameTimeSinceLastIteration() 
	end
	--this is spaghetti
	if mods.EMPGenerator.empgenerator_ready(system) and Hyperspace.Global.GetInstance():GetCApp().world.space.gamePaused == false then
		local shootData = autoLookForProjectilesToEMP(1)
		if shootData.shootNow == true and mods.EMPGenerator.EnemyGoingToEMPTarget == false then
			mods.EMPGenerator.TimeUntilEnemyEMPsTarget = mods.EMPGenerator.AIwaitTimeProjectiles --should be good enough 
			mods.EMPGenerator.EnemyGoingToEMPTarget = true
		end
		if shootData.shootNow == false then
			shootData = autoLookForDronesToEMP(1)
			if shootData.shootNow == true and mods.EMPGenerator.EnemyGoingToEMPTarget == false then
				mods.EMPGenerator.TimeUntilEnemyEMPsTarget = mods.EMPGenerator.AIwaitTimeDrones --should be good enough 
				mods.EMPGenerator.EnemyGoingToEMPTarget = true
			end
		end
		if shootData.shootNow == false and mods.EMPGenerator.EnemyGoingToStunCrew == false then
			--dont save to shootData
			local shootDataTemp = autoLookForCrewToEMP(1)
			if shootDataTemp.shootNow == true then mods.EMPGenerator.TimeUntilEnemyEMPsCrew = mods.EMPGenerator.AIwaitTimeCrew mods.EMPGenerator.EnemyGoingToStunCrew = true end
		end
		--[[if shootData["shootNow"] == true and EnemyGoingToEMPTarget == false then
			TimeUntilEnemyEMPsTarget = 0.15 --should be good enough 
			EnemyGoingToEMPTarget = true
		end--]]
		
		if mods.EMPGenerator.EnemyGoingToEMPTarget == true and mods.EMPGenerator.TimeUntilEnemyEMPsTarget < 0 then
			if shootData.shootNow == true then
				mods.EMPGenerator.fireEMP(shootData.x, shootData.y, EMPdata.Diameter / 2, EMPdata.Cooldown, mods.EMPGenerator.getStunDuration(mods.EMPGenerator.GetCurrentSysPower(system), mods.EMPGenerator.BarChargeSetting, true), Hyperspace.Global.GetInstance():GetShipManager(1), system)
			end
			mods.EMPGenerator.TimeUntilEnemyEMPsCrew = -1
			mods.EMPGenerator.EnemyGoingToStunCrew = false
			mods.EMPGenerator.TimeUntilEnemyEMPsTarget = -1
			mods.EMPGenerator.EnemyGoingToEMPTarget = false
		elseif mods.EMPGenerator.EnemyGoingToStunCrew == true and mods.EMPGenerator.TimeUntilEnemyEMPsCrew < 0 then
			shootData = autoLookForCrewToEMP(1) 
			if shootData.shootNow == true then
				mods.EMPGenerator.fireEMP(shootData.x, shootData.y, EMPdata.Diameter / 2, EMPdata.Cooldown, mods.EMPGenerator.getStunDuration(mods.EMPGenerator.GetCurrentSysPower(system), mods.EMPGenerator.BarChargeSetting, true), Hyperspace.Global.GetInstance():GetShipManager(1), system)
			end
			mods.EMPGenerator.TimeUntilEnemyEMPsCrew = -1
			mods.EMPGenerator.EnemyGoingToStunCrew = false
			mods.EMPGenerator.TimeUntilEnemyEMPsTarget = -1
			mods.EMPGenerator.EnemyGoingToEMPTarget = false
		end
	else
		mods.EMPGenerator.TimeUntilEnemyEMPsCrew = -1
		mods.EMPGenerator.EnemyGoingToStunCrew = false
		mods.EMPGenerator.TimeUntilEnemyEMPsTarget = -1
		mods.EMPGenerator.EnemyGoingToEMPTarget = false
	end
end

--close doors that have been EMPed automatically since opening them is so easy, its stupid for entire AI ships to be fully open for the rest of the fight.
local function checkForEMPDoors()
	local deltaTime = mods.EMPGenerator.GetGameTimeSinceLastIteration()
	for i = 1, #mods.EMPGenerator.EMPdoorList do
		if mods.EMPGenerator.EMPdoorList[i] ~= nil and mods.EMPGenerator.EMPdoorOpenList[i] ~= nil and mods.EMPGenerator.TimeUntilResetEMPDoorList[i] ~= nil then
			mods.EMPGenerator.TimeUntilResetEMPDoorList[i] = mods.EMPGenerator.TimeUntilResetEMPDoorList[i] - deltaTime
			if mods.EMPGenerator.TimeUntilResetEMPDoorList[i] < 0 and mods.EMPGenerator.EMPdoorList[i].bOpen == true then --only update doors that are open, doors that have since become closed must have been closed by the AI for a reason.
				mods.EMPGenerator.EMPdoorList[i].bOpen = mods.EMPGenerator.EMPdoorOpenList[i]
				mods.EMPGenerator.EMPdoorList[i] = nil
				mods.EMPGenerator.EMPdoorOpenList[i] = nil
				mods.EMPGenerator.TimeUntilResetEMPDoorList[i] = nil
			end
		end
	end
end

local function EMPHacked(shipIndex, empSystem) --shipIndex and empSystem of the hacked system
	--instantly use system, dont wait.

	--choose projs
	--choose drones
	--choose crew
	--only emp ship that emp system belongs too

	if ((shipIndex == 0 and mods.EMPGenerator.playerEMPHackFiredOnce == false) or (shipIndex == 1 and mods.EMPGenerator.enemyEMPHackFiredOnce == false)) then
		local owner = shipIndex --0 is player
		local shipManager = Hyperspace.Global.GetInstance():GetShipManager(owner)

		local x = nil
		local y = nil
		local data = mods.EMPGenerator.getCDAndDiameter(mods.EMPGenerator.GetCurrentSysPower(empSystem), 0.5)
		local r = data.Diameter / 2
		local cd = data.Cooldown

		local data1 = autoLookForProjectilesToEMP(1 - owner)
		local data2 = autoLookForDronesToEMP(1 - owner)
		local data3 = autoLookForCrewToEMP(1 - owner)

		if data1.shootNow == true then
			x = data1.x
			y = data1.y
		elseif data2.shootNow == true then
			x = data2.x
			y = data2.y
		elseif data3.shootNow == true then
			x = data3.x
			y = data3.y
		else
			--nothing
		end

		local isEnemy = false
		if shipIndex == 0 then isEnemy = true end

		if x ~= nil and y ~= nil then
			mods.EMPGenerator.fireEMP(x, y, r, mods.EMPGenerator.getStunDuration(mods.EMPGenerator.GetCurrentSysPower(empSystem), mods.EMPGenerator.BarChargeSetting, isEnemy), cd, shipManager, empSystem)
			if shipIndex == 0 and mods.EMPGenerator.playerEMPHackFiredOnce == false then mods.EMPGenerator.playerEMPHackFiredOnce = true Hyperspace.metaVariables.playerEMPHackFiredOnce = 1 end 
			if shipIndex == 1 and mods.EMPGenerator.enemyEMPHackFiredOnce == false then mods.EMPGenerator.enemyEMPHackFiredOnce = true Hyperspace.metaVariables.enemyEMPHackFiredOnce = 1 end 
		end
	end
end

local function OnTickLogic(systemBox)

	if mods.EMPGenerator.Grid_on_image == nil then OnInitLogic() end --script.on_init runs on ship start, not game start, so we need this

	InCombat = true
	local empSystem = systemBox.pSystem
	if Hyperspace.Global.GetInstance():GetShipManager(1) == nil then InCombat = false 
	elseif Hyperspace.Global.GetInstance():GetShipManager(1).bDestroyed then
		InCombat = false
	end

	--technically both enemy and player system go through here, but we shouldnt get double instances of emp hack effects
	if InCombat == true then
		if Hyperspace.Global.GetInstance():GetShipManager(0):GetSystem(Hyperspace.ShipSystem.NameToSystemId("empgenerator")) ~= nil then
			local playerempSystem = Hyperspace.Global.GetInstance():GetShipManager(0):GetSystem(Hyperspace.ShipSystem.NameToSystemId("empgenerator"))
			if playerempSystem.iHackEffect == 2 then --emp system hacked
				EMPHacked(0, playerempSystem)
			elseif mods.EMPGenerator.playerEMPHackFiredOnce ~= false then
				mods.EMPGenerator.playerEMPHackFiredOnce = false
				Hyperspace.metaVariables.playerEMPHackFiredOnce = 0
			end
		end
		if Hyperspace.Global.GetInstance():GetShipManager(1):GetSystem(Hyperspace.ShipSystem.NameToSystemId("empgenerator")) ~= nil then
			local enemyempSystem = Hyperspace.Global.GetInstance():GetShipManager(1):GetSystem(Hyperspace.ShipSystem.NameToSystemId("empgenerator"))
			if enemyempSystem.iHackEffect == 2 then --emp system hacked
				EMPHacked(1, enemyempSystem)
			elseif mods.EMPGenerator.enemyEMPHackFiredOnce ~= false then
				mods.EMPGenerator.enemyEMPHackFiredOnce = false
				Hyperspace.metaVariables.enemyEMPHackFiredOnce = 0
			end
		end
	end

	if Hyperspace.Global.GetInstance():GetCApp().world.space:DangerousEnvironment() == false then
		local activeEnemyShip = false
		if Hyperspace.Global.GetInstance():GetShipManager(1) ~= nil then 
			if Hyperspace.Global.GetInstance():GetShipManager(1).bDestroyed == false then
				activeEnemyShip = true 
			end
		end
		if Hyperspace.Global.GetInstance():GetShipManager(0).bJumping and activeEnemyShip == false then empSystem.iLockCount = 0 end --CLEAR ON JUMP
	end

	if systemBox.table.activateButton ~= nil then
		if systemBox.table.activateButton.bActive == false then mods.EMPGenerator.HoldingChargeBar = false end --should help
	end

	if mods.EMPGenerator.HoldingChargeBar == true then
		local mousePos = Hyperspace.Mouse.position 

		--need to hide selection... how

		local yCursorPos = mousePos.y
		--from 607 to 644
		local frac =  (644 - yCursorPos) / 37
		--lower Y (higher on screen) is more radius, more cooldown
		if frac > 1 then frac = 1 end
		if frac < 0 then frac = 0 end
		mods.EMPGenerator.BarChargeSetting = frac
	end

	if systemBox.bPlayerUI == false then
		enemyAILogicOnTick()
	end

	if Hyperspace.Global.GetInstance():GetCApp().world.space.gamePaused == false then 
		checkForEMPDoors()
	end

	if Hyperspace.Global.GetInstance():GetCApp().gui.combatControl.boss_visual == false then mods.EMPGenerator.CutoffX = mods.EMPGenerator.CutoffXNormal else mods.EMPGenerator.CutoffX = mods.EMPGenerator.CutoffXBoss end

	--band-aid solution 
	--one of the systems is still human repairable but idk I guess
	local stackedSystem = mods.EMPGenerator.getOtherSystemInStackedEMPRoom(empSystem)
	if stackedSystem ~= nil then
		--just make it auto repair or else it will be a headache
		if Hyperspace.Global.GetInstance():GetCApp().world.space.gamePaused == false then 
			if stackedSystem.healthState.first < stackedSystem.healthState.second then
				stackedSystem.repairedLastFrame = true
				stackedSystem.fRepairOverTime = stackedSystem.fRepairOverTime + mods.EMPGenerator.GetGameTimeSinceLastIteration() * 5
			end
			if empSystem.healthState.first < empSystem.healthState.second then
				empSystem.repairedLastFrame = true
				empSystem.fRepairOverTime = stackedSystem.fRepairOverTime + mods.EMPGenerator.GetGameTimeSinceLastIteration() * 5
			end
		end
		if stackedSystem.fRepairOverTime >= 100 then 
			stackedSystem.fRepairOverTime = 0
			stackedSystem:AddDamage(-1)
		end
		if empSystem.fRepairOverTime >= 100 then 
			empSystem.fRepairOverTime = 0
			empSystem:AddDamage(-1)
		end
	end

	if systemBox.table.activateButton ~= nil then --allow key input
		if systemBox.table.activateButton.bActive and mods.EMPGenerator.AimEMPKeyActive == true then
			mods.EMPGenerator.EMPGenerator_targetting = true --Indicate that we are now targeting the system
		end

		if mods.EMPGenerator.PowerKeyActive == true and mods.EMPGenerator.PowerKeyActiveLastTick == false then
			--try add power 
			if mods.EMPGenerator.InversePowerKeyActive == true then
				if mods.EMPGenerator.GetCurrentSysPower(empSystem) <= 0 then
					--nothing
				else
					empSystem:DecreasePower(true)
					Hyperspace.Sounds:PlaySoundMix("powerDownSystem", -1, false)
				end
			else
				if mods.EMPGenerator.GetCurrentSysPower(empSystem) >= empSystem.powerState.second then
					Hyperspace.Sounds:PlaySoundMix("powerUpFail", -1, false)
				else
					empSystem:IncreasePower(1, false)
					Hyperspace.Sounds:PlaySoundMix("powerUpSystem", -1, false)
				end
			end
		end

		if mods.EMPGenerator.IncreaseChargeKeyActive == true then
			mods.EMPGenerator.BarChargeSetting = mods.EMPGenerator.BarChargeSetting + 0.6 * mods.EMPGenerator.GetRealTimeSinceLastIteration()
			if mods.EMPGenerator.BarChargeSetting > 1 then mods.EMPGenerator.BarChargeSetting = 1 end
		elseif mods.EMPGenerator.DecreaseChargeKeyActive == true then
			mods.EMPGenerator.BarChargeSetting = mods.EMPGenerator.BarChargeSetting - 0.6 * mods.EMPGenerator.GetRealTimeSinceLastIteration()
			if mods.EMPGenerator.BarChargeSetting < 0 then mods.EMPGenerator.BarChargeSetting = 0 end
		end
	end

	mods.EMPGenerator.PowerKeyActiveLastTick = mods.EMPGenerator.PowerKeyActive

	--print(mods.EMPGenerator.pointInShield(0, mods.EMPGenerator.convertScreenPosToWorldPos(Hyperspace.Mouse.position, true)))

	OSClockLastTick = os.clock()
end

script.on_internal_event(Defines.InternalEvents.ON_MOUSE_L_BUTTON_UP, function() mods.EMPGenerator.HoldingChargeBar = false end)

--Handles custom rendering
local function empgenerator_render(systemBox, ignoreStatus)
	if Hyperspace.Global.GetInstance():GetShipManager(0).iCustomizeMode == 0 then
		if mods.EMPGenerator.is_empgenerator(systemBox) == true and systemBox.table.activateButton ~= nil then 
			local activateButton = systemBox.table.activateButton
			activateButton.bActive = mods.EMPGenerator.empgenerator_ready(systemBox.pSystem)
			Graphics.CSurface.GL_RenderPrimitive(mods.EMPGenerator.buttonBase)
			--systemBox.table.activateButton:OnRender()
			
			--mods.EMPGenerator.setSystemSelectionStateLogic(systemBox.pSystem)

			Graphics.CSurface.GL_BlitImage(getCurrentGridImage(systemBox), 36, -38, 40, 81, 0, Graphics.GL_Color(1, 1, 1, 1), false)
			local var1 = 1 - mods.EMPGenerator.BarChargeSetting
			Graphics.CSurface.GL_BlitImagePartial(getCurrentBarImage(systemBox), 36, -40 + 31 * (1 - mods.EMPGenerator.BarChargeSetting), 40, 31 * mods.EMPGenerator.BarChargeSetting, 0, 1, var1, 1, 1, Graphics.GL_Color(1, 1, 1, 1), false)
		
			local data = mods.EMPGenerator.getCDAndDiameter(mods.EMPGenerator.GetCurrentSysPower(systemBox.pSystem), mods.EMPGenerator.BarChargeSetting)

			--tooltip, should be fine enough
			if activateButton.bHover or mods.EMPGenerator.HoldingChargeBar == true then
				--Hyperspace.Mouse.bForceTooltip = true
				if activateButton.bActive then 
					if Hyperspace.Mouse.position.y <= 644 or mods.EMPGenerator.HoldingChargeBar == true then --charge bar 
						local s = "Move this slider up to increase diameter at expense of cooldown. Results scale with more power in system."
						s = s .. "\n\nCurrent Power Setting: " .. string.format("%.0f", mods.EMPGenerator.BarChargeSetting * 100) .. "%"

						s = s .. "\nPulse Diameter: " .. string.format("%.0f", data.Diameter) .. "px"
						s = s .. "\nCooldown: " .. string.format("%.1f", data.Cooldown) .. " secs"
						s = s .. "\nStun Duration: " .. string.format("%.1f", mods.EMPGenerator.getStunDuration(mods.EMPGenerator.GetCurrentSysPower(systemBox.pSystem), mods.EMPGenerator.BarChargeSetting, false)) .. " secs"

						s = s .. "\n\n+Charge Hotkey: " .. EMPHotkeys.keyNames[Hyperspace.metaVariables.EMPIncreaseChargeKey]
						s = s .. "\n-Charge Hotkey: " .. EMPHotkeys.keyNames[Hyperspace.metaVariables.EMPDecreaseChargeKey]

						--Hyperspace.Mouse.tooltip = s
						Hyperspace.Mouse:SetTooltip(s)
					else
						local s = "Aim the EMP."
						s = s .. "\n\nHotkey: " .. EMPHotkeys.keyNames[Hyperspace.metaVariables.EMPAimEMPKey]
						--Hyperspace.Mouse.tooltip = s
						Hyperspace.Mouse:SetTooltip(s)
					end
				else
					if Hyperspace.Mouse.position.y <= 644 or mods.EMPGenerator.HoldingChargeBar == true then --charge bar 
						local s = "The slider cannot be changed while the system is cooling down."
						s = s .. "\n\nCurrent Power Setting: " .. string.format("%.0f", mods.EMPGenerator.BarChargeSetting * 100) .. "%"

						s = s .. "\nPulse Diameter: " .. string.format("%.0f", data.Diameter) .. "px"
						s = s .. "\nCooldown: " .. string.format("%.1f", data.Cooldown) .. " secs"
						s = s .. "\nStun Duration: " .. string.format("%.1f", mods.EMPGenerator.getStunDuration(mods.EMPGenerator.GetCurrentSysPower(systemBox.pSystem), mods.EMPGenerator.BarChargeSetting, false)) .. " secs"

						s = s .. "\n\n+Charge Hotkey: " .. EMPHotkeys.keyNames[Hyperspace.metaVariables.EMPIncreaseChargeKey]
						s = s .. "\n-Charge Hotkey: " .. EMPHotkeys.keyNames[Hyperspace.metaVariables.EMPDecreaseChargeKey]

						--Hyperspace.Mouse.tooltip = s
						Hyperspace.Mouse:SetTooltip(s)
					else
						local s = "The EMP cannot be currently aimed, it is cooling down."
						s = s .. "\n\nHotkey: " .. EMPHotkeys.keyNames[Hyperspace.metaVariables.EMPAimEMPKey]
						--Hyperspace.Mouse.tooltip = s
						Hyperspace.Mouse:SetTooltip(s)
					end
				end
			end

			--have this here I guess since we can
			OnTickLogic(systemBox)
		end

		--sure this can be here
		if Hyperspace.metaVariables.EMPButtonAlreadyAdded == 0 and Hyperspace.Global.GetInstance():GetCApp().gui.event_pause == false then
			Hyperspace.CustomEventsParser.GetInstance():LoadEvent(Hyperspace.Global.GetInstance():GetCApp().world, "ADD_EMP_CONFIG_BUTTON", false, -1)
			Hyperspace.metaVariables.EMPButtonAlreadyAdded = 1
		end
	else
	end
end
script.on_render_event(Defines.RenderEvents.SYSTEM_BOX, 
function(systemBox, ignoreStatus) 
    return Defines.Chain.CONTINUE
end, empgenerator_render)

script.on_render_event(Defines.RenderEvents.SYSTEM_BOX, --has to be system box
function(systemBox, ignoreStatus) 
    return Defines.Chain.CONTINUE
end, 
function() 
	if mods.EMPGenerator.playerSystemBox ~= nil then
		mods.EMPGenerator.setSystemSelectionStateLogic(mods.EMPGenerator.playerSystemBox.pSystem)
	end
end)

script.on_render_event(Defines.RenderEvents.FTL_BUTTON, 
function() 
    return Defines.Chain.CONTINUE
end, 
function() 
	if mods.EMPGenerator.playerSystemBox ~= nil then
		--is this *really* the best way to do this
		if os.clock() < mods.EMPGenerator.timeEndFlash then
			local system = mods.EMPGenerator.playerSystemBox.pSystem
			local room = Hyperspace.Global.GetInstance():GetShipManager(0).ship.vRoomList[system:GetRoomId()]
			--local rw = room.rect.w
			--local rh = room.rect.h

			local pointScreen = mods.EMPGenerator.convertWorldPosToScreenPos(system.location, true)
			local x = pointScreen.x - mods.EMPGenerator.systemOverlay.width / 2
			local y = pointScreen.y - mods.EMPGenerator.systemOverlay.height / 2

			Graphics.CSurface.GL_BlitImage(mods.EMPGenerator.systemOverlay, x, y, mods.EMPGenerator.systemOverlay.width, mods.EMPGenerator.systemOverlay.height, 0, Graphics.GL_Color(1, 1, 0, 1), false)
		end
	end
end)





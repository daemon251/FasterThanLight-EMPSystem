--todo

--various save load glitches
--put global vars all in one place
--door emp preview placement .. fixed?
--doors weird ... fixed?
--change cursor

--1.1.0
--blue options .. done? maybe more to be done?
--add augment dynamically, MV internal upgrade thing
--systemId .. done... perhaps?
--change power gfx
--enemy doesnt choose to hack emp system?
--stealth b crashes in MV on pick
--realtime function
--exposed some more stuff on the developer side
--start beacon is no longer overriden, MV now works properly because of this
--fixed issue with incorrect offset in system list

--CONFIG
mods.EMPGenerator = {}

mods.EMPGenerator.BaseDiameter = 96 --px
mods.EMPGenerator.BaseCooldown = 20 --seconds
mods.EMPGenerator.LevelPerformances = {1.00, 1.25, 1.50, 1.75}
--level cost determined in blueprints

--these values can be changed by other mods whenever (make sure to do this after it is done by this mod though)
mods.EMPGenerator.CutoffXNormal = 882 --VANILLA setting, changed later if needed 
mods.EMPGenerator.CutoffXBoss = 756 --VANILLA setting, changed later if needed

mods.EMPGenerator.systemId = nil --set later, can be used as shorthand. you should only EVER read this value from outside this file.

mods.EMPGenerator.CutoffX = -1 --leftmost x cord of enemy box, set later on tick. Don't write to this from outside this file.
mods.EMPGenerator.BarChargeSetting = 0.5 -- 0 to 1
local InCombat = false
local OSClockLastTick = 0 --used to get DeltaTime, since I dont think there is a native function for that (at least accessible through lua)

function mods.EMPGenerator.GetGameTimeSinceLastIteration()
	if Hyperspace.Global.GetInstance():GetCApp().world.space.gamePaused == false then
		--return (Hyperspace.FPS.SpeedFactor / 0.111) * (os.clock() - OSClockLastTick) --wtf
		return Hyperspace.FPS.SpeedFactor / 16
	else
		return 0
	end
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
mods.EMPGenerator.eventButtonAdded = false

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(ship)
	ShipLoopActive = true --set to false later if needed
end)

mods.EMPGenerator.PowerKeyActive = false
mods.EMPGenerator.PowerKeyActiveLastTick = false

mods.EMPGenerator.InversePowerKeyActive = false
mods.EMPGenerator.IncreaseChargeKeyActive = false
mods.EMPGenerator.DecreaseChargeKeyActive = false
mods.EMPGenerator.AimEMPKeyActive = false

mods.EMPGenerator.EMPgenerator_targetting = false --player

script.on_internal_event(Defines.InternalEvents.SYSTEM_BOX_KEY_DOWN, function(systemBox, key, shift)
	if Hyperspace.App.world.bStartedGame and key ~= 0 then 
		if key == Hyperspace.metaVariables.EMPInverseKey then 
			mods.EMPGenerator.InversePowerKeyActive = true --like shift, normally reduces power
		end


		if key == Hyperspace.metaVariables.EMPPowerKey then
			mods.EMPGenerator.PowerKeyActive = true
		elseif key == Hyperspace.metaVariables.EMPAimEMPKey then
			mods.EMPGenerator.AimEMPKeyActive = true
			if mods.EMPGenerator.EMPgenerator_targetting == true then mods.EMPGenerator.AimEMPKeyActive = false mods.EMPGenerator.EMPgenerator_targetting = false end
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

function mods.EMPGenerator.getCDAndDiameterMult(systemLevel, barcharge)
	local data = {}

	local performance = 1 
	if systemLevel > 0 and systemLevel < #mods.EMPGenerator.LevelPerformances + 1 then performance = mods.EMPGenerator.LevelPerformances[systemLevel] end
		
	---1 to 1 with chargebar
	--Diameter: 2/3 base to 3/2 * performance 
	--CooldownMult: 3 / (4 * performance) to 4 / 3
	local exponent = (barcharge - 0.5)
	local diameterMult = (1.5000 ^ (exponent * 2)) * (performance ^ (exponent + 0.5))
	local cooldownMult = (1.3333 ^ (exponent * 2)) * (performance ^ (exponent - 0.5))
	
	if systemLevel == 0 then 
		diameterMult = 1 
		cooldownMult = 1 
	end

	data["CooldownMult"] = cooldownMult
	data["DiameterMult"] = diameterMult

	return data
end

--Handles tooltips and mousever descriptions per level
function mods.EMPGenerator.get_level_description_empgenerator(systemId, level, tooltip)
    if systemId == Hyperspace.ShipSystem.NameToSystemId("empgenerator") then
		local s = ""
		if level == 1 then s = string.format("%.2f",mods.EMPGenerator.LevelPerformances[1]) .. "x Performance" end
		if level == 2 then s = string.format("%.2f",mods.EMPGenerator.LevelPerformances[2]) .. "x Performance" end
		if level == 3 then s = string.format("%.2f",mods.EMPGenerator.LevelPerformances[3]) .. "x Performance" end
		if level == 4 then s = string.format("%.2f",mods.EMPGenerator.LevelPerformances[4]) .. "x Performance" end
		
		--this will render above power state which sucks but nothing can be done about this except rewriting the tooltip later which I dont feel like doing
		if tooltip then 
			s = s .. "\n\nMin. Cooldown: 15s / Performance"
			s = s .. "\nMax. Diameter: 144px * Performance"

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

--Handles initialization of custom system box
local function empgenerator_construct_system_box(systemBox)
    if mods.EMPGenerator.is_empgenerator(systemBox) and systemBox.bPlayerUI == true then
        --systemBox.extend.xOffset = 54

        local activateButton = Hyperspace.Button()
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
				end
			else
				if projectile:GetType() ~= 5 and projectile:GetType() ~= 6 then --5 is beam I think, 6 is asb
					--projectile:Kill() --add vfx to dis
					--kills after frame pause, fix somehow, THEREFORE
					--projectile.position = Hyperspace.Pointf(2000, 2000) --yeet this mf outta here so that it isnt seen before its cleared by next tick
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
						local blueprint = Hyperspace.Blueprints:GetWeaponBlueprint("THIS_BLUEPRINT_IS_MEANT_TO_BE_NIL") --produces default wp blueprint, should be good

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

local function stunDrones(x, y, r, preview)
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
			if preview then
				local pointCursorScreen = mods.EMPGenerator.convertWorldPosToScreenPos(Hyperspace.Point(x2, y2), empOnLeft)
				local width = 13
				local height = 13
				Graphics.CSurface.GL_BlitImage(mods.EMPGenerator.DotImage, pointCursorScreen.x - width / 2, pointCursorScreen.y - height / 2, width, height, 0, Graphics.GL_Color(0, 0, 1, 1), false)
			else
				--drone:BlowUp(false) --would prefer to stun
				drone.ionStun = drone.ionStun + 8
			end
		end
		i = i + 1
	end
end

local function stunCrew(x, y, r, preview)
	local empOnLeft = false
	if x < mods.EMPGenerator.CutoffX or InCombat == false then empOnLeft = true end
	
	local crewList = nil
	if empOnLeft == true then
		crewList = Hyperspace.ships.player.vCrewList --does this include enemy boarders?
	else
		crewList = Hyperspace.ships.enemy.vCrewList --does this include boarders?
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
				if Hyperspace.ShipGraph.GetShipInfo(index):GetRoomBlackedOut(crew.iRoomId) == false then
					Graphics.CSurface.GL_BlitImage(mods.EMPGenerator.DotImage, pointCursorScreen.x - width / 2, pointCursorScreen.y - height / 2, width, height, 0, Graphics.GL_Color(1, 1, 0, 1), false)
				end
			else
				crew.fStunTime = crew.fStunTime + 6.5
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
				local pointCursorScreen = mods.EMPGenerator.convertWorldPosToScreenPos(Hyperspace.Point(x2, y2), empOnLeft)

				local width = 13
				local height = 13

				--dont exactly know why door position is 1px off... well it needs to be corrected now
				local xOffset = 0
				local yOffset = 0
				if door.bVertical == true then yOffset = 1 
				else xOffset = 1 end

				Graphics.CSurface.GL_BlitImage(mods.EMPGenerator.DotImage, pointCursorScreen.x - width / 2 + xOffset, pointCursorScreen.y - height / 2 + yOffset, width, height, 0, Graphics.GL_Color(0, 0, 1, 1), false)
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
		end
	end
end

local function applyIonDamage(x, y, r, preview)
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
				system:IonDamage(1)
			end
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
	laser.death_animation.fScale = (r * 2 * 64.0 / 56.0) / 256
	laser.death_animation:Start(false)
end

function mods.EMPGenerator.fireEMPTest(x, y, r)
	deleteProjectiles(x, y, r, false)
	stunDrones(x, y, r, false)
	stunCrew(x, y, r, false)
	forceOpenDoors(x, y, r, false)
	--if(shipManager:HasAugmentation("EMPGENERATOR_ION_UPGRADE")) == 1 then
	--	applyIonDamage(x, y, r, false)
	--end
	createEMPVFX(x, y, r)

	Hyperspace.Sounds:PlaySoundMix("ionHit3", -1, false)
end

function mods.EMPGenerator.fireEMP(x, y, r, cooldownMult, shipManager, empSystem)
	--local system = shipManager:GetSystem(Hyperspace.ShipSystem.NameToSystemId("empgenerator"))
	deleteProjectiles(x, y, r, false)
	stunDrones(x, y, r, false)
	stunCrew(x, y, r, false)
	forceOpenDoors(x, y, r, false)
	if(shipManager:HasAugmentation("EMPGENERATOR_ION_UPGRADE")) == 1 then
		applyIonDamage(x, y, r, false)
	end
	createEMPVFX(x, y, r)

	Hyperspace.Sounds:PlaySoundMix("ionHit3", -1, false)

	local cooldownTime = mods.EMPGenerator.BaseCooldown * cooldownMult
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
        if activateButton.bHover and activateButton.bActive then
			local mousePos = Hyperspace.Mouse.position 
			local yCursorPos = mousePos.y
			if yCursorPos > 644 then
				mods.EMPGenerator.EMPgenerator_targetting = true --Indicate that we are now targeting the system
			else
				mods.EMPGenerator.HoldingChargeBar = true
				--from 607 to 644
				local frac =  (644 - yCursorPos) / 37
				--lower Y (higher on screen) is more radius, more cooldown
				mods.EMPGenerator.BarChargeSetting = frac
			end
        elseif Hyperspace.Global.GetInstance():GetCApp().world.bStartedGame and mods.EMPGenerator.EMPgenerator_targetting == true then 
            mods.EMPGenerator.EMPgenerator_targetting = false 
			local mousePos = Hyperspace.Mouse.position 
			local xCursorPos = mousePos.x
			local yCursorPos = mousePos.y

			local data = mods.EMPGenerator.getCDAndDiameterMult(systemBox.pSystem.powerState.first, mods.EMPGenerator.BarChargeSetting)
			
            mods.EMPGenerator.fireEMP(xCursorPos, yCursorPos, mods.EMPGenerator.BaseDiameter * data["DiameterMult"] / 2, data["CooldownMult"], Hyperspace.Global.GetInstance():GetShipManager(0), systemBox.pSystem)
        end
    end
    return Defines.Chain.CONTINUE
end
script.on_internal_event(Defines.InternalEvents.SYSTEM_BOX_MOUSE_CLICK, empgenerator_click)

--handle rendering while targetting the system
script.on_render_event(Defines.RenderEvents.MOUSE_CONTROL, function()
	--scuffed way to tell if player is in event, map, main menu, etc. I don't think there's a better way to do this
    if mods.EMPGenerator.EMPgenerator_targetting == true and (ShipLoopActive == true or Hyperspace.Global.GetInstance():GetCApp().gui.bPaused == true) then

		local system = Hyperspace.Global.GetInstance():GetShipManager(0):GetSystem(Hyperspace.ShipSystem.NameToSystemId("empgenerator"))

		local data = mods.EMPGenerator.getCDAndDiameterMult(system.powerState.first, mods.EMPGenerator.BarChargeSetting)

        local mousePos = Hyperspace.Mouse.position 

		local D = mods.EMPGenerator.BaseDiameter * data["DiameterMult"]
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
		
		--I dont know who designed it to work this way, but fuck you. I don't know how this works but it does.
		--hide when in esc pls
		Graphics.CSurface.GL_BlitImagePartial(mods.EMPGenerator.RedCircleImage, mousePos.x - width / 2 - xCorrection, mousePos.y - D / 2, width, D, 0, var1, 0, 1, 1, Graphics.GL_Color(1, 1, 1, 1), flip)
    
		deleteProjectiles(mousePos.x, mousePos.y, mods.EMPGenerator.BaseDiameter * data["DiameterMult"] / 2, true)
		stunDrones(mousePos.x, mousePos.y, mods.EMPGenerator.BaseDiameter * data["DiameterMult"] / 2, true)
		stunCrew(mousePos.x, mousePos.y, mods.EMPGenerator.BaseDiameter * data["DiameterMult"] / 2, true)
		forceOpenDoors(mousePos.x, mousePos.y, mods.EMPGenerator.BaseDiameter * data["DiameterMult"] / 2, true)
		if(Hyperspace.Global.GetInstance():GetShipManager(0):HasAugmentation("EMPGENERATOR_ION_UPGRADE")) == 1 then
			applyIonDamage(mousePos.x, mousePos.y, mods.EMPGenerator.BaseDiameter * data["DiameterMult"] / 2, true)
		end
	end
	ShipLoopActive = false --set to true if it is true in ShipLoop
end, function() end)

--handle cancelling targetting by right clicking
script.on_internal_event(Defines.InternalEvents.ON_MOUSE_R_BUTTON_DOWN, function(x,y) 
    if mods.EMPGenerator.EMPgenerator_targetting == true then
        mods.EMPGenerator.EMPgenerator_targetting = false
    end
    return Defines.Chain.CONTINUE
end)

--Utility function to see if the system is ready for use
function mods.EMPGenerator.empgenerator_ready(shipSystem)
   	return not shipSystem:GetLocked() and shipSystem:Functioning()
end

function mods.EMPGenerator.setAugmentRarity(augmentID, rarity)
	--this works???
	Hyperspace.Global.GetInstance():GetBlueprints():GetAugmentBlueprint(augmentID).desc.rarity = rarity
end

local CursorImage = nil;
mods.EMPGenerator.Grid_off_image = nil;
mods.EMPGenerator.Grid_on_image = nil;
mods.EMPGenerator.Grid_select_image = nil;
mods.EMPGenerator.Grid_purple_image = nil;
mods.EMPGenerator.Charging_off_image = nil;
mods.EMPGenerator.Charging_on_image = nil;
mods.EMPGenerator.Charging_select_image = nil;

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

	EMPImage = Hyperspace.Resources:GetImageId("effects/emp_explosion.png")
	
	mods.EMPGenerator.DotImage = Hyperspace.Resources:GetImageId("mouse/DotImage.png")
	mods.EMPGenerator.systemId = Hyperspace.ShipSystem.NameToSystemId("empgenerator") 
	
    mods.EMPGenerator.buttonBase = Hyperspace.Resources:CreateImagePrimitiveString("systemUI/button_empgenerator_base.png", empgeneratorButtonOffset_x, empgeneratorButtonOffset_y, 0, Graphics.GL_Color(1, 1, 1, 1), 1, false)

	if mods.multiverse ~= nil then --multiverse
		mods.EMPGenerator.CutoffXNormal = 873
		mods.EMPGenerator.CutoffXBoss = 747
		mods.EMPGenerator.setAugmentRarity("EMPGENERATOR_ION_UPGRADE", 3) --becomes internal upgrade, dont make it spawn in stores --- DOOOOO LATERRRRR
	elseif mods.vertexutil ~= nil then --ins probably
		mods.EMPGenerator.CutoffXNormal = 873
		mods.EMPGenerator.CutoffXBoss = 747
		mods.EMPGenerator.setAugmentRarity("EMPGENERATOR_ION_UPGRADE", 3) 
	else --vanilla nd shiz
		mods.EMPGenerator.CutoffXNormal = 882 --VANILLA setting
		mods.EMPGenerator.CutoffXBoss = 756 --VANILLA setting
		mods.EMPGenerator.setAugmentRarity("EMPGENERATOR_ION_UPGRADE", 3) 
	end

	if Hyperspace.metaVariables.playerEMPHackFiredOnce == 1 then mods.EMPGenerator.playerEMPHackFiredOnce = true end
	if Hyperspace.metaVariables.enemyEMPHackFiredOnce == 1 then mods.EMPGenerator.enemyEMPHackFiredOnce = true end
end

script.on_init(function()
	--OnInitLogic() 	--doesnt always run for some reason, fixed elsewhere
	--this seems to run on run start instead, so this goes here.
	--Hyperspace.CustomEventsParser.GetInstance():LoadEvent(Hyperspace.Global.GetInstance():GetCApp().world, "ADD_EMP_CONFIG_BUTTON", false, -1)
	mods.EMPGenerator.eventButtonAdded = false
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
	local shootData = {}
	shootData["x"] = -1
	shootData["y"] = -1
	shootData["shootNow"] = false

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

			shootData["x"] = pointScreen.x
			shootData["y"] = pointScreen.y
			shootData["shootNow"] = true

			return shootData
		end
		i = i + 1
	end

	return shootData
end

local function autoLookForDronesToEMP(owner)
	local shootData = {}
	shootData["x"] = -1
	shootData["y"] = -1
	shootData["shootNow"] = false

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

				shootData["x"] = pointScreen.x
				shootData["y"] = pointScreen.y
				shootData["shootNow"] = true

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
	local shootData = {}
	shootData["x"] = -1
	shootData["y"] = -1
	shootData["shootNow"] = false
	
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

				shootData["x"] = pointScreen.x
				shootData["y"] = pointScreen.y
				shootData["shootNow"] = true

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

	local EMPdata = mods.EMPGenerator.getCDAndDiameterMult(system.powerState.first, mods.EMPGenerator.BarChargeSetting)

	if Hyperspace.Global.GetInstance():GetCApp().world.space.gamePaused == false then 
		mods.EMPGenerator.TimeUntilEnemyEMPsCrew = mods.EMPGenerator.TimeUntilEnemyEMPsCrew - mods.EMPGenerator.GetGameTimeSinceLastIteration() 
		mods.EMPGenerator.TimeUntilEnemyEMPsTarget = mods.EMPGenerator.TimeUntilEnemyEMPsTarget - mods.EMPGenerator.GetGameTimeSinceLastIteration() 
	end
	--this is spaghetti
	if mods.EMPGenerator.empgenerator_ready(system) and Hyperspace.Global.GetInstance():GetCApp().world.space.gamePaused == false then
		local shootData = autoLookForProjectilesToEMP(1)
		if shootData["shootNow"] == true and mods.EMPGenerator.EnemyGoingToEMPTarget == false then
			mods.EMPGenerator.TimeUntilEnemyEMPsTarget = mods.EMPGenerator.AIwaitTimeProjectiles --should be good enough 
			mods.EMPGenerator.EnemyGoingToEMPTarget = true
		end
		if shootData["shootNow"] == false then
			shootData = autoLookForDronesToEMP(1)
			if shootData["shootNow"] == true and mods.EMPGenerator.EnemyGoingToEMPTarget == false then
				mods.EMPGenerator.TimeUntilEnemyEMPsTarget = mods.EMPGenerator.AIwaitTimeDrones --should be good enough 
				mods.EMPGenerator.EnemyGoingToEMPTarget = true
			end
		end
		if shootData["shootNow"] == false and mods.EMPGenerator.EnemyGoingToStunCrew == false then
			--dont save to shootData
			local shootDataTemp = autoLookForCrewToEMP(1)
			if shootDataTemp["shootNow"] == true then mods.EMPGenerator.TimeUntilEnemyEMPsCrew = mods.EMPGenerator.AIwaitTimeCrew mods.EMPGenerator.EnemyGoingToStunCrew = true end
		end
		--[[if shootData["shootNow"] == true and EnemyGoingToEMPTarget == false then
			TimeUntilEnemyEMPsTarget = 0.15 --should be good enough 
			EnemyGoingToEMPTarget = true
		end--]]
		
		if mods.EMPGenerator.EnemyGoingToEMPTarget == true and mods.EMPGenerator.TimeUntilEnemyEMPsTarget < 0 then
			if shootData["shootNow"] == true then
				mods.EMPGenerator.fireEMP(shootData["x"], shootData["y"], mods.EMPGenerator.BaseDiameter * EMPdata["DiameterMult"] / 2, EMPdata["CooldownMult"], Hyperspace.Global.GetInstance():GetShipManager(1), system)
			end
			mods.EMPGenerator.TimeUntilEnemyEMPsCrew = -1
			mods.EMPGenerator.EnemyGoingToStunCrew = false
			mods.EMPGenerator.TimeUntilEnemyEMPsTarget = -1
			mods.EMPGenerator.EnemyGoingToEMPTarget = false
		elseif mods.EMPGenerator.EnemyGoingToStunCrew == true and mods.EMPGenerator.TimeUntilEnemyEMPsCrew < 0 then
			shootData = autoLookForCrewToEMP(1) 
			if shootData["shootNow"] == true then
				mods.EMPGenerator.fireEMP(shootData["x"], shootData["y"], mods.EMPGenerator.BaseDiameter * EMPdata["DiameterMult"] / 2, EMPdata["CooldownMult"], Hyperspace.Global.GetInstance():GetShipManager(1), system)
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
		print(owner)
		local shipManager = Hyperspace.Global.GetInstance():GetShipManager(owner)

		local x = nil
		local y = nil
		local data = mods.EMPGenerator.getCDAndDiameterMult(empSystem.powerState.first, 0.5)
		local r = data["DiameterMult"] / 2
		local cdMult = data["CooldownMult"]

		local data1 = autoLookForProjectilesToEMP(1 - owner)
		local data2 = autoLookForDronesToEMP(1 - owner)
		local data3 = autoLookForCrewToEMP(1 - owner)

		if data1["shootNow"] == true then
			x = data1["x"]
			y = data1["y"]
		elseif data2["shootNow"] == true then
			x = data2["x"]
			y = data2["y"]
		elseif data3["shootNow"] == true then
			x = data3["x"]
			y = data3["y"]
		else
			--nothing
		end

		if x ~= nil and y ~= nil then
			mods.EMPGenerator.fireEMP(x, y, mods.EMPGenerator.BaseDiameter * r, cdMult, shipManager, empSystem)
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

	--technically both enemy and player system go through here, but we shouldnt get double instances of emp hack effects unless ion damage is queued
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
			mods.EMPGenerator.EMPgenerator_targetting = true --Indicate that we are now targeting the system
		end

		if mods.EMPGenerator.PowerKeyActive == true and mods.EMPGenerator.PowerKeyActiveLastTick == false then
			--try add power 
			if mods.EMPGenerator.InversePowerKeyActive == true then
				if empSystem.powerState.first <= 0 then
					--nothing
				else
					empSystem:DecreasePower(true)
					Hyperspace.Sounds:PlaySoundMix("powerDownSystem", -1, false)
				end
			else
				if empSystem.powerState.first >= empSystem.powerState.second then
					Hyperspace.Sounds:PlaySoundMix("powerUpFail", -1, false)
				else
					empSystem:IncreasePower(1, false)
					Hyperspace.Sounds:PlaySoundMix("powerUpSystem", -1, false)
				end
			end
		end

		if mods.EMPGenerator.IncreaseChargeKeyActive == true then
			mods.EMPGenerator.BarChargeSetting = mods.EMPGenerator.BarChargeSetting + 0.6 * (os.clock() - OSClockLastTick)
			if mods.EMPGenerator.BarChargeSetting > 1 then mods.EMPGenerator.BarChargeSetting = 1 end
		elseif mods.EMPGenerator.DecreaseChargeKeyActive == true then
			mods.EMPGenerator.BarChargeSetting = mods.EMPGenerator.BarChargeSetting - 0.6 * (os.clock() - OSClockLastTick)
			if mods.EMPGenerator.BarChargeSetting < 0 then mods.EMPGenerator.BarChargeSetting = 0 end
		end
	end

	mods.EMPGenerator.PowerKeyActiveLastTick = mods.EMPGenerator.PowerKeyActive

	OSClockLastTick = os.clock()
end

script.on_internal_event(Defines.InternalEvents.ON_MOUSE_L_BUTTON_UP, function() mods.EMPGenerator.HoldingChargeBar = false end)

--Handles custom rendering
local function empgenerator_render(systemBox, ignoreStatus)
	if Hyperspace.Global.GetInstance():GetShipManager(0).iCustomizeMode == 0 then
		if mods.EMPGenerator.is_empgenerator(systemBox) == false and systemBox.table.activateButton ~= nil then 
			local activateButton = systemBox.table.activateButton
			activateButton.bActive = mods.EMPGenerator.empgenerator_ready(systemBox.pSystem)
			Graphics.CSurface.GL_RenderPrimitive(mods.EMPGenerator.buttonBase)
			--systemBox.table.activateButton:OnRender()
			
			Graphics.CSurface.GL_BlitImage(getCurrentGridImage(systemBox), 36, -38, 40, 81, 0, Graphics.GL_Color(1, 1, 1, 1), false)
			local var1 = 1 - mods.EMPGenerator.BarChargeSetting
			Graphics.CSurface.GL_BlitImagePartial(getCurrentBarImage(systemBox), 36, -40 + 31 * (1 - mods.EMPGenerator.BarChargeSetting), 40, 31 * mods.EMPGenerator.BarChargeSetting, 0, 1, var1, 1, 1, Graphics.GL_Color(1, 1, 1, 1), false)
		
			local data = mods.EMPGenerator.getCDAndDiameterMult(systemBox.pSystem.powerState.first, mods.EMPGenerator.BarChargeSetting)

			--tooltip, should be fine enough
			if activateButton.bHover and activateButton.bActive or mods.EMPGenerator.HoldingChargeBar == true then
				Hyperspace.Mouse.bForceTooltip = true
				if Hyperspace.Mouse.position.y <= 644 or mods.EMPGenerator.HoldingChargeBar == true then --charge bar 
					local s = "Move this slider up to increase radius at expense of cooldown. Results scale with more power in system."
					s = s .. "\n\nCharge: " .. string.format("%.0f", mods.EMPGenerator.BarChargeSetting * 100) .. "%"
					s = s .. "\nDiameter Multiplier: " .. string.format("%.3f", data["DiameterMult"]) .. "x"
					s = s .. "\nCooldown Multiplier: " .. string.format("%.3f", data["CooldownMult"]) .. "x"

					s = s .. "\n\n+Charge Hotkey: " .. EMPHotkeys.keyNames[Hyperspace.metaVariables.EMPIncreaseChargeKey]
					s = s .. "\n-Charge Hotkey: " .. EMPHotkeys.keyNames[Hyperspace.metaVariables.EMPDecreaseChargeKey]

					Hyperspace.Mouse.tooltip = s
				else
					local s = "Aim the EMP."
					s = s .. "\n\nHotkey: " .. EMPHotkeys.keyNames[Hyperspace.metaVariables.EMPAimEMPKey]
					Hyperspace.Mouse.tooltip = s
				end
			end

			--have this here I guess since we can
			OnTickLogic(systemBox)
		end

		--sure this can be here
		if mods.EMPGenerator.eventButtonAdded == false and Hyperspace.Global.GetInstance():GetCApp().gui.event_pause == false then
			print("A")
			Hyperspace.CustomEventsParser.GetInstance():LoadEvent(Hyperspace.Global.GetInstance():GetCApp().world, "ADD_EMP_CONFIG_BUTTON", false, -1)
			mods.EMPGenerator.eventButtonAdded = true
		end
	else
	end
end
script.on_render_event(Defines.RenderEvents.SYSTEM_BOX, 
function(systemBox, ignoreStatus) 
    return Defines.Chain.CONTINUE
end, empgenerator_render)


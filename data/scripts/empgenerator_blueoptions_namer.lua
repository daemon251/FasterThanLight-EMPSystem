
script.on_internal_event(Defines.InternalEvents.PRE_CREATE_CHOICEBOX, function(event)
    local playerShipHasEMPSystem = false
    if Hyperspace.Global.GetInstance():GetShipManager(0):GetSystem(Hyperspace.ShipSystem.NameToSystemId("empgenerator")) ~= nil then
        playerShipHasEMPSystem = true
    end
    if playerShipHasEMPSystem == true then
        local choices = event:GetChoices()
        for i = 0, choices:size() - 1 do
            --we add EMPGenerator to several blue options elsewhere, we want to rename it from Defense Drone / Ion Weapon / wtv to EMP Generator
            local choice = choices[i]
            local text = choice.text:GetText()
            if string.find(text, "(Ion Weapon)") then
                choice.text.isLiteral = true --set true, this is fine because we already got the data from the text id if it was used
                choice.text.data = "(Ion Weapon / EMP Generator)" .. string.sub(text, 1 + 12, #text)
            elseif string.find(text, "(Defense Drone)") then
                choice.text.isLiteral = true --set true, this is fine because we already got the data from the text id if it was used
                choice.text.data = "(Defense Drone / EMP Generator)" .. string.sub(text, 1 + 15, #text)
            end
        end
    end
end)
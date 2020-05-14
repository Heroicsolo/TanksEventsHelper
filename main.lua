local addonName, ns = ...

local LibEvent = LibStub:GetLibrary("LibEvent.7000")
local LibSchedule = LibStub:GetLibrary("LibSchedule.7000")
local LibItemInfo = LibStub:GetLibrary("LibItemInfo.7000")

local inspectByAddon = false
local guids, inspecting = {}, false
local members, numMembers = {}, 0

local itemsSlotTable = {
	15,	--INVSLOT_BACK
	9,	--INVSLOT_WRIST
	10,	--INVSLOT_HAND
	6,	--INVSLOT_WAIST
	7,	--INVSLOT_LEGS
	8,	--INVSLOT_FEET
	11,	--INVSLOT_FINGER1
	12,	--INVSLOT_FINGER2
	13,	--INVSLOT_TRINKET1
	14,	--INVSLOT_TRINKET2
	16,	--INVSLOT_MAINHAND
	17,	--INVSLOT_OFFHAND
}

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(self, event, ...)
	return self[event] and self[event](self, event, ...)
end)
f:RegisterEvent("ADDON_LOADED")

local function Print(text, ...)
	if text then
		if text:match("%%[dfqs%d%.]") then
			DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00".. addonName ..":|r " .. format(text, ...))
		else
			DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00".. addonName ..":|r " .. strjoin(" ", text, tostringall(...)))
		end
	end
end

-- Clear
hooksecurefunc("ClearInspectPlayer", function()
    inspecting = false
end)

-- @trigger UNIT_INSPECT_STARTED
hooksecurefunc("NotifyInspect", function(unit)
    local guid = UnitGUID(unit)
    if (not guid or not inspectByAddon) then return end
    local data = guids[guid]
    if (data) then
        data.unit = unit
        data.name, data.realm = UnitName(unit)
    else
        data = {
            unit   = unit,
            guid   = guid,
            class  = select(2, UnitClass(unit)),
            level  = UnitLevel(unit),
            ilevel = -1,
            spec   = nil,
            hp     = UnitHealthMax(unit),
            timer  = time(),
        }
        data.name, data.realm = UnitName(unit)
        guids[guid] = data
    end
    if (not data.realm) then
        data.realm = GetRealmName()
    end
    data.expired = time() + 3
    inspecting = data
    LibEvent:trigger("UNIT_INSPECT_STARTED", data)
end)

function GetInspecting(unit)
	if (unit and guids[UnitGUID(unit)]) then return true end
    if (inspecting and inspecting.expired > time()) then
        return inspecting
    end
end

-- @trigger UNIT_INSPECT_READY
LibEvent:attachEvent("INSPECT_READY", function(this, guid)
    if (not guids[guid] or not GetInspecting()) then return end

    LibSchedule:AddTask({
        identity  = guid,
        timer     = 0.5,
        elasped   = 0.8,
        expired   = GetTime() + 4,
        data      = guids[guid],
        onTimeout = function(self) inspecting = false end,
        onExecute = function(self)
            local count, ilevel, _, weaponLevel, isArtifact, maxLevel = LibItemInfo:GetUnitItemLevel(self.data.unit)
            if (ilevel <= 0) then return true end

            if (ilevel > 0) then
                --if (UnitIsVisible(self.data.unit) or self.data.ilevel == ilevel) then
                    self.data.timer = time()
                    self.data.name = UnitName(self.data.unit)
                    self.data.class = select(2, UnitClass(self.data.unit))
                    self.data.ilevel = ilevel
                    self.data.maxLevel = maxLevel
                    self.data.hp = UnitHealthMax(self.data.unit)
                    self.data.weaponLevel = weaponLevel
                    self.data.isArtifact = isArtifact
                    LibEvent:trigger("UNIT_INSPECT_READY", self.data)
                    inspecting = false
					inspectByAddon = false

					CheckTankCorruption(self.data.name.."-"..self.data.realm)
					
                    return true
                --else
                --    self.data.ilevel = ilevel
                --    self.data.maxLevel = maxLevel
                --end
            end
        end,
    })
end)

-- @trigger RAID_INSPECT_STARTED
function SendInspect(unit)
    if (GetInspecting(unit)) then return end
    if (unit and UnitIsVisible(unit) and CanInspect(unit)) then
        ClearInspectPlayer()
		inspectByAddon = true
        NotifyInspect(unit)
        LibEvent:trigger("RAID_INSPECT_STARTED", members[UnitGUID(unit)])
        return
    end
end

function f:ADDON_LOADED(event, addon)
	if addon == addonName then
		Print('Loaded')
		f:RegisterEvent("READY_CHECK")
	end
end

function f:READY_CHECK(starter, timer)
	CheckTanks()
end

function PrintResultsToChat(msg)
	if IsInRaid() then
		SendChatMessage(msg, string.upper("raid"))
	elseif IsInGroup() then
		SendChatMessage(msg, string.upper("party"))
	else
		Print(msg)
	end
end

function CheckTanks()
	PrintResultsToChat("["..addonName.."]: Checking tanks...")

	local n = GetNumGroupMembers() or 0

	local inRaid = IsInRaid()
	local inGroup = IsInGroup()

	local withoutWardenEssence = {}
	local withoutAnimaEssence = {}
	local withoutBothEssences = {}
	local outOfRange = {}

	if n < 1 then
		local playerName = UnitName('player')
		local wardenFound, animaFound = CheckTankEssences('player', playerName)
		if not wardenFound then withoutWardenEssence[#withoutWardenEssence + 1] = playerName end
		if not animaFound then withoutAnimaEssence[#withoutAnimaEssence + 1] = playerName end
		if not animaFound and not wardenFound then withoutBothEssences[#withoutBothEssences + 1] = playerName end
		CheckTankCorruption(playerName)
	else
		for i=1,n do
			local name,subgroup,_,unit,online
			
			online = true
			
			if not inRaid and i <= 5 then
				unit = i == 1 and 'player' or 'party'..(i-1)
				name = UnitName(unit)
				subgroup = 1
			else
				name,_,subgroup,_,_,_,_,online = GetRaidRosterInfo(i)
				unit = "raid"..i
			end

			if UnitGroupRolesAssigned(unit) == "TANK" then
				if not CheckInteractDistance(unit, 1) or not online or not CanInspect(unit) then
					outOfRange[#outOfRange + 1] = name
				else
					local wardenFound, animaFound = CheckTankEssences(unit, name)
					if not wardenFound then withoutWardenEssence[#withoutWardenEssence + 1] = name end
					if not animaFound then withoutAnimaEssence[#withoutAnimaEssence + 1] = name end
					if not animaFound and not wardenFound then withoutBothEssences[#withoutBothEssences + 1] = name end
					if i > 1 then
						SendInspect(unit)
					else
						CheckTankCorruption(name)
					end
				end
			end
		end
	end
	
	if #withoutWardenEssence == 0 and #withoutAnimaEssence == 0 then
		PrintResultsToChat("["..addonName.."]: ALL ESSENCES ARE OK")
		return
	end
	
	local msg = "WITHOUT WARDEN ESSENCE RANK 3: "
	
	if #withoutWardenEssence > 0 then
		for i=1,#withoutWardenEssence do
			if i > 1 then
				msg = msg..", "..withoutWardenEssence[i]
			else
				msg = msg..withoutWardenEssence[i]
			end
		end
		
		PrintResultsToChat(msg)
	end
	
	msg = "WITHOUT ANIMA ESSENCE: "
	
	if #withoutAnimaEssence > 0 then
		for i=1,#withoutAnimaEssence do
			if i > 1 then
				msg = msg..", "..withoutAnimaEssence[i]
			else
				msg = msg..withoutAnimaEssence[i]
			end
		end
		
		PrintResultsToChat(msg)
	end
	
	msg = "WITHOUT BOTH ESSENCES: "
	
	if #withoutBothEssences > 0 then
		for i=1,#withoutBothEssences do
			if i > 1 then
				msg = msg..", "..withoutBothEssences[i]
			else
				msg = msg..withoutBothEssences[i]
			end
		end
		
		PrintResultsToChat(msg)
	end
	
	msg = "OUT OF RANGE: "
	
	if #outOfRange > 0 then
		for i=1,#outOfRange do
			if i > 1 then
				msg = msg..", "..outOfRange[i]
			else
				msg = msg..outOfRange[i]
			end
		end
		
		PrintResultsToChat(msg)
	end
end

function CheckTankEssences(unit, name)
	local neededEssencesCount = 0

	local wardenFound = false
	local animaFound = false

	local unitGUID = UnitGUID(unit)

	for i=1,50 do
		local buffName, _, _, _, _, _, unitCaster, _, _, spellId = UnitAura(name, i, "HELPFUL")
		
		local casterGUID = UnitGUID(unitCaster)
		
		if not spellId then
			break
		else
			if spellId == 312107 and casterGUID == unitGUID then
				wardenFound = true
				neededEssencesCount = neededEssencesCount + 1
			elseif spellId == 294966 and casterGUID == unitGUID then
				animaFound = true
				neededEssencesCount = neededEssencesCount + 1
			end

			if neededEssencesCount >= 2 then break end
		end
	end
	
	return wardenFound, animaFound
end

function CheckTankCorruption(name)
	local corruptions = GetCharacterCorruptions(name)
	local summaryTD = 0
	local summaryEchoingVoid = 0

	if #corruptions > 0 then
		for i=1, #corruptions do
			local corruptionBonus = corruptions[i]

			if 	   string.find(corruptionBonus, "6539") then
				summaryTD = summaryTD + 18
			elseif string.find(corruptionBonus, "6538") then
				summaryTD = summaryTD + 12
			elseif string.find(corruptionBonus, "6537") then
				summaryTD = summaryTD + 6
			elseif string.find(corruptionBonus, "6549") then
				summaryEchoingVoid = summaryEchoingVoid + 0.4
			elseif string.find(corruptionBonus, "6550") then
				summaryEchoingVoid = summaryEchoingVoid + 0.6
			elseif string.find(corruptionBonus, "6551") then
				summaryEchoingVoid = summaryEchoingVoid + 1
			end
		end
	end
	
	PrintResultsToChat(name..' has '..summaryTD..'% devastation, '..summaryEchoingVoid..'% echoing void')
end

function GetItemSplit(itemLink)
	local itemString = string.match(itemLink, "item:([%-?%d:]+)")
	local itemSplit = {}

	-- Split data into a table
	for _, v in ipairs({strsplit(":", itemString)}) do
		if v == "" then
			itemSplit[#itemSplit + 1] = 0
		else
			itemSplit[#itemSplit + 1] = tonumber(v)
		end
	end

	return itemSplit
end

function GetCharacterCorruptions(name)
	local corruptions = {}

    for i=1,#itemsSlotTable do
        local itemLink = GetInventoryItemLink(name, itemsSlotTable[i])

        if itemLink then
            local itemSplit = GetItemSplit(itemLink)

            for index=1, itemSplit[13] do
                corruptions[#corruptions + 1] = itemSplit[13 + index]
            end
        end
    end

    return corruptions
end

-- Slash
SLASH_TANKSEVENTSHELPER1 = "/tanks"

local SlashHandlers = {
	["check"] = function()
		CheckTanks()
	end,
	["help"] = function()
		Print(" /tanks check     <<< checks Warden and Anima essences of the each tank in your group or raid")
	end,
}

SlashCmdList["TANKSEVENTSHELPER"] = function(text)
	local command, params = strsplit(" ", text, 2)

	if SlashHandlers[command] then
		SlashHandlers[command](params)
	end
end
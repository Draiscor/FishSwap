-- Namespace
local FishSwap = CreateFrame("Button", "FishSwapButton", UIParent)

-- Configuration
local BUTTON_SIZE = 32
local ICON_TEXTURE = "Interface\\Icons\\Trade_Fishing"
local DEBUG_MODE = false

-- Hidden Tooltip for scanning item stats
local scanTooltip = CreateFrame("GameTooltip", "FishSwapScanner", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

-- Initialize Saved Variables (Main Hand = 16, Off Hand = 17)
if not FishSwapSavedWeapons then
    FishSwapSavedWeapons = {
        mh = nil,
        oh = nil
    }
end

-- Helper: Parse Item Name from Link
local function GetItemNameFromLink(link)
    if not link then
        return nil
    end
    local name = string.gsub(link, "|c%x+|Hitem:%d+:%d+:%d+:%d+|h%[(.-)%]|h|r", "%1")
    return name
end

-- Helper: Find item location in bags (BagID, SlotID)
local function FindItemInBags(itemName)
    if not itemName then
        return nil, nil
    end
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots > 0 then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    if GetItemNameFromLink(link) == itemName then
                        return bag, slot
                    end
                end
            end
        end
    end
    return nil, nil
end

-- Helper: Count total free bag slots (Vanilla 1.12 compatible)
local function GetTotalFreeBagSlots()
    local free = 0
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots > 0 then
            for slot = 1, numSlots do
                local texture = GetContainerItemInfo(bag, slot)
                if not texture then
                    free = free + 1
                end
            end
        end
    end
    return free
end

-- Helper: Analyze an item to see if it is a Fishing Pole and what bonus it has
-- Returns: isPole (bool), bonus (number)
local function AnalyzeItem(bag, slot)
    scanTooltip:ClearLines()
    scanTooltip:SetBagItem(bag, slot)

    local isPole = false
    local bonus = 0

    -- Scan lines in the tooltip
    local numLines = scanTooltip:NumLines()
    if numLines > 10 then
        numLines = 10
    end

    for i = 1, numLines do
        local lineObj = _G["FishSwapScannerTextLeft" .. i]
        local lineObjRight = _G["FishSwapScannerTextRight" .. i]

        if lineObj then
            local text = lineObj:GetText()
            local textR = lineObjRight and lineObjRight:GetText() or ""

            if text then
                -- CHECK 1: Is it a fishing pole?
                if string.find(text, "Fishing Pole") or string.find(textR, "Fishing Pole") then
                    isPole = true
                end

                -- CHECK 2: Does it have a bonus?
                local _, _, foundBonus = string.find(text, "Fishing %+(%d+)")
                if foundBonus then
                    bonus = tonumber(foundBonus)
                end
            end
        end
    end

    return isPole, bonus
end

-- Helper: Is a fishing pole equipped?
local function IsFishingPoleEquipped()
    scanTooltip:ClearLines()
    scanTooltip:SetInventoryItem("player", 16)

    local numLines = scanTooltip:NumLines()
    if numLines > 10 then
        numLines = 10
    end

    for i = 1, numLines do
        local lineObj = _G["FishSwapScannerTextLeft" .. i]
        local lineObjRight = _G["FishSwapScannerTextRight" .. i]

        if lineObj then
            local text = lineObj:GetText()
            local textR = lineObjRight and lineObjRight:GetText() or ""

            if text and (string.find(text, "Fishing Pole") or string.find(textR, "Fishing Pole")) then
                return true
            end
        end
    end
    return false
end

-- Core Logic: Toggle Equipment
local function ToggleFishingGear()
    if IsFishingPoleEquipped() then
        -- === MODE: SWAP BACK TO WEAPONS ===

        local mhName = FishSwapSavedWeapons.mh
        local ohName = FishSwapSavedWeapons.oh

        if not mhName and not ohName then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffff0000FishSwap:|r No saved weapons found. Please equip your weapons manually once to initialize.")
            return
        end

        local proceedToOffHand = true

        -- 1. Equip Main Hand
        if mhName then
            local bag, slot = FindItemInBags(mhName)
            if bag and slot then
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00FishSwap:|r Equipping Main Hand...")
                PickupContainerItem(bag, slot)
                EquipCursorItem(16)
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error:|r Could not find Main Hand: " .. mhName)
                proceedToOffHand = false
            end
        end

        -- 2. Equip Off Hand
        if ohName then
            if proceedToOffHand then
                local bagOH, slotOH = FindItemInBags(ohName)
                if bagOH and slotOH then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00FishSwap:|r Equipping Off Hand...")
                    PickupContainerItem(bagOH, slotOH)
                    EquipCursorItem(17)
                elseif ohName then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error:|r Could not find Off Hand: " .. ohName)
                end
            else
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cffff0000FishSwap:|r Aborting Off-Hand equip because Main Hand is missing.")
            end
        end

    else
        -- === MODE: SWAP TO FISHING POLE ===

        local hasMH = GetInventoryItemLink("player", 16)
        local hasOH = GetInventoryItemLink("player", 17)
        local freeSlots = GetTotalFreeBagSlots()

        if hasMH and hasOH and freeSlots < 2 then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000FishSwap Error:|r Swap aborted.")
            DEFAULT_CHAT_FRAME:AddMessage("You have a MH and OH equipped, but only " .. freeSlots ..
                                              " bag slot(s) free.")
            return
        end

        -- Save current gear
        FishSwapSavedWeapons.mh = GetItemNameFromLink(hasMH)
        FishSwapSavedWeapons.oh = GetItemNameFromLink(hasOH)

        -- Find the BEST Fishing Pole
        local bestBag, bestSlot = nil, nil
        local bestBonus = -1

        if DEBUG_MODE then
            DEFAULT_CHAT_FRAME:AddMessage("FishSwap Debug: Scanning Bags...")
        end

        for bag = 0, 4 do
            local numSlots = GetContainerNumSlots(bag)
            if numSlots > 0 then
                for slot = 1, numSlots do
                    local link = GetContainerItemLink(bag, slot)
                    if link then
                        -- Analyze every item using SetBagItem
                        local isPole, bonus = AnalyzeItem(bag, slot)

                        if isPole then
                            if DEBUG_MODE then
                                local name = GetItemNameFromLink(link)
                                DEFAULT_CHAT_FRAME:AddMessage("Found Pole: " .. name .. " (+" .. bonus .. ")")
                            end

                            if bonus > bestBonus then
                                bestBonus = bonus
                                bestBag = bag
                                bestSlot = slot
                            end
                        end
                    end
                end
            end
        end

        if bestBag and bestSlot then
            local poleLink = GetContainerItemLink(bestBag, bestSlot)
            local poleName = GetItemNameFromLink(poleLink)
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00FishSwap:|r Equipping " .. poleName .. " (Bonus: +" .. bestBonus ..
                                              ")...")

            PickupContainerItem(bestBag, bestSlot)
            EquipCursorItem(16)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000FishSwap:|r No Fishing Pole found in bags!")
            if not DEBUG_MODE then
                DEFAULT_CHAT_FRAME:AddMessage(
                    "If you have a pole, edit the LUA file and set DEBUG_MODE = true to see why it's skipped.")
            end
        end
    end
end

-- Helper: Reset Position Only
local function ResetPosition()
    FishSwap:ClearAllPoints()
    FishSwap:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00FishSwap:|r Button position reset.")
end

-- Helper: Full Reset (Right Click)
local function FullReset()
    ResetPosition()
    FishSwapSavedWeapons.mh = nil
    FishSwapSavedWeapons.oh = nil
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00FishSwap:|r Saved weapon data cleared.")
end

-- UI Construction
FishSwap:SetWidth(BUTTON_SIZE)
FishSwap:SetHeight(BUTTON_SIZE)
FishSwap:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
FishSwap:EnableMouse(true)
FishSwap:SetMovable(true)
FishSwap:RegisterForDrag("LeftButton")
FishSwap:RegisterForClicks("LeftButtonUp", "RightButtonUp")

local tex = FishSwap:CreateTexture(nil, "BACKGROUND")
tex:SetAllPoints()
tex:SetTexture(ICON_TEXTURE)
FishSwap.texture = tex

-- Drag Scripts
FishSwap:SetScript("OnDragStart", function()
    if IsShiftKeyDown() and arg1 == "LeftButton" then
        this:StartMoving()
    end
end)
FishSwap:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
end)

-- Click Script
FishSwap:SetScript("OnMouseUp", function()
    if arg1 == "LeftButton" then
        ToggleFishingGear()
    elseif arg1 == "RightButton" then
        FullReset()
    end
end)

-- Tooltip
FishSwap:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("FishSwap")
    GameTooltip:AddLine("Left Click: Toggle best Fishing Pole.", 1, 1, 1)
    GameTooltip:AddLine("Right Click: Reset Position & Clear Data.", 1, 0.5, 0.5)

    if FishSwapSavedWeapons.mh then
        GameTooltip:AddLine("Saved MH: " .. FishSwapSavedWeapons.mh, 0, 1, 0)
    end
    if FishSwapSavedWeapons.oh then
        GameTooltip:AddLine("Saved OH: " .. FishSwapSavedWeapons.oh, 0, 1, 0)
    end
    GameTooltip:AddLine("Shift+Left Drag to move.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
FishSwap:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Slash Command Handler
SLASH_FISHSWAP1 = "/fishswap"
SlashCmdList["FISHSWAP"] = function(msg)
    if msg == "reset" then
        ResetPosition()
    else
        DEFAULT_CHAT_FRAME:AddMessage("FishSwap: Type |cff00ffff/fishswap reset|r to reset button position.")
    end
end

DEFAULT_CHAT_FRAME:AddMessage("FishSwap Loaded. Shift+Drag to move. Type /fishswap reset to rescue button.")

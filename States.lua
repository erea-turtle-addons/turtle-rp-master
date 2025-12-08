-- States.lua - States module for RPMaster (placeholder)
-- Future: Manage and distribute RP states/buffs to players

local statesContent = nil

-- Function: Create states content frame
function RPMStates_CreateContent(parent)
    statesContent = CreateFrame("Frame", "RPMStatesContent", parent)
    statesContent:SetAllPoints()

    -- Placeholder text
    local title = statesContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("CENTER", 0, 20)
    title:SetText("States Module")

    local description = statesContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    description:SetPoint("CENTER", 0, -10)
    description:SetText("Coming Soon")
    description:SetTextColor(0.7, 0.7, 0.7)

    local info = statesContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    info:SetPoint("CENTER", 0, -40)
    info:SetText("This module will allow GMs to create\nand distribute RP states/buffs/effects")
    info:SetTextColor(0.5, 0.5, 0.5)

    return statesContent
end

-- Function: Show callback
function RPMStates_Show()
    -- Nothing to do yet
end

-- Function: Hide callback
function RPMStates_Hide()
    -- Nothing to do yet
end

-- Register module with Core
RPM_RegisterModule("states", {
    createContent = RPMStates_CreateContent,
    onShow = RPMStates_Show,
    onHide = RPMStates_Hide
})

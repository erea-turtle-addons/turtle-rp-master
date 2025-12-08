-- Monitor.lua - Monitor module for RPMaster (placeholder)
-- Future: Monitor player inventories and states

local monitorContent = nil

-- Function: Create monitor content frame
function RPMMonitor_CreateContent(parent)
    monitorContent = CreateFrame("Frame", "RPMMonitorContent", parent)
    monitorContent:SetAllPoints()

    -- Placeholder text
    local title = monitorContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("CENTER", 0, 20)
    title:SetText("Monitor Module")

    local description = monitorContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    description:SetPoint("CENTER", 0, -10)
    description:SetText("Coming Soon")
    description:SetTextColor(0.7, 0.7, 0.7)

    local info = monitorContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    info:SetPoint("CENTER", 0, -40)
    info:SetText("This module will allow GMs to monitor\nplayer inventories and active states")
    info:SetTextColor(0.5, 0.5, 0.5)

    return monitorContent
end

-- Function: Show callback
function RPMMonitor_Show()
    -- Nothing to do yet
end

-- Function: Hide callback
function RPMMonitor_Hide()
    -- Nothing to do yet
end

-- Register module with Core
RPM_RegisterModule("monitor", {
    createContent = RPMMonitor_CreateContent,
    onShow = RPMMonitor_Show,
    onHide = RPMMonitor_Hide
})

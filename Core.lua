-- Core.lua - Main frame, tabs, and module registry for RPMaster
-- Modular architecture for RP Master addon

local ADDON_NAME = "RPMaster"
local ADDON_VERSION = "2025-12-07 21:40"
local ADDON_PREFIX = "RPMSTR"

-- Debug logging system
RPMasterDebugLog = RPMasterDebugLog or {}

local function Log(message)
    local timestamp = date("%H:%M:%S")
    local logEntry = string.format("[%s] RPMaster: %s", timestamp, tostring(message))
    table.insert(RPMasterDebugLog, logEntry)
    -- Keep only last 500 entries to prevent bloat
    if table.getn(RPMasterDebugLog) > 500 then
        table.remove(RPMasterDebugLog, 1)
    end
end

Log("Core.lua loading...")

-- RPMasterDB will be initialized in PLAYER_LOGIN event
-- (saved variables aren't available until after VARIABLES_LOADED)

-- Module registry
RPM_Modules = {}
RPM_CurrentTab = nil
RPM_DetachedFrames = {}

-- Main frame
RPMasterFrame = CreateFrame("Frame", "RPMasterFrame", UIParent)
RPMasterFrame:SetWidth(700)
RPMasterFrame:SetHeight(500)
RPMasterFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
RPMasterFrame:SetBackdrop({
    bgFile = "Interface\\AddOns\\RPMaster\\black",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
RPMasterFrame:SetBackdropColor(0, 0, 0, 1)
RPMasterFrame:SetMovable(true)
RPMasterFrame:Hide()

-- Position will be loaded in PLAYER_LOGIN event

-- Title
local title = RPMasterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -20)
title:SetText("RP Master - Game Master")

-- Draggable title bar
local titleBar = CreateFrame("Frame", nil, RPMasterFrame)
titleBar:SetPoint("TOPLEFT", 10, -10)
titleBar:SetPoint("TOPRIGHT", -30, -10)
titleBar:SetHeight(30)
titleBar:EnableMouse(true)
titleBar:RegisterForDrag("LeftButton")
titleBar:SetScript("OnDragStart", function()
    RPMasterFrame:StartMoving()
end)
titleBar:SetScript("OnDragStop", function()
    RPMasterFrame:StopMovingOrSizing()
    RPM_SaveWindowPosition("main", RPMasterFrame)
end)

-- Close button
local closeBtn = CreateFrame("Button", nil, RPMasterFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -5, -5)

-- Tab bar container
local tabBar = CreateFrame("Frame", "RPMTabBar", RPMasterFrame)
tabBar:SetPoint("TOPLEFT", 15, -50)
tabBar:SetPoint("TOPRIGHT", -15, -50)
tabBar:SetHeight(30)

-- Content container (where active tab content shows)
local contentFrame = CreateFrame("Frame", "RPMContentFrame", RPMasterFrame)
contentFrame:SetPoint("TOPLEFT", 15, -85)
contentFrame:SetPoint("BOTTOMRIGHT", -15, 15)

-- Tab buttons
RPM_TabButtons = {}

-- Function: Register a module
function RPM_RegisterModule(name, callbacks)
    RPM_Modules[name] = {
        name = name,
        createContent = callbacks.createContent,
        onShow = callbacks.onShow,
        onHide = callbacks.onHide,
        content = nil,
        tabButton = nil,
        detachButton = nil
    }
end

-- Function: Create tab button
local function CreateTabButton(moduleName, index)
    local tabWidth = 120
    local tabHeight = 28
    local spacing = 5

    local tab = CreateFrame("Button", "RPMTab_"..moduleName, tabBar)
    tab:SetWidth(tabWidth)
    tab:SetHeight(tabHeight)
    tab:SetPoint("LEFT", (tabWidth + spacing) * (index - 1), 0)

    tab:SetBackdrop({
        bgFile = "Interface\\AddOns\\RPMaster\\black",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    tab:SetBackdropColor(0.1, 0.1, 0.1, 1)

    -- Tab label
    local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 8, 0)
    -- Lua 5.0 doesn't support string:method() syntax, use string.method() instead
    local displayName = string.upper(string.sub(moduleName, 1, 1)) .. string.sub(moduleName, 2)
    label:SetText(displayName)

    -- Detach button (small button on right side of tab)
    local detachBtn = CreateFrame("Button", nil, tab)
    detachBtn:SetWidth(16)
    detachBtn:SetHeight(16)
    detachBtn:SetPoint("RIGHT", -4, 0)

    local detachText = detachBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detachText:SetText("^")
    detachText:SetTextColor(0.7, 0.7, 0.7)

    detachBtn:SetScript("OnClick", function()
        RPM_DetachTab(moduleName)
    end)

    detachBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText("Detach to separate window")
        GameTooltip:Show()
    end)

    detachBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Tab click handler
    tab:SetScript("OnClick", function()
        RPM_SwitchTab(moduleName)
    end)

    RPM_Modules[moduleName].tabButton = tab
    RPM_Modules[moduleName].detachButton = detachBtn
    RPM_TabButtons[moduleName] = tab

    return tab
end

-- Function: Switch to a tab
function RPM_SwitchTab(tabName)
    if not RPMasterDB then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r RPMasterDB not initialized yet", 1, 0, 0)
        return
    end

    if not RPM_Modules[tabName] then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Unknown tab: "..tabName, 1, 0, 0)
        return
    end

    -- Don't switch if tab is detached
    if RPMasterDB.preferences.detachedTabs[tabName] then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[RPMaster]|r "..tabName.." is detached", 1, 1, 0)
        return
    end

    -- Hide current content
    if RPM_CurrentTab then
        local currentModule = RPM_Modules[RPM_CurrentTab]
        if currentModule.content then
            currentModule.content:Hide()
        end
        if currentModule.onHide then
            currentModule.onHide()
        end
        -- Unhighlight tab
        if currentModule.tabButton then
            currentModule.tabButton:SetBackdropColor(0.1, 0.1, 0.1, 1)
        end
    end

    -- Show new content
    local module = RPM_Modules[tabName]
    if not module.content then
        -- Create content on first access
        module.content = module.createContent(contentFrame)
    end

    module.content:SetParent(contentFrame)
    module.content:SetAllPoints(contentFrame)
    module.content:Show()

    if module.onShow then
        module.onShow()
    end

    -- Highlight active tab
    if module.tabButton then
        module.tabButton:SetBackdropColor(0.2, 0.2, 0.2, 1)
    end

    RPM_CurrentTab = tabName
    RPMasterDB.preferences.activeTab = tabName
end

-- Function: Detach a tab to separate window
function RPM_DetachTab(tabName)
    if RPMasterDB.preferences.detachedTabs[tabName] then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[RPMaster]|r "..tabName.." is already detached", 1, 1, 0)
        return
    end

    local module = RPM_Modules[tabName]
    if not module then return end

    -- Create content if not exists
    if not module.content then
        module.content = module.createContent(contentFrame)
    end

    -- Create detached window
    local frameName = "RPM" .. string.upper(string.sub(tabName, 1, 1)) .. string.sub(tabName, 2) .. "Detached"
    local detachedFrame = CreateFrame("Frame", frameName, UIParent)
    detachedFrame:SetWidth(700)
    detachedFrame:SetHeight(500)
    detachedFrame:SetPoint("CENTER", UIParent, "CENTER", 50, 50)
    detachedFrame:SetBackdrop({
        bgFile = "Interface\\AddOns\\RPMaster\\black",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    detachedFrame:SetBackdropColor(0, 0, 0, 1)
    detachedFrame:SetMovable(true)
    detachedFrame:SetFrameStrata("MEDIUM")

    -- Load saved position
    if RPMasterDB.preferences.windowPositions[tabName] then
        local pos = RPMasterDB.preferences.windowPositions[tabName]
        detachedFrame:ClearAllPoints()
        detachedFrame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end

    -- Title
    local detachedTitle = detachedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detachedTitle:SetPoint("TOP", 0, -20)
    local titleText = string.upper(string.sub(tabName, 1, 1)) .. string.sub(tabName, 2)
    detachedTitle:SetText(titleText)

    -- Draggable title bar
    local detachedTitleBar = CreateFrame("Frame", nil, detachedFrame)
    detachedTitleBar:SetPoint("TOPLEFT", 10, -10)
    detachedTitleBar:SetPoint("TOPRIGHT", -60, -10)
    detachedTitleBar:SetHeight(30)
    detachedTitleBar:EnableMouse(true)
    detachedTitleBar:RegisterForDrag("LeftButton")
    detachedTitleBar:SetScript("OnDragStart", function()
        detachedFrame:StartMoving()
    end)
    detachedTitleBar:SetScript("OnDragStop", function()
        detachedFrame:StopMovingOrSizing()
        RPM_SaveWindowPosition(tabName, detachedFrame)
    end)

    -- Reattach button
    local reattachBtn = CreateFrame("Button", nil, detachedFrame, "UIPanelButtonTemplate")
    reattachBtn:SetWidth(20)
    reattachBtn:SetHeight(20)
    reattachBtn:SetPoint("TOPRIGHT", -30, -13)
    reattachBtn:SetText("v")
    reattachBtn:SetScript("OnClick", function()
        RPM_ReattachTab(tabName)
    end)
    reattachBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Reattach to main window")
        GameTooltip:Show()
    end)
    reattachBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Close button
    local detachedCloseBtn = CreateFrame("Button", nil, detachedFrame, "UIPanelCloseButton")
    detachedCloseBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Content container
    local detachedContent = CreateFrame("Frame", nil, detachedFrame)
    detachedContent:SetPoint("TOPLEFT", 15, -50)
    detachedContent:SetPoint("BOTTOMRIGHT", -15, 15)

    -- Move content to detached window
    module.content:SetParent(detachedContent)
    module.content:SetAllPoints(detachedContent)
    module.content:Show()

    if module.onShow then
        module.onShow()
    end

    -- Hide tab button in main window
    if module.tabButton then
        module.tabButton:Hide()
    end

    -- Save state
    RPMasterDB.preferences.detachedTabs[tabName] = true
    RPM_DetachedFrames[tabName] = detachedFrame

    -- Switch to next available tab in main window
    if RPM_CurrentTab == tabName then
        local nextTab = nil
        for name, mod in pairs(RPM_Modules) do
            if not RPMasterDB.preferences.detachedTabs[name] then
                nextTab = name
                break
            end
        end
        if nextTab then
            RPM_SwitchTab(nextTab)
        else
            RPM_CurrentTab = nil
        end
    end

    detachedFrame:Show()
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r "..tabName.." detached", 0, 1, 0)
end

-- Function: Reattach a tab to main window
function RPM_ReattachTab(tabName)
    if not RPMasterDB.preferences.detachedTabs[tabName] then
        return
    end

    local module = RPM_Modules[tabName]
    local detachedFrame = RPM_DetachedFrames[tabName]

    if not module or not detachedFrame then return end

    -- Move content back to main window
    module.content:SetParent(contentFrame)
    module.content:SetAllPoints(contentFrame)
    module.content:Hide()

    if module.onHide then
        module.onHide()
    end

    -- Show tab button
    if module.tabButton then
        module.tabButton:Show()
    end

    -- Destroy detached window
    detachedFrame:Hide()
    RPM_DetachedFrames[tabName] = nil

    -- Save state
    RPMasterDB.preferences.detachedTabs[tabName] = false

    -- Switch to reattached tab
    RPM_SwitchTab(tabName)

    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r "..tabName.." reattached", 0, 1, 0)
end

-- Function: Save window position
function RPM_SaveWindowPosition(windowName, frame)
    if not RPMasterDB or not RPMasterDB.preferences then
        return
    end
    local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint()
    RPMasterDB.preferences.windowPositions[windowName] = {point, relativePoint, xOfs, yOfs}
end

-- Function: Initialize modules and tabs
function RPM_InitializeModules()
    Log("RPM_InitializeModules called")

    -- Safety check
    if not RPMasterDB or not RPMasterDB.preferences then
        Log("ERROR: RPMasterDB or preferences is nil in InitializeModules!")
        return
    end

    -- Module order for tabs
    local moduleOrder = {"items", "states", "monitor"}

    -- Create tab buttons
    for index, moduleName in ipairs(moduleOrder) do
        if RPM_Modules[moduleName] then
            Log("Creating tab button for: " .. moduleName)
            CreateTabButton(moduleName, index)
        else
            Log("Module not found: " .. moduleName)
        end
    end

    -- Restore detached windows
    Log("Restoring detached windows")
    for tabName, isDetached in pairs(RPMasterDB.preferences.detachedTabs) do
        if isDetached and RPM_Modules[tabName] then
            Log("Detaching tab: " .. tabName)
            RPM_DetachTab(tabName)
        end
    end

    -- Switch to last active tab or first available
    local startTab = RPMasterDB.preferences.activeTab or "items"
    Log("Starting tab: " .. startTab)
    if RPMasterDB.preferences.detachedTabs[startTab] then
        -- Find first non-detached tab
        for name, mod in pairs(RPM_Modules) do
            if not RPMasterDB.preferences.detachedTabs[name] then
                startTab = name
                Log("Found non-detached tab: " .. name)
                break
            end
        end
    end

    if RPM_Modules[startTab] and not RPMasterDB.preferences.detachedTabs[startTab] then
        Log("Switching to tab: " .. startTab)
        RPM_SwitchTab(startTab)
    else
        Log("Cannot switch to tab: " .. startTab)
    end
end

-- Function: Open main interface
function RPM_OpenMainFrame()
    Log("RPM_OpenMainFrame called")

    -- If modules haven't been initialized yet, do it now
    if not RPM_CurrentTab then
        Log("Modules not initialized, initializing now")

        -- Initialize RPMasterDB if needed
        if not RPMasterDB then
            Log("RPMasterDB is nil, creating default structure")
            RPMasterDB = {
                itemLibrary = {},
                nextItemID = 1,
                preferences = {
                    detachedTabs = {items = false, states = false, monitor = false},
                    windowPositions = {main = nil, items = nil, states = nil, monitor = nil},
                    activeTab = "items"
                }
            }
        else
            Log("RPMasterDB exists, type: " .. type(RPMasterDB))
        end

        -- Ensure preferences structure exists (backward compatibility)
        if not RPMasterDB.preferences then
            Log("preferences is nil, creating default preferences")
            RPMasterDB.preferences = {
                detachedTabs = {items = false, states = false, monitor = false},
                windowPositions = {main = nil, items = nil, states = nil, monitor = nil},
                activeTab = "items"
            }
        else
            Log("preferences exists")
        end

        RPM_InitializeModules()
    end

    RPMasterFrame:Show()
    -- Refresh active tab if exists
    if RPM_CurrentTab and RPM_Modules[RPM_CurrentTab] and RPM_Modules[RPM_CurrentTab].onShow then
        RPM_Modules[RPM_CurrentTab].onShow()
    end
end

-- Function: Toggle main interface
function RPM_ToggleMainFrame()
    if RPMasterFrame:IsShown() then
        RPMasterFrame:Hide()
    else
        RPM_OpenMainFrame()
    end
end

-- Slash commands
SLASH_RPMASTER1 = "/rpmaster"
SLASH_RPMASTER2 = "/rpm"
SlashCmdList["RPMASTER"] = function(msg)
    -- Handle log command
    if msg == "log" then
        RPM_ShowLog()
        return
    end

    -- Handle clearlog command
    if msg == "clearlog" then
        RPMasterDebugLog = {}
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r Debug log cleared")
        return
    end

    RPM_ToggleMainFrame()
end

-- Event frame for initialization
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("PLAYER_LOGIN")
loadFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        Log("PLAYER_LOGIN event fired")

        -- Initialize RPMasterDB now that saved variables are loaded
        -- (PLAYER_LOGIN fires after VARIABLES_LOADED)
        RPMasterDB = RPMasterDB or {
            itemLibrary = {},
            nextItemID = 1,
            preferences = {
                detachedTabs = {items = false, states = false, monitor = false},
                windowPositions = {main = nil, items = nil, states = nil, monitor = nil},
                activeTab = "items"
            }
        }
        Log("RPMasterDB initialized")

        -- Ensure preferences structure exists (backward compatibility)
        if not RPMasterDB.preferences then
            Log("preferences is nil, creating default")
            RPMasterDB.preferences = {
                detachedTabs = {items = false, states = false, monitor = false},
                windowPositions = {main = nil, items = nil, states = nil, monitor = nil},
                activeTab = "items"
            }
        else
            Log("preferences exists")
        end

        -- Load saved main frame position
        if RPMasterDB.preferences.windowPositions.main then
            local pos = RPMasterDB.preferences.windowPositions.main
            RPMasterFrame:ClearAllPoints()
            RPMasterFrame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        end

        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700[RPMaster] Version: " .. ADDON_VERSION .. "|r")
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[RPMaster]|r Commands: /rpm, /rpm log", 0, 1, 1)

        -- Initialize modules after a short delay to ensure all files loaded
        loadFrame.timer = 0
        loadFrame:SetScript("OnUpdate", function(self, elapsed)
            self.timer = self.timer + elapsed
            if self.timer >= 0.5 then
                RPM_InitializeModules()
                self:SetScript("OnUpdate", nil)
            end
        end)

        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- Debug log viewer frame
local logFrame = CreateFrame("Frame", "RPMasterLogFrame", UIParent)
logFrame:SetWidth(600)
logFrame:SetHeight(400)
logFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
logFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
logFrame:SetBackdropColor(0, 0, 0, 1)
logFrame:SetMovable(true)
logFrame:EnableMouse(true)
logFrame:SetFrameStrata("DIALOG")
logFrame:Hide()

local logTitle = logFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
logTitle:SetPoint("TOP", 0, -15)
logTitle:SetText("RPMaster Debug Log")

-- Draggable
local logTitleBar = CreateFrame("Frame", nil, logFrame)
logTitleBar:SetPoint("TOPLEFT", 10, -10)
logTitleBar:SetPoint("TOPRIGHT", -30, -10)
logTitleBar:SetHeight(30)
logTitleBar:EnableMouse(true)
logTitleBar:RegisterForDrag("LeftButton")
logTitleBar:SetScript("OnDragStart", function() logFrame:StartMoving() end)
logTitleBar:SetScript("OnDragStop", function() logFrame:StopMovingOrSizing() end)

local logCloseBtn = CreateFrame("Button", nil, logFrame, "UIPanelCloseButton")
logCloseBtn:SetPoint("TOPRIGHT", -5, -5)

-- Scrollable log area with EditBox for copy/paste
local logScrollFrame = CreateFrame("ScrollFrame", "RPMasterLogScrollFrame", logFrame, "UIPanelScrollFrameTemplate")
logScrollFrame:SetPoint("TOPLEFT", 20, -50)
logScrollFrame:SetPoint("BOTTOMRIGHT", -40, 50)

local logEditBox = CreateFrame("EditBox", nil, logScrollFrame)
logEditBox:SetWidth(520)
logEditBox:SetHeight(1)
logEditBox:SetMultiLine(true)
logEditBox:SetAutoFocus(false)
logEditBox:SetFontObject(GameFontNormalSmall)
logEditBox:SetTextColor(1, 1, 1, 1)
logEditBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)

logScrollFrame:SetScrollChild(logEditBox)

-- Clear button
local clearBtn = CreateFrame("Button", nil, logFrame, "UIPanelButtonTemplate")
clearBtn:SetWidth(80)
clearBtn:SetHeight(22)
clearBtn:SetPoint("BOTTOM", logFrame, "BOTTOM", 0, 15)
clearBtn:SetText("Clear Log")
clearBtn:SetScript("OnClick", function()
    RPMasterDebugLog = {}
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r Debug log cleared")
    logFrame:Hide()
end)

-- Function to show log viewer
function RPM_ShowLog()
    if table.getn(RPMasterDebugLog) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[RPMaster]|r Debug log is empty")
        return
    end

    local logContent = table.concat(RPMasterDebugLog, "\n")
    logEditBox:SetText(logContent)
    logEditBox:HighlightText()

    -- Calculate height needed for all text
    local numLines = table.getn(RPMasterDebugLog)
    local lineHeight = 14 -- approximate height per line
    local totalHeight = numLines * lineHeight + 20
    logEditBox:SetHeight(totalHeight)

    logFrame:Show()
    logEditBox:SetFocus()
end

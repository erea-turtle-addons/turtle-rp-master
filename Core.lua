-- ============================================================================
-- Core.lua - Main frame, tabs, and module registry for RPMaster
-- ============================================================================
-- PURPOSE: Provides the main UI framework, tab system, and module registration
--          for the RP Master addon. Acts as the "shell" that hosts feature modules.
--
-- ARCHITECTURE: Modular plugin system
--   - Core.lua creates the main window and tab bar
--   - Feature modules (ItemLibrary.lua, States.lua, etc.) register themselves
--   - Each module provides callbacks: createContent(), onShow(), onHide()
--   - Tabs can be detached into separate windows
--
-- LUA VERSION: Lua 5.0 (WoW 1.12 environment)
--   - No table.insert shorthand, use explicit syntax
--   - Use table.getn(t) instead of #t for table length
--   - Use string.gfind instead of string.gmatch
--   - math.mod instead of % for modulo (though % works in expressions)
--
-- WOW API NOTES:
--   - All UI elements are "Frames" (similar to DOM nodes or Swing components)
--   - CreateFrame() is like document.createElement() or new JPanel()
--   - Frames are global by default if given a string name
--   - Event system is observer pattern: RegisterEvent() + OnEvent callback
--   - No anonymous functions, use function() end syntax
-- ============================================================================

-- Import business logic libraries
local objectDatabase = RequireObjectDatabase()
local rpBusiness = RequireRPBusiness()
local messaging = RequireMessaging()
local encoding = RequireEncoding()

-- ============================================================================
-- CONSTANTS (local = file-scoped, like private static final in Java)
-- ============================================================================
local ADDON_NAME = "RPMaster"
-- Version info loaded from version.lua (loaded first in .toc)
-- Show version tag unless it's the default "0.0.0", then show build time
local ADDON_VERSION = (RP_VERSION_TAG and RP_VERSION_TAG ~= "0.0.0") and RP_VERSION_TAG or (RP_BUILD_TIME or "unknown")
local ADDON_PREFIX = messaging.ADDON_PREFIX  -- Use constant from messaging module

-- ============================================================================
-- STARTUP MESSAGE
-- ============================================================================
-- Immediate load message (fires when Core.lua is parsed by the Lua interpreter)
-- DEFAULT_CHAT_FRAME is a global WoW variable for the main chat window
-- Color codes: |cAARRGGBB text |r (AA=alpha, RGB=color, |r resets)
-- ============================================================================
DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700[RP Master] Version: " .. ADDON_VERSION)
DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[RP Master] Commands: /rpm, /rpm log")

-- ============================================================================
-- DEBUG LOGGING SYSTEM
-- ============================================================================
-- GLOBAL saved variable (persisted to disk between sessions)
-- Pattern: RPMasterDebugLog = RPMasterDebugLog or {}
--   - If RPMasterDebugLog exists (loaded from SavedVariables), keep it
--   - Otherwise initialize as empty table
-- This is like: RPMasterDebugLog ??= new List<string>() in C#
-- ============================================================================
RPMasterDebugLog = RPMasterDebugLog or {}

-- ============================================================================
-- Log() - Internal logging function
-- ============================================================================
-- @param message: String to log (will be converted to string if not already)
-- @returns: void
-- BEHAVIOR:
--   - Prepends timestamp to message
--   - Appends to RPMasterDebugLog array
--   - Keeps only last 500 entries (circular buffer pattern)
-- USAGE: Log("Player clicked button")
-- ============================================================================
local function Log(message)
    local timestamp = date("%H:%M:%S")  -- WoW global function, returns formatted time
    local logEntry = string.format("[%s] RPMaster: %s", timestamp, tostring(message))
    table.insert(RPMasterDebugLog, logEntry)  -- Appends to end (Lua arrays are 1-indexed)

    -- Circular buffer: Keep only last 500 entries to prevent SavedVariables file bloat
    -- (Lua 5.0 uses table.getn() instead of # operator for array length)
    if table.getn(RPMasterDebugLog) > 500 then
        table.remove(RPMasterDebugLog, 1)  -- Remove first element (index 1, not 0!)
    end
end

-- Base64 encoding/decoding moved to turtle-rp-common/rp-business.lua
-- Use rpBusiness.Base64Encode() and rpBusiness.Base64Decode()

Log("Core.lua loading...")

-- ============================================================================
-- EVENT HANDLER: CHAT_MSG_ADDON (Receiving addon messages from players)
-- ============================================================================
-- PURPOSE: Listen for player responses to GIVE requests (GIVE_ACCEPT/GIVE_REJECT)
--          and database sync messages (DB_SYNC)
--
-- WOW EVENT SYSTEM:
--   - Similar to addEventListener() in JavaScript or EventHandler in C#
--   - CreateFrame() creates an invisible frame to act as event listener
--   - RegisterEvent() subscribes to specific events
--   - SetScript("OnEvent", callback) sets the handler function
--
-- GLOBAL VARIABLES IN EVENT CALLBACKS (Lua 5.0 pattern):
--   - event: The event name (string)
--   - arg1, arg2, arg3, etc.: Event-specific parameters
--   - For CHAT_MSG_ADDON: arg1=prefix, arg2=message, arg3=distribution, arg4=sender
--
-- NOTE: In modern Lua/WoW versions, these would be function parameters
-- ============================================================================
local gmEventFrame = CreateFrame("Frame")  -- Invisible frame acts as event listener
gmEventFrame:RegisterEvent("CHAT_MSG_ADDON")  -- Subscribe to addon message events
gmEventFrame:SetScript("OnEvent", function()  -- Anonymous callback (can't access params in Lua 5.0)
    if event == "CHAT_MSG_ADDON" then
        -- Extract event parameters (Lua 5.0 uses global arg1, arg2, etc. instead of function params)
        local prefix, encodedMessage, distribution, sender = arg1, arg2, arg3, arg4

        -- Filter: Only process messages with our addon prefix
        if prefix ~= ADDON_PREFIX then
            return  -- Ignore messages from other addons
        end

        Log("CHAT_MSG_ADDON received from " .. tostring(sender))

        -- Parse message using messaging module
        -- Automatically handles Base64 decoding and caret-delimited parsing
        local messageType, parts = messaging.ParseMessage(encodedMessage)

        -- Get current player's name (like "this" in Java)
        local myName = UnitName("player")  -- WoW API: UnitName("player") returns your character name

        -- Handle different message types (pattern similar to switch/case)
        if messageType == messaging.MESSAGE_TYPES.GIVE_ACCEPT then
            -- Format: GIVE_ACCEPT^gmName^playerName^itemName
            -- Player accepted the item we gave them
            local targetGM = parts[2]     -- Who the response is for
            local playerName = parts[3]   -- Who accepted
            local itemName = parts[4]     -- What they accepted

            if targetGM == myName then  -- Only show message if it's for us
                Log("GIVE_ACCEPT received: " .. playerName .. " accepted " .. itemName)
                -- Green message in chat
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF00FF00[RP Master]|r %s accepted item: '%s'", playerName, itemName), 0, 1, 0)
            end

        elseif messageType == messaging.MESSAGE_TYPES.GIVE_REJECT then
            -- Format: GIVE_REJECT^gmName^playerName^itemName
            -- Player declined the item we gave them
            local targetGM = parts[2]
            local playerName = parts[3]
            local itemName = parts[4]

            if targetGM == myName then  -- Only show message if it's for us
                Log("GIVE_REJECT received: " .. playerName .. " declined " .. itemName)
                -- Red/orange message in chat
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFFFF0000[RP Master]|r %s declined item: '%s'", playerName, itemName), 1, 0.5, 0)
            end

        elseif messageType == messaging.MESSAGE_TYPES.RAID_WARNING then
            -- Format: RAID_WARNING^playerName^message
            -- Player action requested a raid warning to be sent
            local playerName = parts[2]
            local warningMessage = parts[3]

            Log("RAID_WARNING request from " .. playerName .. ": " .. warningMessage)

            -- Send raid warning (WoW 1.12: requires raid leader)
            -- Note: WoW 1.12 doesn't have UnitIsRaidOfficer
            if GetNumRaidMembers() > 0 and IsRaidLeader() then
                SendChatMessage(warningMessage, "RAID_WARNING")
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFFFFD700[RP Master]|r Raid warning sent: '%s' (from %s)", warningMessage, playerName), 1, 1, 0)
            else
                -- Try to send anyway - if not allowed, game will block it
                SendChatMessage(warningMessage, "RAID_WARNING")
                if not IsRaidLeader() then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFFFFAA00[RP Master]|r Attempted raid warning (may require raid leader): '%s' (from %s)", warningMessage, playerName), 1, 1, 0)
                else
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFFFFD700[RP Master]|r Raid warning sent: '%s' (from %s)", warningMessage, playerName), 1, 1, 0)
                end
            end

        -- ============================================================================
        -- DATABASE SYNC MESSAGE HANDLING
        -- ============================================================================
        -- Handle DB_SYNC messages from players (sent by RPPlayer addon)
        -- Format: "DB_SYNC^databaseId^databaseName^version^checksum^itemCount^item1Id^item1Guid^item1Name^item1Icon^item1Tooltip^item1Content^..."
        -- This is a simplified version of the message structure - actual implementation will need to handle
        -- sending/receiving multiple parts for large databases (like GIVE messages)
        elseif messageType == messaging.MESSAGE_TYPES.DB_SYNC_START then
            Log("DB_SYNC message received from player: " .. sender)
            -- In a full implementation, we would process the database sync here
            -- For now, we'll just log that we received it
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF00FFFF[RP Master]|r Received DB_SYNC request from %s", sender), 0, 1, 1)

        elseif messageType == messaging.MESSAGE_TYPES.STATUS_RESPONSE then
            -- Format: STATUS_RESPONSE^requestId^playerVersion^syncStateEncoded^inventoryEncoded
            local requestId = parts[2]
            local playerVersion = parts[3]
            local syncStateEncoded = parts[4]
            local inventoryEncoded = parts[5]

            Log("STATUS_RESPONSE received from " .. sender .. " (reqId: " .. tostring(requestId) .. ")")

            -- Decode sync state (Base64)
            local syncStateStr = encoding.Base64Decode(syncStateEncoded or "")
            local syncParts = {}
            if syncStateStr and syncStateStr ~= "" then
                -- Parse caret-delimited sync state
                local lastPos = 1
                local msgLen = string.len(syncStateStr)
                while lastPos <= msgLen do
                    local caretPos = string.find(syncStateStr, "^", lastPos, true)
                    if caretPos then
                        local field = string.sub(syncStateStr, lastPos, caretPos - 1)
                        table.insert(syncParts, field)
                        lastPos = caretPos + 1
                        if caretPos == msgLen then
                            table.insert(syncParts, "")
                            break
                        end
                    else
                        local field = string.sub(syncStateStr, lastPos)
                        table.insert(syncParts, field)
                        break
                    end
                end
            end

            local syncState = nil
            if table.getn(syncParts) >= 5 then
                syncState = {
                    databaseId = syncParts[1],
                    databaseName = syncParts[2],
                    version = tonumber(syncParts[3]) or 0,
                    checksum = syncParts[4],
                    lastSyncTime = tonumber(syncParts[5]) or 0
                }
            end

            -- Decode inventory (Base64)
            local inventoryStr = encoding.Base64Decode(inventoryEncoded or "")
            local inventoryParts = {}
            if inventoryStr and inventoryStr ~= "" then
                -- Parse caret-delimited inventory
                local lastPos = 1
                local msgLen = string.len(inventoryStr)
                while lastPos <= msgLen do
                    local caretPos = string.find(inventoryStr, "^", lastPos, true)
                    if caretPos then
                        local field = string.sub(inventoryStr, lastPos, caretPos - 1)
                        table.insert(inventoryParts, field)
                        lastPos = caretPos + 1
                        if caretPos == msgLen then
                            table.insert(inventoryParts, "")
                            break
                        end
                    else
                        local field = string.sub(inventoryStr, lastPos)
                        table.insert(inventoryParts, field)
                        break
                    end
                end
            end

            local inventory = {}
            for i = 1, 16 do
                local guid = inventoryParts[i]
                if guid and guid ~= "" then
                    inventory[i] = guid
                else
                    inventory[i] = nil
                end
            end

            -- Update player state
            if not RPMMonitor_PlayerStates then
                RPMMonitor_PlayerStates = {}
            end

            RPMMonitor_PlayerStates[sender] = {
                version = playerVersion,
                syncState = syncState,
                inventory = inventory,
                lastResponse = time(),
                connected = true,
                hasAddon = true
            }

            -- Mark request as responded
            if RPMMonitor_PendingRequests and RPMMonitor_PendingRequests[requestId] then
                if not RPMMonitor_PendingRequests[requestId].responded then
                    RPMMonitor_PendingRequests[requestId].responded = {}
                end
                RPMMonitor_PendingRequests[requestId].responded[sender] = true
            end

            -- Update UI if Monitor tab is visible
            if RPM_CurrentTab == "monitor" and RPMMonitor_UpdatePlayerRow then
                RPMMonitor_UpdatePlayerRow(sender)
            end

            Log("Player state updated for " .. sender .. " (version: " .. tostring(playerVersion) .. ")")
        end
    end
end)

-- ============================================================================
-- SAVED VARIABLES (Database)
-- ============================================================================
-- RPMasterDB will be initialized in PLAYER_LOGIN event
-- (saved variables aren't available until after VARIABLES_LOADED)
--
-- IMPORTANT: SavedVariables are loaded asynchronously
--   1. Code executes (this file is parsed)
--   2. VARIABLES_LOADED event fires → SavedVariables are now available
--   3. PLAYER_LOGIN event fires → Safe to use saved data
--
-- This is similar to async database loading in web apps
-- ============================================================================

-- ============================================================================
-- MODULE REGISTRY (Plugin Architecture)
-- ============================================================================
-- DESIGN PATTERN: Plugin/Module system
--   - Core.lua provides the shell (main window + tabs)
--   - Feature modules (ItemLibrary.lua, States.lua, etc.) register themselves
--   - Each module provides callbacks: createContent(), onShow(), onHide()
--
-- GLOBAL VARIABLES:
--   - RPM_Modules: Dictionary of registered modules
--   - RPM_CurrentTab: Name of currently active tab (string)
--   - RPM_DetachedFrames: Dictionary of detached window frames
--
-- SIMILAR TO: Eclipse plugin system, VS Code extensions, WordPress plugins
-- ============================================================================
RPM_Modules = {}             -- Dictionary: moduleName -> {callbacks, content, etc.}
RPM_CurrentTab = nil         -- String: Currently active tab name (e.g., "items")
RPM_DetachedFrames = {}      -- Dictionary: moduleName -> detached Frame object

-- ============================================================================
-- MAIN WINDOW FRAME
-- ============================================================================
-- WOW FRAME SYSTEM:
--   - Frames are UI containers (like JPanel in Java or div in HTML)
--   - CreateFrame(type, name, parent) creates a new frame
--   - type: "Frame", "Button", "EditBox", "ScrollFrame", etc.
--   - name: Global variable name (optional, but useful for debugging)
--   - parent: Parent frame (UIParent = top-level, like document.body)
--
-- COORDINATE SYSTEM:
--   - Origin is bottom-left of parent
--   - SetPoint() positions relative to parent or other frames
--   - Format: SetPoint("ANCHOR", parent, "PARENT_ANCHOR", xOffset, yOffset)
-- ============================================================================
RPMasterFrame = CreateFrame("Frame", "RPMasterFrame", UIParent)  -- Creates global variable
RPMasterFrame:SetWidth(700)
RPMasterFrame:SetHeight(1000)
RPMasterFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
RPMasterFrame:SetBackdrop({
    bgFile = "Interface\\AddOns\\turtle-rp-master\\black",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
RPMasterFrame:SetBackdropColor(0, 0, 0, 1)
RPMasterFrame:SetMovable(true)
RPMasterFrame:SetResizable(true)  -- Enable resizing
RPMasterFrame:SetMinResize(500, 400)  -- Minimum size
RPMasterFrame:SetMaxResize(1200, 900)  -- Maximum size
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

-- Resize button in bottom-right corner
local resizeBtn = CreateFrame("Button", nil, RPMasterFrame)
resizeBtn:SetPoint("BOTTOMRIGHT", RPMasterFrame, "BOTTOMRIGHT", -7, 7)
resizeBtn:SetWidth(20)
resizeBtn:SetHeight(20)
resizeBtn:EnableMouse(true)
resizeBtn:SetFrameStrata("HIGH")
resizeBtn:SetFrameLevel(RPMasterFrame:GetFrameLevel() + 100)
resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeBtn:SetScript("OnMouseDown", function()
    RPMasterFrame:StartSizing("BOTTOMRIGHT")
end)
resizeBtn:SetScript("OnMouseUp", function()
    RPMasterFrame:StopMovingOrSizing()
    RPM_SaveWindowPosition("main", RPMasterFrame)
end)

-- Tab bar container
local tabBar = CreateFrame("Frame", "RPMTabBar", RPMasterFrame)
tabBar:SetPoint("TOPLEFT", 15, -50)
tabBar:SetPoint("TOPRIGHT", -15, -50)
tabBar:SetHeight(30)

-- Content container (where active tab content shows)
local contentFrame = CreateFrame("Frame", "RPMContentFrame", RPMasterFrame)
contentFrame:SetPoint("TOPLEFT", 15, -85)
contentFrame:SetPoint("BOTTOMRIGHT", -15, 15)

-- ============================================================================
-- TAB BUTTONS (Global registry)
-- ============================================================================
RPM_TabButtons = {}  -- Dictionary: moduleName -> tab Button frame

-- ============================================================================
-- RPM_RegisterModule() - Plugin registration function
-- ============================================================================
-- @param name: String - Module name (e.g., "items", "states")
-- @param callbacks: Table - Module callbacks:
--   - createContent(parentFrame): Called once to build the module's UI
--   - onShow(): Called when tab becomes active
--   - onHide(): Called when switching away from tab
--
-- CALLED BY: Each feature module at the end of their file
--   Example: RPM_RegisterModule("items", {createContent = ..., onShow = ...})
--
-- LIFECYCLE:
--   1. Module file loads → Calls RPM_RegisterModule()
--   2. Core calls createContent() when tab is first shown
--   3. Core calls onShow() when tab becomes active
--   4. Core calls onHide() when switching tabs
--
-- SIMILAR TO: Unity's GameObject.AddComponent() or Angular's module registration
-- ============================================================================
function RPM_RegisterModule(name, callbacks)
    RPM_Modules[name] = {
        name = name,                       -- Module identifier
        createContent = callbacks.createContent,  -- Factory function
        onShow = callbacks.onShow,         -- Activation callback
        onHide = callbacks.onHide,         -- Deactivation callback
        content = nil,                     -- Cached Frame (created lazily)
        tabButton = nil,                   -- Tab button Frame
        detachButton = nil                 -- Detach button Frame
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
        bgFile = "Interface\\AddOns\\turtle-rp-master\\black",
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

-- ============================================================================
-- RPM_SwitchTab() - Switch to a different tab
-- ============================================================================
-- @param tabName: String - Name of tab to switch to (e.g., "items")
-- @returns: void
--
-- BEHAVIOR:
--   1. Validate tab exists and is not detached
--   2. Hide current tab (call onHide, hide UI)
--   3. Show new tab (create UI if first time, call onShow)
--   4. Update visual state (highlight active tab)
--   5. Save preference to database
--
-- LAZY LOADING:
--   - Tab content is only created on first access
--   - module.content is nil until first shown
--   - This is like lazy initialization in Java: if (content == null) { create() }
--
-- SIMILAR TO: React's component lifecycle (componentWillUnmount → componentDidMount)
-- ============================================================================
function RPM_SwitchTab(tabName)
    -- Validation: Ensure database is loaded
    if not RPMasterDB then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r RPMasterDB not initialized yet", 1, 0, 0)
        return
    end

    -- Validation: Ensure module exists
    if not RPM_Modules[tabName] then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Unknown tab: "..tabName, 1, 0, 0)
        return
    end

    -- If tab is detached, show the detached window instead
    if RPMasterDB.preferences.detachedTabs[tabName] then
        local detachedFrame = RPM_DetachedFrames[tabName]
        if detachedFrame then
            detachedFrame:Show()
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[RPMaster]|r Showing detached "..tabName.." window", 1, 1, 0)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Detached window not found for "..tabName, 1, 0, 0)
        end
        return
    end

    -- STEP 1: Hide current tab content
    if RPM_CurrentTab then
        local currentModule = RPM_Modules[RPM_CurrentTab]

        -- Hide the UI frame
        if currentModule.content then
            currentModule.content:Hide()
        end

        -- Call lifecycle callback (similar to componentWillUnmount)
        if currentModule.onHide then
            currentModule.onHide()
        end

        -- Unhighlight tab button (dim color)
        if currentModule.tabButton then
            currentModule.tabButton:SetBackdropColor(0.1, 0.1, 0.1, 1)
        end
    end

    -- STEP 2: Show new tab content
    local module = RPM_Modules[tabName]

    -- Lazy loading: Create content on first access
    if not module.content then
        module.content = module.createContent(contentFrame)  -- Factory pattern
    end

    -- Parent the content frame to the main content area
    module.content:SetParent(contentFrame)
    module.content:SetAllPoints(contentFrame)  -- Fill parent
    module.content:Show()

    -- Call lifecycle callback (similar to componentDidMount)
    if module.onShow then
        module.onShow()
    end

    -- STEP 3: Update visual state
    -- Highlight active tab button (brighter color)
    if module.tabButton then
        module.tabButton:SetBackdropColor(0.2, 0.2, 0.2, 1)
    end

    -- STEP 4: Save state to database
    RPM_CurrentTab = tabName  -- Update global state
    RPMasterDB.preferences.activeTab = tabName  -- Persist to disk
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
        bgFile = "Interface\\AddOns\\turtle-rp-master\\black",
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

    -- Close button (hides window but keeps it detached)
    local detachedCloseBtn = CreateFrame("Button", nil, detachedFrame, "UIPanelCloseButton")
    detachedCloseBtn:SetPoint("TOPRIGHT", -5, -5)
    detachedCloseBtn:SetScript("OnClick", function()
        detachedFrame:Hide()
    end)

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

    -- Keep tab button visible so user can click to show detached window
    -- Visual indicator: change tab button color to show it's detached
    if module.tabButton then
        module.tabButton:SetBackdropColor(0.15, 0.1, 0.2, 1)  -- Slightly purple tint for detached tabs
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

    -- Reset tab button color (was purple when detached)
    if module.tabButton then
        module.tabButton:SetBackdropColor(0.1, 0.1, 0.1, 1)  -- Normal color
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

-- Function: Handle window size changes
RPMasterFrame:SetScript("OnSizeChanged", function()
    -- Save the new size to preferences when the window is resized
    if not RPMasterDB or not RPMasterDB.preferences then
        return
    end
    local width = RPMasterFrame:GetWidth()
    local height = RPMasterFrame:GetHeight()
    RPMasterDB.preferences.windowSize = {width, height}
end)

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

    -- Show all detached windows (they may have been hidden by close button)
    for tabName, detachedFrame in pairs(RPM_DetachedFrames) do
        if detachedFrame and RPMasterDB.preferences.detachedTabs[tabName] then
            detachedFrame:Show()
        end
    end

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
loadFrame:RegisterEvent("VARIABLES_LOADED")
loadFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

local variablesLoaded = false

loadFrame:SetScript("OnEvent", function(self, event)
    if event == "VARIABLES_LOADED" then
        Log("VARIABLES_LOADED event fired")

        -- Initialize RPMasterDB now that saved variables are loaded
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

        -- Load saved window size if available
        if RPMasterDB.preferences.windowSize then
            local width, height = unpack(RPMasterDB.preferences.windowSize)
            RPMasterFrame:SetWidth(width)
            RPMasterFrame:SetHeight(height)
        end

        variablesLoaded = true
        self:UnregisterEvent("VARIABLES_LOADED")

    elseif event == "PLAYER_ENTERING_WORLD" then
        if not variablesLoaded then
            return
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

        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
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

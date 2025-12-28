-- ============================================================================
-- Monitor.lua - Monitor module for RPMaster
-- ============================================================================
-- PURPOSE: Monitor raid members with RPPlayer addon and their inventories
--
-- FEATURES:
--   - View list of raid/party members
--   - Show RPPlayer version (color-coded: green=match, red=mismatch)
--   - Expandable inventory view for each player
--   - Manual refresh button
--   - Auto-refresh every 30 seconds
--   - Database broadcasting functionality
--
-- CURRENT STATE: Using fake data for UI validation but now implementing real sync
-- ============================================================================

local monitorContent = nil  -- Main content frame
local scrollFrame = nil      -- Scrollable area for player list
local scrollChild = nil      -- Child frame inside scrollFrame
local slider = nil           -- Scrollbar widget
local playerRows = {}        -- Cache of player row frames

-- ============================================================================
-- PLAYER MONITORING STATE
-- ============================================================================
-- Global state for tracking player status responses
RPMMonitor_PlayerStates = RPMMonitor_PlayerStates or {}
RPMMonitor_PendingRequests = RPMMonitor_PendingRequests or {}

-- Import shared database logic
local objectDatabase = nil
local function LoadObjectDatabase()
    if not objectDatabase then
        local success, result = pcall(function() return require("turtle-rp-common/objectDatabase") end)
        if success and result then
            objectDatabase = result
        else
            -- Fallback for when the module is not available (shouldn't happen in normal operation)
            objectDatabase = {
                GenerateGUID = function(itemData) return string.format("%d-%d-%d", time(), math.random(1000, 9999), itemData.id or 0) end,
                CreateCommittedDatabase = function(itemLibrary, databaseName) return {items = itemLibrary, metadata = {id = "", name = databaseName or "Unnamed Database", version = time(), checksum = ""}} end,
                VerifyDatabaseIntegrity = function(databaseItems, expectedChecksum) return true end
            }
        end
    end
end

-- ============================================================================
-- GetRealVersionData() - Get actual version data for players
-- ============================================================================
local function GetRealVersionData(playerName)
    local state = RPMMonitor_PlayerStates and RPMMonitor_PlayerStates[playerName]
    if state then
        return state.version or "unknown"
    end
    return "unknown"
end

-- ============================================================================
-- GetRealSyncStatus() - Get actual sync status for players
-- ============================================================================
-- PURPOSE: Get real database sync status
-- RETURNS: "synced", "out_of_sync", or "unknown"
--
-- SYNC STATUS MEANINGS:
--   - "synced": Player has latest committed database (green checkmark)
--   - "out_of_sync": Player has old version or wrong database (red X)
--   - "unknown": No response yet or player doesn't have RPPlayer (grey ?)
-- ============================================================================
local function GetRealSyncStatus(playerName)
    local state = RPMMonitor_PlayerStates and RPMMonitor_PlayerStates[playerName]
    if not state or not state.syncState then
        return "unknown"
    end

    if not RPMasterDB or not RPMasterDB.committedDatabase or not RPMasterDB.committedDatabase.metadata then
        return "unknown"
    end

    local gmChecksum = RPMasterDB.committedDatabase.metadata.checksum
    local playerChecksum = state.syncState.checksum

    if playerChecksum == gmChecksum then
        return "synced"
    else
        return "out_of_sync"
    end
end

-- ============================================================================
-- GetRealInventoryData() - Get actual inventory data using real items from library
-- ============================================================================
local function GetRealInventoryData(playerName)
    local state = RPMMonitor_PlayerStates and RPMMonitor_PlayerStates[playerName]
    if not state or not state.inventory then
        return {}
    end

    -- Convert GUIDs to item IDs
    local itemIds = {}
    if RPMasterDB and RPMasterDB.committedDatabase and RPMasterDB.committedDatabase.items then
        for slot = 1, 16 do
            local guid = state.inventory[slot]
            if guid then
                for id, item in pairs(RPMasterDB.committedDatabase.items) do
                    if item.guid == guid then
                        itemIds[slot] = id
                        break
                    end
                end
            end
        end
    end

    return itemIds
end

-- ============================================================================
-- RPMMonitor_RequestPlayerStatus() - Request status from all raid/party members
-- ============================================================================
-- PURPOSE: Broadcast STATUS_REQUEST to all players
-- WORKFLOW:
--   1. Generate unique requestId
--   2. Broadcast STATUS_REQUEST via RAID/PARTY
--   3. Track request in RPMMonitor_PendingRequests for timeout handling
--   4. Players respond with STATUS_RESPONSE (handled in Core.lua event handler)
-- ============================================================================
function RPMMonitor_RequestPlayerStatus()
    -- Generate unique request ID (timestamp-random)
    local requestId = string.format("%d-%d", time(), math.random(10000, 99999))

    -- Build STATUS_REQUEST message
    local messaging = RequireMessaging()
    local requestMsg = messaging.MESSAGE_TYPES.STATUS_REQUEST .. "^" .. requestId

    -- Determine distribution channel
    local distribution = "RAID"
    if GetNumRaidMembers() == 0 then
        distribution = "PARTY"
    end

    -- Send request
    SendAddonMessage("RPMSTR", requestMsg, distribution)

    -- Track request for timeout handling
    RPMMonitor_PendingRequests[requestId] = {
        sentTime = time(),
        responded = {}
    }

    RPM_Log("STATUS_REQUEST sent (reqId: " .. requestId .. ", dist: " .. distribution .. ")")
end

-- ============================================================================
-- RPMMonitor_UpdatePlayerRow() - Update single player row with real-time data
-- ============================================================================
-- PURPOSE: Update UI for a specific player when STATUS_RESPONSE arrives
-- @param playerName: String - Name of player to update
-- CALLED: From Core.lua event handler when STATUS_RESPONSE received
-- ============================================================================
function RPMMonitor_UpdatePlayerRow(playerName)
    if not monitorContent or not playerRows then return end

    local playerState = RPMMonitor_PlayerStates and RPMMonitor_PlayerStates[playerName]
    if not playerState then return end

    -- Find the row for this player
    local row = nil
    for _, r in pairs(playerRows) do
        if r.playerName == playerName then
            row = r
            break
        end
    end

    if not row then
        -- Row doesn't exist yet, trigger full refresh
        RPMMonitor_RefreshPlayerList()
        return
    end

    -- Update version display
    row.version = playerState.version or "unknown"
    if playerState.hasAddon == false then
        row.versionText:SetText("No Addon")
        row.versionText:SetTextColor(0.5, 0.5, 0.5)  -- Grey
    elseif row.version == "unknown" then
        row.versionText:SetText(row.version)
        row.versionText:SetTextColor(0.5, 0.5, 0.5)  -- Grey (unknown)
    elseif row.version == RP_BUILD_TIME then
        row.versionText:SetText(row.version)
        row.versionText:SetTextColor(0, 1, 0)  -- Green (match)
    else
        row.versionText:SetText(row.version)
        row.versionText:SetTextColor(1, 0, 0)  -- Red (mismatch)
    end

    -- Update sync status icon
    local syncStatus = GetRealSyncStatus(playerName)
    row.syncStatus = syncStatus
    row.syncIcon.syncStatus = syncStatus

    if syncStatus == "synced" then
        row.syncIcon.texture:SetTexture("Interface\\TARGETINGFRAME\\UI-RaidTargetingIcon_6")
        row.syncIcon.texture:SetVertexColor(0, 1, 0, 1)  -- Green
    elseif syncStatus == "out_of_sync" then
        row.syncIcon.texture:SetTexture("Interface\\TARGETINGFRAME\\UI-RaidTargetingIcon_6")
        row.syncIcon.texture:SetVertexColor(1, 0, 0, 1)  -- Red
    else
        row.syncIcon.texture:SetTexture("Interface\\TARGETINGFRAME\\UI-RaidTargetingIcon_6")
        row.syncIcon.texture:SetVertexColor(0.5, 0.5, 0.5, 1)  -- Grey
    end

    -- Update inventory icons
    row.inventoryIds = GetRealInventoryData(playerName)

    -- Update inventory slot visuals
    for slotIndex = 1, 16 do
        local slot = row.inventorySlots[slotIndex]
        local itemId = row.inventoryIds[slotIndex]

        if itemId and RPMasterDB and RPMasterDB.committedDatabase and RPMasterDB.committedDatabase.items and RPMasterDB.committedDatabase.items[itemId] then
            local item = RPMasterDB.committedDatabase.items[itemId]
            slot.icon:SetTexture(item.icon)
            slot.itemData = item
            slot:Show()
        else
            slot.icon:SetTexture(nil)
            slot:Hide()
        end
    end
end

-- ============================================================================
-- RPMMonitor_RefreshPlayerList() - Refresh the list of raid/party members
-- ============================================================================
function RPMMonitor_RefreshPlayerList()
    if not monitorContent then return end

    -- Hide all existing rows
    for _, row in pairs(playerRows) do
        row:Hide()
    end

    -- Get raid/party members with connection status
    local players = {}

    if GetNumRaidMembers() > 0 then
        -- In a raid
        for i = 1, GetNumRaidMembers() do
            local name = UnitName("raid" .. i)
            if name then
                table.insert(players, {
                    name = name,
                    connected = UnitIsConnected("raid" .. i)
                })
            end
        end
    elseif GetNumPartyMembers() > 0 then
        -- In a party
        table.insert(players, {
            name = UnitName("player"),
            connected = true  -- Player is always connected
        })
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party" .. i)
            if name then
                table.insert(players, {
                    name = name,
                    connected = UnitIsConnected("party" .. i)
                })
            end
        end
    else
        -- Solo
        table.insert(players, {
            name = UnitName("player"),
            connected = true
        })
    end

    -- Create/update rows for each player
    local yOffset = -10
    for i, playerData in ipairs(players) do
        local row = playerRows[i]
        if not row then
            row = RPMMonitor_CreatePlayerRow(scrollChild, i)
            playerRows[i] = row
        end

        -- Update row data
        row.playerName = playerData.name
        row.version = GetRealVersionData(playerData.name)
        row.syncStatus = GetRealSyncStatus(playerData.name)  -- Sync status: synced/out_of_sync/unknown
        row.inventoryIds = GetRealInventoryData(playerData.name)  -- Array of item IDs

        -- Update UI
        row.nameText:SetText(playerData.name)

        -- Grey out name if disconnected
        if playerData.connected then
            row.nameText:SetTextColor(1, 1, 1)  -- White (connected)
        else
            row.nameText:SetTextColor(0.5, 0.5, 0.5)  -- Grey (disconnected)
        end

        -- Color code version (green if matches, red if not, grey if unknown)
        if row.version == "unknown" then
            row.versionText:SetText(row.version)
            row.versionText:SetTextColor(0.5, 0.5, 0.5)  -- Grey (unknown)
        elseif row.version == RP_BUILD_TIME then
            row.versionText:SetText(row.version)
            row.versionText:SetTextColor(0, 1, 0)  -- Green
        else
            row.versionText:SetText(row.version)
            row.versionText:SetTextColor(1, 0, 0)  -- Red
        end

        -- ====================================================================
        -- UPDATE SYNC STATUS ICON
        -- ====================================================================
        -- Set icon texture and color based on sync status
        -- WoW 1.12 doesn't have built-in checkmark/X icons, so we use:
        --   - Colored circles to represent status
        --   - Green circle = synced
        --   - Red circle = out of sync
        --   - Grey circle = unknown
        -- ====================================================================
        row.syncIcon.playerName = playerData.name  -- For click handler
        row.syncIcon.syncStatus = row.syncStatus    -- For tooltip

        if row.syncStatus == "synced" then
            -- Green circle (synced)
            row.syncIcon.texture:SetTexture("Interface\\TARGETINGFRAME\\UI-RaidTargetingIcon_6")  -- Green square icon
            row.syncIcon.texture:SetVertexColor(0, 1, 0, 1)  -- Tint green
        elseif row.syncStatus == "out_of_sync" then
            -- Red circle (out of sync)
            row.syncIcon.texture:SetTexture("Interface\\TARGETINGFRAME\\UI-RaidTargetingIcon_6")  -- Same icon
            row.syncIcon.texture:SetVertexColor(1, 0, 0, 1)  -- Tint red
        else
            -- Grey circle (unknown)
            row.syncIcon.texture:SetTexture("Interface\\TARGETINGFRAME\\UI-RaidTargetingIcon_6")  -- Same icon
            row.syncIcon.texture:SetVertexColor(0.5, 0.5, 0.5, 1)  -- Tint grey
        end

        -- Update inventory icons (16 slots)
        for slotIndex = 1, 16 do
            local slot = row.inventorySlots[slotIndex]
            local itemId = row.inventoryIds[slotIndex]

            if itemId and RPMasterDB and RPMasterDB.itemLibrary and RPMasterDB.itemLibrary[itemId] then
                -- Show item icon
                local item = RPMasterDB.itemLibrary[itemId]
                slot.icon:SetTexture(item.icon)
                slot:Show()

                -- Set tooltip
                slot.itemData = item
                slot:SetScript("OnEnter", function()
                    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                    GameTooltip:SetText(this.itemData.name, 1, 1, 1)
                    if this.itemData.tooltip and this.itemData.tooltip ~= "" then
                        GameTooltip:AddLine(this.itemData.tooltip, 0.7, 0.7, 0.7, 1)
                    end
                    GameTooltip:Show()
                end)
                slot:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            else
                -- Empty slot
                slot.icon:SetTexture(nil)
                slot:Hide()
            end
        end

        -- Position row
        row:SetPoint("TOPLEFT", 10, yOffset)
        row:Show()

        yOffset = yOffset - 45  -- Row height (slightly taller for icons)
    end

    -- Update scroll height
    local totalHeight = math.abs(yOffset) + 20
    scrollChild:SetHeight(math.max(totalHeight, 1))

    -- Update scrollbar range
    local viewHeight = scrollFrame:GetHeight() or 0
    local max = totalHeight - viewHeight
    if max < 0 then max = 0 end
    slider:SetMinMaxValues(0, max)
    slider:SetValue(0)
end

-- ============================================================================
-- RPMMonitor_CreatePlayerRow() - Create a row for one player
-- ============================================================================
-- LAYOUT:
--   [Name 100px] [Version 60px] [SyncIcon 24px] [16 inventory slots]
--   - Name: Player name (greyed if disconnected)
--   - Version: Addon version (green=match, red=mismatch)
--   - SyncIcon: Database sync status (clickable to sync individual player)
--   - Inventory: 16 item slots with tooltips
-- ============================================================================
function RPMMonitor_CreatePlayerRow(parent, index)
    local row = CreateFrame("Frame", "RPMMonitorPlayerRow" .. index, parent)
    row:SetWidth(750)
    row:SetHeight(40)

    -- Background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0, 0, 0, 0.3)

    -- Player name (100px)
    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameText:SetPoint("LEFT", 5, 0)
    row.nameText:SetWidth(100)
    row.nameText:SetJustifyH("LEFT")

    -- Version (60px)
    row.versionText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.versionText:SetPoint("LEFT", 110, 0)
    row.versionText:SetWidth(60)
    row.versionText:SetJustifyH("LEFT")

    -- ========================================================================
    -- SYNC STATUS ICON (24px, clickable)
    -- ========================================================================
    -- PURPOSE: Shows if player has synced database, click to sync
    -- ICONS:
    --   - Green checkmark: Player has latest committed database
    --   - Red X: Player out of sync or has different database
    --   - Grey ?: Unknown status (no response or no RPPlayer addon)
    -- ========================================================================
    row.syncIcon = CreateFrame("Button", nil, row)
    row.syncIcon:SetWidth(24)
    row.syncIcon:SetHeight(24)
    row.syncIcon:SetPoint("LEFT", 175, 0)

    -- Sync icon texture (will be set based on status)
    row.syncIcon.texture = row.syncIcon:CreateTexture(nil, "ARTWORK")
    row.syncIcon.texture:SetAllPoints()

    -- Sync icon click handler
    row.syncIcon:SetScript("OnClick", function()
        if this.playerName then
            RPMMonitor_SyncPlayer(this.playerName)
        end
    end)

    -- Sync icon tooltip
    row.syncIcon:SetScript("OnEnter", function()
        if not this.syncStatus or not this.playerName then return end

        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(this.playerName, 1, 1, 1)

        if this.syncStatus == "synced" then
            GameTooltip:AddLine("Database: Synced", 0, 1, 0)
        elseif this.syncStatus == "out_of_sync" then
            GameTooltip:AddLine("Database: Out of sync", 1, 0, 0)
        else
            GameTooltip:AddLine("Database: Unknown", 0.5, 0.5, 0.5)
        end

        GameTooltip:AddLine("Click to sync", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    row.syncIcon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- 16 item slots inline (starting after sync icon)
    row.inventorySlots = {}
    local slotSize = 32
    local spacing = 2
    local startX = 205  -- Moved right to make room for sync icon

    for i = 1, 16 do
        local slot = CreateFrame("Button", nil, row)
        slot:SetWidth(slotSize)
        slot:SetHeight(slotSize)
        slot:SetPoint("LEFT", startX + (i - 1) * (slotSize + spacing), 0)

        -- Slot background
        local slotBg = slot:CreateTexture(nil, "BACKGROUND")
        slotBg:SetAllPoints()
        slotBg:SetTexture(0, 0, 0, 0.5)

        -- Item icon texture
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetAllPoints()
        slot.icon:SetTexture(nil)

        -- Border
        local border = slot:CreateTexture(nil, "OVERLAY")
        border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        border:SetAllPoints()
        border:SetBlendMode("ADD")
        border:SetAlpha(0.5)

        slot:Hide()
        row.inventorySlots[i] = slot
    end

    return row
end

-- ============================================================================
-- RPMMonitor_CreateContent() - Create the Monitor tab UI
-- ============================================================================
function RPMMonitor_CreateContent(parent)
    monitorContent = CreateFrame("Frame", "RPMMonitorContent", parent)
    monitorContent:SetAllPoints()

    -- Title
    local title = monitorContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("RPPlayer Monitor")

    -- ========================================================================
    -- DATABASE STATUS TEXT (shows if database is ready for sync)
    -- ========================================================================
    -- PURPOSE: Visual indicator if database is committed and ready
    -- DISPLAY:
    --   - "DB OK" in green = database committed and named
    --   - "DB NoK" in red = database not committed or missing name
    -- POSITION: Below title, centered
    -- ========================================================================
    local dbStatusText = monitorContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dbStatusText:SetPoint("TOP", 0, -25)
    monitorContent.dbStatusText = dbStatusText

    -- Function to update database status text
    local function UpdateDatabaseStatus()
        if RPMasterDB and RPMasterDB.committedDatabase and
           RPMasterDB.committedDatabase.metadata and
           RPMasterDB.committedDatabase.metadata.name and
           RPMasterDB.committedDatabase.metadata.name ~= "" then
            -- Database is committed and named = OK
            dbStatusText:SetText("DB OK")
            dbStatusText:SetTextColor(0, 1, 0)  -- Green
        else
            -- Database not committed or no name = Not OK
            dbStatusText:SetText("DB NoK")
            dbStatusText:SetTextColor(1, 0, 0)  -- Red
        end
    end

    -- Initial status update
    UpdateDatabaseStatus()

    -- Store function for refresh
    monitorContent.UpdateDatabaseStatus = UpdateDatabaseStatus

    -- Scrollable player list
    scrollFrame = CreateFrame("ScrollFrame", "RPMMonitorScrollFrame", monitorContent)
    scrollFrame:SetPoint("TOPLEFT", 10, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 50)
    scrollFrame:EnableMouseWheel(true)

    scrollFrame:SetScript("OnVerticalScroll", function()
        local offset = arg1  -- Lua 5.0: event parameter
        slider:SetValue(offset)
    end)

    -- Scrollbar
    slider = CreateFrame("Slider", "RPMMonitorScrollBar", scrollFrame, "UIPanelScrollBarTemplate")
    slider:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 4, -16)
    slider:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4, 16)
    slider:SetMinMaxValues(0, 100)
    slider:SetValueStep(1)
    slider:SetValue(0)
    slider:SetWidth(16)

    slider:SetScript("OnValueChanged", function()
        local value = arg1  -- Lua 5.0: event parameter
        scrollFrame:SetVerticalScroll(value)
    end)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(750)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Mouse wheel scrolling
    scrollFrame:SetScript("OnMouseWheel", function()
        local delta = arg1  -- Lua 5.0: event parameter
        local current = slider:GetValue()
        local minVal, maxVal = slider:GetMinMaxValues()
        if delta > 0 then
            slider:SetValue(math.max(minVal, current - 40))
        else
            slider:SetValue(math.min(maxVal, current + 40))
        end
    end)

    -- ========================================================================
    -- BOTTOM BUTTONS - Refresh and Sync All
    -- ========================================================================
    -- Refresh button (left)
    local refreshBtn = CreateFrame("Button", nil, monitorContent, "UIPanelButtonTemplate")
    refreshBtn:SetPoint("BOTTOM", -85, 10)
    refreshBtn:SetWidth(150)
    refreshBtn:SetHeight(30)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        RPMMonitor_RequestPlayerStatus()
        RPMMonitor_RefreshPlayerList()
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD700[RPMaster]|r Requesting player status...", 1, 1, 0)
    end)

    -- Sync All button (right)
    -- PURPOSE: Send committed database to all raid/party members
    local syncAllBtn = CreateFrame("Button", nil, monitorContent, "UIPanelButtonTemplate")
    syncAllBtn:SetPoint("BOTTOM", 85, 10)
    syncAllBtn:SetWidth(150)
    syncAllBtn:SetHeight(30)
    syncAllBtn:SetText("Sync All")
    syncAllBtn:SetScript("OnClick", function()
        RPMMonitor_SyncAll()
    end)

    return monitorContent
end

-- ============================================================================
-- RPMMonitor_SyncPlayer() - Sync database to individual player
-- ============================================================================
-- PURPOSE: Send committed database to a specific player
-- @param playerName: String - Target player name
--
-- WORKFLOW (FUTURE IMPLEMENTATION):
--   1. Check if database is committed (RPMasterDB.committedDatabase exists)
--   2. Send DB_SYNC message with database ID, name, and version
--   3. Send all items from committedDatabase.items (NOT current edits)
--   4. Update sync status when player responds
--
-- CURRENT: Fake implementation for GUI validation
-- ============================================================================
function RPMMonitor_SyncPlayer(playerName)
    -- Validate database
    if not RPMasterDB or not RPMasterDB.committedDatabase or not RPMasterDB.committedDatabase.items then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r No committed database to sync! Click 'Commit Database' first.", 1, 0, 0)
        return
    end

    if not RPMasterDB.committedDatabase.metadata or not RPMasterDB.committedDatabase.metadata.name or RPMasterDB.committedDatabase.metadata.name == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Database has no name! Set one in Item Library tab.", 1, 0, 0)
        return
    end

    -- FAKE: Just log and show message
    -- TODO: Implement actual sync via SendAddonMessage
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFFFFD700[RPMaster]|r Syncing database '%s' to %s (FAKE)",
        RPMasterDB.committedDatabase.metadata.name, playerName), 1, 1, 0)

    -- Count items in committed database
    local itemCount = table.getn(RPMasterDB.committedDatabase.items) or 0

    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF888888  Database ID: %s, Version: %d, Items: %d, Checksum: %s|r",
        RPMasterDB.committedDatabase.metadata.id or "none",
        RPMasterDB.committedDatabase.metadata.version or 0,
        itemCount,
        RPMasterDB.committedDatabase.metadata.checksum or "none"), 0.5, 0.5, 0.5)
end

-- ============================================================================
-- RPMMonitor_SyncAll() - Sync database to all raid/party members
-- ============================================================================
-- PURPOSE: Broadcast committed database to all players in raid/party
--
-- WORKFLOW (FUTURE IMPLEMENTATION):
--   1. Check if database is committed
--   2. Get list of all raid/party members
--   3. Send DB_SYNC to each member (broadcast or individual whispers)
--   4. Track sync responses and update UI
--
-- CURRENT: Fake implementation for GUI validation
-- ============================================================================
function RPMMonitor_SyncAll()
    -- Validate database
    if not RPMasterDB or not RPMasterDB.committedDatabase or not RPMasterDB.committedDatabase.items then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r No committed database to sync! Click 'Commit Database' first.", 1, 0, 0)
        return
    end

    if not RPMasterDB.committedDatabase.metadata or not RPMasterDB.committedDatabase.metadata.name or RPMasterDB.committedDatabase.metadata.name == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Database has no name! Set one in Item Library tab.", 1, 0, 0)
        return
    end

    -- Get player list
    local playerCount = 0
    if GetNumRaidMembers() > 0 then
        playerCount = GetNumRaidMembers()
    elseif GetNumPartyMembers() > 0 then
        playerCount = GetNumPartyMembers() + 1  -- Party + self
    else
        playerCount = 1  -- Solo
    end

    -- Count items
    local itemCount = table.getn(RPMasterDB.committedDatabase.items) or 0

    -- FAKE: Just log and show message
    -- TODO: Implement actual broadcast sync
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFFFFD700[RPMaster]|r Syncing database '%s' to %d players (FAKE)",
        RPMasterDB.databaseName, playerCount), 1, 1, 0)

    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF888888  Database ID: %s, Version: %d, Items: %d|r",
        RPMasterDB.databaseId or "none", RPMasterDB.committedVersion or 0, itemCount), 0.5, 0.5, 0.5)
end

-- ============================================================================
-- RPMMonitor_CheckRequestTimeouts() - Check for expired STATUS_REQUEST timeouts
-- ============================================================================
-- PURPOSE: Mark non-responding players as not having addon
-- WORKFLOW:
--   1. Iterate through pending requests
--   2. If elapsed time >= 5 seconds, mark non-responders as hasAddon=false
--   3. Clean up old requests
-- CALLED: Every 1 second by OnUpdate frame
-- ============================================================================
function RPMMonitor_CheckRequestTimeouts()
    if not RPMMonitor_PendingRequests then return end

    local currentTime = time()
    local timeoutSeconds = 5

    for requestId, requestData in pairs(RPMMonitor_PendingRequests) do
        local elapsed = currentTime - requestData.sentTime

        if elapsed >= timeoutSeconds then
            -- Get list of all raid/party members
            local allPlayers = {}

            if GetNumRaidMembers() > 0 then
                for i = 1, GetNumRaidMembers() do
                    local name = UnitName("raid" .. i)
                    if name then
                        table.insert(allPlayers, name)
                    end
                end
            elseif GetNumPartyMembers() > 0 then
                table.insert(allPlayers, UnitName("player"))
                for i = 1, GetNumPartyMembers() do
                    local name = UnitName("party" .. i)
                    if name then
                        table.insert(allPlayers, name)
                    end
                end
            else
                table.insert(allPlayers, UnitName("player"))
            end

            -- Mark non-responders as not having addon
            for _, playerName in ipairs(allPlayers) do
                local responded = requestData.responded and requestData.responded[playerName]

                if not responded then
                    -- Player didn't respond = no addon or offline
                    if not RPMMonitor_PlayerStates then
                        RPMMonitor_PlayerStates = {}
                    end

                    if not RPMMonitor_PlayerStates[playerName] then
                        RPMMonitor_PlayerStates[playerName] = {}
                    end

                    RPMMonitor_PlayerStates[playerName].hasAddon = false
                    RPMMonitor_PlayerStates[playerName].version = "unknown"
                    RPMMonitor_PlayerStates[playerName].lastResponse = nil
                end
            end

            -- Clean up old request
            RPMMonitor_PendingRequests[requestId] = nil

            -- Refresh UI to show timeouts
            if RPM_CurrentTab == "monitor" then
                RPMMonitor_RefreshPlayerList()
            end
        end
    end
end

-- ============================================================================
-- TIMEOUT FRAME - OnUpdate handler for checking timeouts
-- ============================================================================
local timeoutFrame = CreateFrame("Frame")
local timeSinceLastCheck = 0
timeoutFrame:SetScript("OnUpdate", function()
    local elapsed = arg1  -- Lua 5.0: OnUpdate elapsed time
    timeSinceLastCheck = timeSinceLastCheck + elapsed

    if timeSinceLastCheck >= 1 then  -- Check every 1 second
        RPMMonitor_CheckRequestTimeouts()
        timeSinceLastCheck = 0
    end
end)

-- ============================================================================
-- AUTO-REFRESH FRAME - OnUpdate handler for 30-second auto-refresh
-- ============================================================================
local autoRefreshFrame = CreateFrame("Frame")
local timeSinceLastRefresh = 0
autoRefreshFrame:SetScript("OnUpdate", function()
    local elapsed = arg1  -- Lua 5.0: OnUpdate elapsed time
    timeSinceLastRefresh = timeSinceLastRefresh + elapsed

    if timeSinceLastRefresh >= 30 then  -- Auto-refresh every 30 seconds
        -- Only auto-refresh if Monitor tab is visible
        if RPM_CurrentTab == "monitor" then
            RPMMonitor_RequestPlayerStatus()
        end
        timeSinceLastRefresh = 0
    end
end)

-- ============================================================================
-- MODULE LIFECYCLE CALLBACKS
-- ============================================================================

-- ============================================================================
-- RPMMonitor_UpdateDatabaseStatus() - Update database status display
-- ============================================================================
-- PURPOSE: Called from other modules (e.g., ItemLibrary) to update DB status
-- EXAMPLE: After committing database in Item Library tab
-- ============================================================================
function RPMMonitor_UpdateDatabaseStatus()
    if monitorContent and monitorContent.UpdateDatabaseStatus then
        monitorContent.UpdateDatabaseStatus()
    end
end

-- RPMMonitor_Show() - Called when Monitor tab becomes active
function RPMMonitor_Show()
    -- Update database status text
    RPMMonitor_UpdateDatabaseStatus()

    -- Refresh player list when tab is shown
    RPMMonitor_RefreshPlayerList()
end

-- RPMMonitor_Hide() - Called when switching away from Monitor tab
function RPMMonitor_Hide()
    -- Nothing to do
end

-- ============================================================================
-- MODULE REGISTRATION
-- ============================================================================
-- Register with Core's plugin system
-- ============================================================================
RPM_RegisterModule("monitor", {
    createContent = RPMMonitor_CreateContent,
    onShow = RPMMonitor_Show,
    onHide = RPMMonitor_Hide
})

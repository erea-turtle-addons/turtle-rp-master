-- ============================================================================
-- master-actions.lua - GM-side Action GUI for Turtle RP Master
-- ============================================================================
-- PURPOSE: Handle all GUI aspects of action execution on the GM side
--
-- RESPONSIBILITIES:
--   - Send actual raid warnings (DisplayRaidWarning)
--   - Handle GM-side notifications
--   - Process player action requests (CreateObject, etc.)
--
-- ARCHITECTURE:
--   - rp-common/rp-actions.lua: Pure business logic (ExecuteAction)
--   - master-actions.lua: GM-side GUI (THIS FILE)
--   - Different from player-actions.lua (GM has different permissions)
--
-- USAGE:
--   local masterActions = RequireMasterActions()
--   masterActions.ExecuteAction(item, action)
-- ============================================================================

-- Import dependencies (lazy loading to avoid initialization order issues)
local rpActions = nil
local function GetRPActions()
    if not rpActions then
        rpActions = RequireRPActions()
    end
    return rpActions
end

-- ============================================================================
-- Log() - Local logging function wrapper
-- ============================================================================
local function Log(message)
    if RPMasterDebugLog then
        -- WoW 1.12: No date() function, use simple logging
        local logEntry = string.format("RPMaster: %s", tostring(message))
        table.insert(RPMasterDebugLog, logEntry)
        if table.getn(RPMasterDebugLog) > 500 then
            table.remove(RPMasterDebugLog, 1)
        end
    end
end

-- ============================================================================
-- RESULT HANDLERS
-- ============================================================================

-- ============================================================================
-- HandleSendGmMessage - Send actual raid warning or other messages
-- ============================================================================
local function HandleSendGmMessage(item, action, result)
    local message = result.data.message
    local messageType = result.data.messageType

    if messageType == "RAID_WARNING" then
        -- GM can send actual raid warnings
        if GetNumRaidMembers() > 0 then
            SendChatMessage(message, "RAID_WARNING")
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r Raid warning sent: " .. message, 0, 1, 0)
        else
            -- Not in raid, display locally
            RaidNotice_AddMessage(RaidWarningFrame, message, ChatTypeInfo["RAID_WARNING"])
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFAA00[RPMaster]|r Not in raid. Message displayed locally: " .. message, 1, 1, 0)
        end
    else
        -- Other message types
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r Message: " .. message, 0, 1, 0)
    end
end

-- ============================================================================
-- HandleSuccess - Generic success message
-- ============================================================================
local function HandleSuccess(item, action, result)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r " .. (result.message or "Action executed: " .. action.label), 0, 1, 0)
end

-- ============================================================================
-- HandleFail - Action failed (not an error, just failed validation)
-- ============================================================================
local function HandleFail(item, action, result)
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFAA00[RPMaster]|r " .. (result.message or "Action failed"), 1, 1, 0)
end

-- ============================================================================
-- HandleError - Execution error
-- ============================================================================
local function HandleError(item, action, result)
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Error: " .. (result.message or "Unknown error"), 1, 0, 0)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- ============================================================================
-- ExecuteAction - Execute action and handle GUI for result (GM side)
-- ============================================================================
-- @param item: Table - Item object with actions
-- @param action: Table - Action object to execute
-- @returns: void
--
-- FLOW:
--   1. Call rpActions.ExecuteAction (business logic)
--   2. Handle result.result type (GUI logic)
--   3. GM-specific handling (e.g. actual raid warnings)
--
-- NOTE: GM side handles fewer result types than player side
--       (REQUEST_INPUT, CREATE_OBJECT, etc. are player-only)
-- ============================================================================
local function ExecuteAction(item, action)
    Log("ExecuteAction called - Item: " .. tostring(item.name) .. ", Action: " .. tostring(action.id))

    local playerName = UnitName("player")
    local rpActions = GetRPActions()  -- Lazy load
    local result = rpActions.ExecuteAction(playerName, item, action.id)

    if not result then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Action execution failed: No result returned", 1, 0, 0)
        return
    end

    -- Dispatch to appropriate handler based on result type
    if result.result == rpActions.RESULT_TYPES.SEND_GM_MESSAGE then
        HandleSendGmMessage(item, action, result)

    elseif result.result == rpActions.RESULT_TYPES.SUCCESS then
        HandleSuccess(item, action, result)

    elseif result.result == rpActions.RESULT_TYPES.FAIL then
        HandleFail(item, action, result)

    elseif result.result == rpActions.RESULT_TYPES.ERROR then
        HandleError(item, action, result)

    else
        -- Other result types not typically used by GM
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFAA00[RPMaster]|r Result type '" .. tostring(result.result) .. "' not handled on GM side", 1, 1, 0)
        Log("Unhandled result type: " .. tostring(result.result))
    end
end

-- ============================================================================
-- EXPORT FUNCTIONS
-- ============================================================================

function RequireMasterActions()
    return {
        ExecuteAction = ExecuteAction
    }
end

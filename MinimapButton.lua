-- ============================================================================
-- MinimapButton.lua - Minimap button for RPMaster
-- ============================================================================
-- PURPOSE: Provides a minimap button to quickly open the RPMaster interface
--
-- FEATURES:
--   - Draggable around the minimap edge
--   - Left-click to toggle RPMaster window
--   - Right-click for quick menu
--   - Tooltip with addon info and instructions
--   - Position persistence (remembers location)
--
-- ARCHITECTURE:
--   - Simple standalone module
--   - Integrates with existing Core.lua functions
--   - Uses SavedVariables for position storage
--
-- LUA VERSION: Lua 5.0 (WoW 1.12 environment)
-- ============================================================================

-- ============================================================================
-- CONSTANTS
-- ============================================================================
local BUTTON_SIZE = 32  -- Size of the minimap button
local BUTTON_RADIUS = 80  -- Distance from minimap center

-- ============================================================================
-- SAVED VARIABLES
-- ============================================================================
-- RPMasterDB.minimapButton will store position angle
-- Format: RPMasterDB.minimapButton = { angle = 45 }

-- ============================================================================
-- CREATE MINIMAP BUTTON FRAME
-- ============================================================================
local minimapButton = CreateFrame("Button", "RPMasterMinimapButton", Minimap)
minimapButton:SetWidth(BUTTON_SIZE)
minimapButton:SetHeight(BUTTON_SIZE)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetMovable(true)
minimapButton:EnableMouse(true)
minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapButton:RegisterForDrag("LeftButton")

-- Button background texture
local bg = minimapButton:CreateTexture(nil, "BACKGROUND")
bg:SetWidth(BUTTON_SIZE)
bg:SetHeight(BUTTON_SIZE)
bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
bg:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)

-- Button icon texture
local icon = minimapButton:CreateTexture(nil, "ARTWORK")
icon:SetWidth(20)
icon:SetHeight(20)
icon:SetTexture("Interface\\Icons\\INV_Misc_Note_02")  -- Note icon
icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)  -- Crop edges for cleaner look
icon:SetPoint("CENTER", minimapButton, "CENTER",  0, 0)

-- Border overlay
local border = minimapButton:CreateTexture(nil, "OVERLAY")
border:SetWidth(52)
border:SetHeight(52)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT", minimapButton, "TOPLEFT",0, 0)

-- ============================================================================
-- UpdatePosition() - Position button around minimap edge
-- ============================================================================
-- @param angle: Number (0-360 degrees) - Position angle around minimap
-- @returns: void
--
-- BEHAVIOR:
--   - Converts angle to radians
--   - Calculates X,Y offset from minimap center
--   - Positions button at that location
--
-- MATH:
--   - X = radius * cos(angle)
--   - Y = radius * sin(angle)
-- ============================================================================
local function UpdatePosition(angle)
    local x = math.cos(angle) * BUTTON_RADIUS
    local y = math.sin(angle) * BUTTON_RADIUS
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

-- Tooltip
minimapButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(minimapButton, "ANCHOR_LEFT")
    GameTooltip:SetText("RP Master", 1, 1, 1)
    GameTooltip:AddLine("Game Master RP Item Tool", 0.8, 0.8, 0.8)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: Open/Close", 0, 1, 0)
    GameTooltip:AddLine("Right-click: Quick menu", 0, 1, 0)
    GameTooltip:AddLine("Drag: Move button", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end)

minimapButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Left-click: Toggle main window
-- Right-click: Show quick menu (for future features)
minimapButton:SetScript("OnClick", function()
    local button = arg1 or "LeftButton"

    if button == "LeftButton" then
        -- Call existing toggle function from Core.lua
        if RPM_ToggleMainFrame then
            RPM_ToggleMainFrame()
        end
    elseif button == "RightButton" then
        -- Quick menu (future enhancement - for now just toggle)
        if RPM_ToggleMainFrame then
            RPM_ToggleMainFrame()
        end
    end
end)

-- Drag handlers (move around minimap)
minimapButton:SetScript("OnDragStart", function()
    minimapButton:LockHighlight()
    minimapButton.isDragging = true
end)

minimapButton:SetScript("OnDragStop", function()
    minimapButton:UnlockHighlight()
    minimapButton.isDragging = false

    -- Save position
    if RPMasterDB and RPMasterDB.preferences then
        if not RPMasterDB.preferences.minimapButton then
            RPMasterDB.preferences.minimapButton = {}
        end

        -- Calculate angle from current position
        local x, y = minimapButton:GetCenter()
        local mmX, mmY = Minimap:GetCenter()
        local angle = math.atan2(y - mmY, x - mmX)

        RPMasterDB.preferences.minimapButton.angle = angle
    end
end)

minimapButton:SetScript("OnUpdate", function()
    if minimapButton.isDragging then
        -- Update position while dragging
        local mouseX, mouseY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        mouseX = mouseX / scale
        mouseY = mouseY / scale

        local mmX, mmY = Minimap:GetCenter()
        local angle = math.atan2(mouseY - mmY, mouseX - mmX)

        UpdatePosition(angle)
    end
end)

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
-- Wait for PLAYER_LOGIN to ensure SavedVariables are loaded
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    -- Wait a short delay to ensure RPMasterDB is initialized in Core.lua
    initFrame.timer = 0
    initFrame:SetScript("OnUpdate", function()
        initFrame.timer = initFrame.timer + arg1
        if initFrame.timer >= 1.0 then  -- Wait 1 second after login
            -- Ensure preferences structure exists
            if RPMasterDB and not RPMasterDB.preferences.minimapButton then
                RPMasterDB.preferences.minimapButton = {
                    angle = math.rad(225)  -- Default: bottom-left (225 degrees)
                }
            end

            -- Load saved position or use default
            local angle = math.rad(225)  -- Default angle
            if RPMasterDB and RPMasterDB.preferences and RPMasterDB.preferences.minimapButton then
                angle = RPMasterDB.preferences.minimapButton.angle
            end

            UpdatePosition(angle)
            minimapButton:Show()

            -- Stop the update loop
            initFrame:SetScript("OnUpdate", nil)
        end
    end)

    initFrame:UnregisterEvent("PLAYER_LOGIN")
end)

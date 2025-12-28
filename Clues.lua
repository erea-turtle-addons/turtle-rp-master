-- ============================================================================
-- Clues.lua - Clues management module for RPMaster
-- ============================================================================
-- PURPOSE: Create and manage clues that players can search for at specific
--          locations in the world
--
-- FEATURES:
--   - Create/Edit/Delete clues with name, description, zone, coordinates
--   - Assign clues to specific players for searching
--   - Track which players have found which clues
--
-- DATA MODEL:
--   Clue = {
--     id: number (unique, auto-incrementing)
--     name: string (clue title)
--     description: string (what the clue contains)
--     zone: string (zone name, e.g., "Elwynn Forest")
--     x: number (x coordinate, 0-100)
--     y: number (y coordinate, 0-100)
--     assignedTo: string or nil (player name who can find this clue)
--   }
-- ============================================================================

local cluesContent = nil       -- Main content frame
local scrollFrame = nil        -- Scrollable area for clue list
local scrollChild = nil        -- Child frame inside scrollFrame
local slider = nil             -- Scrollbar widget
local editFrame = nil          -- Clue edit dialog

-- Edit form fields
local nameEdit, descEdit, zoneEdit, xEdit, yEdit
local currentEditingClue = nil  -- Clue being edited (nil = creating new)

-- ============================================================================
-- RPMClues_CreateContent() - Create the Clues tab UI
-- ============================================================================
function RPMClues_CreateContent(parent)
    cluesContent = CreateFrame("Frame", "RPMCluesContent", parent)
    cluesContent:SetAllPoints()

    -- Title
    local title = cluesContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Clue Management")

    -- Scrollable clue list
    scrollFrame = CreateFrame("ScrollFrame", "RPMCluesScrollFrame", cluesContent)
    scrollFrame:SetPoint("TOPLEFT", 10, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 60)
    scrollFrame:EnableMouseWheel(true)

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        slider:SetValue(offset)
    end)

    -- Scrollbar
    slider = CreateFrame("Slider", "RPMCluesScrollBar", scrollFrame, "UIPanelScrollBarTemplate")
    slider:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 4, -16)
    slider:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4, 16)
    slider:SetMinMaxValues(0, 100)
    slider:SetValueStep(1)
    slider:SetValue(0)
    slider:SetWidth(16)

    slider:SetScript("OnValueChanged", function(self, value)
        scrollFrame:SetVerticalScroll(value)
    end)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(750)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Mouse wheel scrolling
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = slider:GetValue()
        local minVal, maxVal = slider:GetMinMaxValues()
        if delta > 0 then
            slider:SetValue(math.max(minVal, current - 40))
        else
            slider:SetValue(math.min(maxVal, current + 40))
        end
    end)

    -- Action buttons
    local newClueBtn = CreateFrame("Button", nil, cluesContent, "UIPanelButtonTemplate")
    newClueBtn:SetPoint("BOTTOMLEFT", 10, 10)
    newClueBtn:SetWidth(150)
    newClueBtn:SetHeight(30)
    newClueBtn:SetText("New Clue")
    newClueBtn:SetScript("OnClick", function()
        RPMClues_OpenEditForm(nil)
    end)

    local refreshBtn = CreateFrame("Button", nil, cluesContent, "UIPanelButtonTemplate")
    refreshBtn:SetPoint("BOTTOMLEFT", 170, 10)
    refreshBtn:SetWidth(150)
    refreshBtn:SetHeight(30)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        RPMClues_RefreshClueList()
    end)

    -- Create edit form
    RPMClues_CreateEditFrame()

    return cluesContent
end

-- ============================================================================
-- RPMClues_CreateEditFrame() - Create clue edit dialog
-- ============================================================================
function RPMClues_CreateEditFrame()
    editFrame = CreateFrame("Frame", "RPMCluesEditFrame", UIParent)
    editFrame:SetWidth(500)
    editFrame:SetHeight(400)
    editFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    editFrame:SetFrameStrata("DIALOG")
    editFrame:SetBackdrop({
        bgFile = "Interface\\AddOns\\turtle-rp-master\\black",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    editFrame:SetBackdropColor(0, 0, 0, 1)
    editFrame:SetMovable(true)
    editFrame:EnableMouse(true)
    editFrame:RegisterForDrag("LeftButton")
    editFrame:SetScript("OnDragStart", editFrame.StartMoving)
    editFrame:SetScript("OnDragStop", editFrame.StopMovingOrSizing)
    editFrame:Hide()

    -- Title
    local editTitle = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    editTitle:SetPoint("TOP", 0, -20)
    editTitle:SetText("Edit Clue")

    -- Close button
    local editCloseBtn = CreateFrame("Button", nil, editFrame, "UIPanelCloseButton")
    editCloseBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Helper function to create edit boxes
    local function CreateEditBox(parent, label, yOffset, height, multiline)
        local labelText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelText:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
        labelText:SetText(label)

        local editBox
        if multiline then
            editBox = CreateFrame("EditBox", nil, parent)
            editBox:SetMultiLine(true)
            editBox:SetAutoFocus(false)
            editBox:SetFontObject(GameFontHighlight)
            editBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset - 20)
            editBox:SetWidth(440)
            editBox:SetHeight(height)
            editBox:EnableMouse(true)
            editBox:SetMaxLetters(0)

            local bg = editBox:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(editBox)
            bg:SetTexture(0, 0, 0, 0.5)

            editBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
            editBox:SetScript("OnMouseDown", function() this:SetFocus() end)
        else
            editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
            editBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset - 20)
            editBox:SetWidth(440)
            editBox:SetHeight(height)
            editBox:SetAutoFocus(false)
        end

        return editBox
    end

    -- Edit fields
    nameEdit = CreateEditBox(editFrame, "Clue Name:", -50, 30, false)
    descEdit = CreateEditBox(editFrame, "Description:", -100, 80, true)
    zoneEdit = CreateEditBox(editFrame, "Zone (e.g., 'Elwynn Forest'):", -210, 30, false)

    -- X coordinate
    local xLabel = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    xLabel:SetPoint("TOPLEFT", 20, -260)
    xLabel:SetText("X Coordinate (0-100):")

    xEdit = CreateFrame("EditBox", nil, editFrame, "InputBoxTemplate")
    xEdit:SetPoint("TOPLEFT", 160, -262)
    xEdit:SetWidth(100)
    xEdit:SetHeight(30)
    xEdit:SetAutoFocus(false)
    xEdit:SetNumeric(true)
    xEdit:SetMaxLetters(5)

    -- Y coordinate
    local yLabel = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    yLabel:SetPoint("TOPLEFT", 280, -260)
    yLabel:SetText("Y:")

    yEdit = CreateFrame("EditBox", nil, editFrame, "InputBoxTemplate")
    yEdit:SetPoint("TOPLEFT", 310, -262)
    yEdit:SetWidth(100)
    yEdit:SetHeight(30)
    yEdit:SetAutoFocus(false)
    yEdit:SetNumeric(true)
    yEdit:SetMaxLetters(5)

    -- Save button
    local saveBtn = CreateFrame("Button", nil, editFrame, "UIPanelButtonTemplate")
    saveBtn:SetPoint("BOTTOM", -80, 20)
    saveBtn:SetWidth(120)
    saveBtn:SetHeight(30)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        RPMClues_SaveClue()
    end)

    -- Delete button
    local deleteBtn = CreateFrame("Button", nil, editFrame, "UIPanelButtonTemplate")
    deleteBtn:SetPoint("BOTTOM", 80, 20)
    deleteBtn:SetWidth(120)
    deleteBtn:SetHeight(30)
    deleteBtn:SetText("Delete")
    deleteBtn:SetScript("OnClick", function()
        RPMClues_DeleteClue()
    end)
    editFrame.deleteBtn = deleteBtn
end

-- ============================================================================
-- RPMClues_OpenEditForm() - Open edit dialog
-- ============================================================================
function RPMClues_OpenEditForm(clue)
    currentEditingClue = clue

    if clue then
        nameEdit:SetText(clue.name or "")
        descEdit:SetText(clue.description or "")
        zoneEdit:SetText(clue.zone or "")
        xEdit:SetText(tostring(clue.x or 50))
        yEdit:SetText(tostring(clue.y or 50))

        nameEdit:HighlightText(0, 0)
        editFrame.deleteBtn:Show()
    else
        nameEdit:SetText("")
        descEdit:SetText("")
        zoneEdit:SetText("")
        xEdit:SetText("50")
        yEdit:SetText("50")
        editFrame.deleteBtn:Hide()
    end

    editFrame:Show()
    editFrame:Raise()
end

-- ============================================================================
-- RPMClues_SaveClue() - Save clue to database
-- ============================================================================
function RPMClues_SaveClue()
    -- Initialize database if needed
    if not RPMasterDB then
        RPMasterDB = {}
    end
    if not RPMasterDB.clueLibrary then
        RPMasterDB.clueLibrary = {}
    end
    if not RPMasterDB.nextClueID then
        RPMasterDB.nextClueID = 1
    end

    local name = nameEdit:GetText()
    local description = descEdit:GetText()
    local zone = zoneEdit:GetText()
    local x = tonumber(xEdit:GetText()) or 50
    local y = tonumber(yEdit:GetText()) or 50

    if name == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Clue name is required!", 1, 0, 0)
        return
    end

    -- Validate coordinates
    if x < 0 then x = 0 end
    if x > 100 then x = 100 end
    if y < 0 then y = 0 end
    if y > 100 then y = 100 end

    if currentEditingClue then
        -- Update existing clue
        local clueID = currentEditingClue.id
        if RPMasterDB.clueLibrary[clueID] then
            RPMasterDB.clueLibrary[clueID].name = name
            RPMasterDB.clueLibrary[clueID].description = description
            RPMasterDB.clueLibrary[clueID].zone = zone
            RPMasterDB.clueLibrary[clueID].x = x
            RPMasterDB.clueLibrary[clueID].y = y
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r Clue updated! ID: "..clueID, 0, 1, 0)
        end
    else
        -- Create new clue
        local newClue = {
            id = RPMasterDB.nextClueID,
            name = name,
            description = description,
            zone = zone,
            x = x,
            y = y,
            assignedTo = nil  -- Not assigned to anyone yet
        }
        RPMasterDB.clueLibrary[newClue.id] = newClue
        RPMasterDB.nextClueID = RPMasterDB.nextClueID + 1
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r Clue created! ID: "..newClue.id, 0, 1, 0)
    end

    currentEditingClue = nil
    editFrame:Hide()
    RPMClues_RefreshClueList()
end

-- ============================================================================
-- RPMClues_DeleteClue() - Delete clue from database
-- ============================================================================
function RPMClues_DeleteClue()
    if currentEditingClue then
        RPMasterDB.clueLibrary[currentEditingClue.id] = nil
        editFrame:Hide()
        RPMClues_RefreshClueList()
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8800[RPMaster]|r Clue deleted!", 1, 0.5, 0)
    end
end

-- ============================================================================
-- RPMClues_RefreshClueList() - Refresh the scrollable clue list
-- ============================================================================
function RPMClues_RefreshClueList()
    if not scrollChild then return end

    -- Initialize database
    if not RPMasterDB then
        RPMasterDB = {clueLibrary = {}, nextClueID = 1}
    end
    if not RPMasterDB.clueLibrary then
        RPMasterDB.clueLibrary = {}
    end

    -- Clean up old frames
    for i, child in ipairs({scrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    local yOffset = -10
    local clueCount = 0

    for id, clue in pairs(RPMasterDB.clueLibrary) do
        clueCount = clueCount + 1

        local clueFrame = CreateFrame("Frame", nil, scrollChild)
        clueFrame:SetWidth(720)
        clueFrame:SetHeight(60)
        clueFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)

        -- Background
        local bg = clueFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(0.1, 0.1, 0.1, 0.5)

        -- Clue icon (treasure chest)
        local iconTex = clueFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetWidth(40)
        iconTex:SetHeight(40)
        iconTex:SetPoint("LEFT", 5, 0)
        iconTex:SetTexture("Interface\\Icons\\INV_Misc_Map_01")

        -- Clue name
        local nameText = clueFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        nameText:SetPoint("TOPLEFT", iconTex, "TOPRIGHT", 10, 0)
        nameText:SetText(clue.name)

        -- Zone and coordinates
        local locationText = clueFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        locationText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -5)
        locationText:SetTextColor(0.7, 0.7, 0.7)
        local locStr = string.format("%s (%.1f, %.1f)", clue.zone or "Unknown", clue.x or 0, clue.y or 0)
        locationText:SetText(locStr)

        -- Assigned status
        local assignText = clueFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        assignText:SetPoint("TOPLEFT", locationText, "BOTTOMLEFT", 0, -3)
        if clue.assignedTo then
            assignText:SetText("Assigned to: " .. clue.assignedTo)
            assignText:SetTextColor(0, 1, 0)
        else
            assignText:SetText("Not assigned")
            assignText:SetTextColor(0.5, 0.5, 0.5)
        end

        -- Edit button
        local editBtn = CreateFrame("Button", nil, clueFrame, "UIPanelButtonTemplate")
        editBtn:SetPoint("RIGHT", -120, 0)
        editBtn:SetWidth(80)
        editBtn:SetHeight(25)
        editBtn:SetText("Edit")
        do
            local clueToEdit = clue
            editBtn:SetScript("OnClick", function()
                RPMClues_OpenEditForm(clueToEdit)
            end)
        end

        -- Assign button
        local assignBtn = CreateFrame("Button", nil, clueFrame, "UIPanelButtonTemplate")
        assignBtn:SetPoint("RIGHT", -30, 0)
        assignBtn:SetWidth(80)
        assignBtn:SetHeight(25)
        assignBtn:SetText("Assign")
        do
            local clueToAssign = clue
            assignBtn:SetScript("OnClick", function()
                RPMClues_ShowPlayerSelector(clueToAssign)
            end)
        end

        yOffset = yOffset - 70
    end

    -- Update scroll height
    local totalHeight = math.max(1, clueCount * 70 + 20)
    scrollChild:SetHeight(totalHeight)

    local viewHeight = scrollFrame:GetHeight() or 0
    local max = totalHeight - viewHeight
    if max < 0 then max = 0 end
    slider:SetMinMaxValues(0, max)
    slider:SetValue(0)
end

-- Give Clue Frame (for player selection)
local giveClueFrame = nil
local currentAssignClue = nil

-- ============================================================================
-- RPMClues_ShowPlayerSelector() - Show dialog to assign clue to player
-- ============================================================================
function RPMClues_ShowPlayerSelector(clue)
    currentAssignClue = clue

    -- Create frame if it doesn't exist
    if not giveClueFrame then
        giveClueFrame = CreateFrame("Frame", "RPMasterGiveClueFrame", UIParent)
        giveClueFrame:SetWidth(400)
        giveClueFrame:SetHeight(250)
        giveClueFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        giveClueFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })
        giveClueFrame:SetBackdropColor(0, 0, 0, 1)
        giveClueFrame:SetMovable(true)
        giveClueFrame:SetFrameStrata("DIALOG")
        giveClueFrame:EnableMouse(true)

        -- Title
        local title = giveClueFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -15)
        title:SetText("Assign Clue to Player")

        -- Clue name label
        local clueLabel = giveClueFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        clueLabel:SetPoint("TOPLEFT", 20, -50)
        clueLabel:SetText("Clue:")

        local clueName = giveClueFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        clueName:SetPoint("LEFT", clueLabel, "RIGHT", 5, 0)
        clueName:SetText("")
        giveClueFrame.clueName = clueName

        -- Player dropdown label
        local playerLabel = giveClueFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        playerLabel:SetPoint("TOPLEFT", 20, -85)
        playerLabel:SetText("Player:")

        -- Player dropdown
        local playerDropdown = CreateFrame("Frame", "RPMGiveCluePlayerDropdown", giveClueFrame, "UIDropDownMenuTemplate")
        playerDropdown:SetPoint("TOPLEFT", 70, -80)
        UIDropDownMenu_SetWidth(280, playerDropdown)  -- WoW 1.12: width first, then dropdown
        giveClueFrame.playerDropdown = playerDropdown

        -- Assign button
        local assignBtn = CreateFrame("Button", nil, giveClueFrame, "UIPanelButtonTemplate")
        assignBtn:SetWidth(100)
        assignBtn:SetHeight(25)
        assignBtn:SetPoint("BOTTOMRIGHT", -20, 15)
        assignBtn:SetText("Assign")
        assignBtn:SetScript("OnClick", function()
            local selectedPlayer = UIDropDownMenu_GetText(playerDropdown)
            if selectedPlayer and selectedPlayer ~= "" then
                RPMClues_AssignClueToPlayer(currentAssignClue, selectedPlayer)
                giveClueFrame:Hide()
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Please select a player!", 1, 0, 0)
            end
        end)

        -- Cancel button
        local cancelBtn = CreateFrame("Button", nil, giveClueFrame, "UIPanelButtonTemplate")
        cancelBtn:SetWidth(100)
        cancelBtn:SetHeight(25)
        cancelBtn:SetPoint("RIGHT", assignBtn, "LEFT", -10, 0)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function()
            giveClueFrame:Hide()
        end)

        -- Close button
        local closeBtn = CreateFrame("Button", nil, giveClueFrame, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)
    end

    -- Update clue name
    giveClueFrame.clueName:SetText(clue.name)

    -- Populate dropdown with raid members
    UIDropDownMenu_Initialize(giveClueFrame.playerDropdown, function()
        if GetNumRaidMembers() > 0 then
            for i = 1, GetNumRaidMembers() do
                local name = GetRaidRosterInfo(i)
                if name then
                    local info = {}
                    info.text = name
                    info.value = name
                    do
                        local playerName = name
                        info.func = function()
                            UIDropDownMenu_SetSelectedValue(giveClueFrame.playerDropdown, playerName)
                            UIDropDownMenu_SetText(playerName, giveClueFrame.playerDropdown)
                        end
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end
        elseif GetNumPartyMembers() > 0 then
            for i = 1, GetNumPartyMembers() do
                local name = UnitName("party"..i)
                if name then
                    local info = {}
                    info.text = name
                    info.value = name
                    do
                        local playerName = name
                        info.func = function()
                            UIDropDownMenu_SetSelectedValue(giveClueFrame.playerDropdown, playerName)
                            UIDropDownMenu_SetText(playerName, giveClueFrame.playerDropdown)
                        end
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end
        else
            local info = {}
            info.text = "No raid or party members"
            info.disabled = 1
            UIDropDownMenu_AddButton(info)
        end
    end)

    UIDropDownMenu_SetText("Select player...", giveClueFrame.playerDropdown)
    giveClueFrame:Show()
end

-- ============================================================================
-- RPMClues_AssignClueToPlayer() - Assign clue to specific player
-- ============================================================================
function RPMClues_AssignClueToPlayer(clue, playerName)
    if RPMasterDB.clueLibrary[clue.id] then
        RPMasterDB.clueLibrary[clue.id].assignedTo = playerName
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF00FF00[RPMaster]|r Clue '%s' assigned to %s", clue.name, playerName), 0, 1, 0)
        -- TODO: Send message to player
        RPMClues_RefreshClueList()
    end
end

-- ============================================================================
-- MODULE LIFECYCLE CALLBACKS
-- ============================================================================

function RPMClues_Show()
    RPMClues_RefreshClueList()
end

function RPMClues_Hide()
    -- Nothing to do
end

-- ============================================================================
-- MODULE REGISTRATION
-- ============================================================================
RPM_RegisterModule("clues", {
    createContent = RPMClues_CreateContent,
    onShow = RPMClues_Show,
    onHide = RPMClues_Hide
})

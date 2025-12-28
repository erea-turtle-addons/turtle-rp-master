-- ============================================================================
-- ItemLibrary.lua - Item Library module for RPMaster
-- ============================================================================
-- PURPOSE: Provides item creation, editing, and distribution functionality
--          This is a plugin module that registers itself with Core.lua
--
-- FEATURES:
--   - Create/Edit/Delete RP items (notes, letters, quest objects)
--   - Visual icon picker with 100+ WoW icons
--   - Scrollable item library list
--   - Send items to players via addon messages
--   - Custom message support when giving items
--
-- ARCHITECTURE:
--   - Registers with Core via RPM_RegisterModule() at end of file
--   - Creates UI lazily when tab is first shown
--   - Uses SendAddonMessage() for player-to-player communication
--
-- DATA MODEL:
--   Item = {
--     id: number (unique, auto-incrementing)
--     guid: string (globally unique: "timestamp-random-id")
--     name: string (display name)
--     icon: string (texture path)
--     tooltip: string (short description, max 120 chars)
--     content: string (full text content, unlimited)
--   }
-- ============================================================================

-- Import shared business logic from turtle-rp-common
local objectDatabase = RequireObjectDatabase()
local rpBusiness = RequireRPBusiness()
local encoding = RequireEncoding()
local messaging = RequireMessaging()
local rpActions = RequireRPActions()

local ADDON_PREFIX = messaging.ADDON_PREFIX  -- Use constant from messaging module

-- ============================================================================
-- Log() - Local logging function wrapper
-- ============================================================================
-- Calls global RPMasterDebugLog from Core.lua
-- Local function pattern allows this module to work independently
-- ============================================================================
local function Log(message)
    if RPMasterDebugLog then
        local timestamp = date("%H:%M:%S")
        local logEntry = string.format("[%s] RPMaster: %s", timestamp, tostring(message))
        table.insert(RPMasterDebugLog, logEntry)
        if table.getn(RPMasterDebugLog) > 500 then
            table.remove(RPMasterDebugLog, 1)
        end
    end
end

-- ============================================================================
-- LOCAL VARIABLES (Module state)
-- ============================================================================
-- These are module-level private variables (like class fields in Java)
-- 'local' = file-scoped (not accessible from other files)
-- ============================================================================
local itemsContent = nil       -- Main content frame for this module
local scrollFrame = nil        -- Scrollable area for item list
local scrollChild = nil        -- Child frame inside scrollFrame (holds item rows)
local slider = nil             -- Scrollbar widget
local editFrame = nil          -- Item edit dialog (popup window)
local iconPickerFrame = nil    -- Icon picker dialog (popup window)

-- ============================================================================
-- EDIT FORM STATE
-- ============================================================================
local nameEdit, iconEdit, tooltipEdit, contentEdit, contentTemplateEdit  -- EditBox widgets
local currentEditingItem = nil  -- Item being edited (nil = creating new)
currentItemActions = {}  -- GLOBAL: Actions for current item being edited (v0.2.0: multi-method)
                         -- Global so ActionEditor.lua can access it
local actionsListFrame = nil  -- Frame to display action list

-- ============================================================================
-- GenerateGUID() - Create globally unique identifier (delegated to object-database)
-- ============================================================================
-- @param name: string - Item name used for checksum generation
-- @returns: String in format "timestamp-random-checksum"
--
-- WHY GUID?
--   - Multiple GMs might create items with same ID
--   - Players can receive same item multiple times
--   - GUID ensures we can distinguish between duplicate items
--
-- FORMAT: "1234567890-98772240-661d3cc5"
--   - timestamp: Unix epoch seconds
--   - random: 8-digit random number (prevents collisions within same second)
--   - checksum: FNV-1 hash of name (ensures uniqueness)
--
-- SIMILAR TO: UUID.randomUUID() in Java, Guid.NewGuid() in C#
-- ============================================================================
local function GenerateGUID(name)
    return objectDatabase.GenerateGUID(name)
end

-- ============================================================================
-- RPMItems_CreateContent() - Create the Items tab UI
-- ============================================================================
-- @param parent: Frame - Parent frame from Core (contentFrame)
-- @returns: Frame - The created UI frame
--
-- CALLED BY: Core.lua when Items tab is first shown (lazy loading)
--
-- UI STRUCTURE:
--   itemsContent (main container)
--   ├── scrollFrame (scrollable area)
--   │   ├── scrollChild (content container, dynamically sized)
--   │   │   └── [Item rows created dynamically]
--   │   └── slider (scrollbar)
--   ├── New Item button
--   └── Refresh button
--
-- SCROLLFRAME PATTERN:
--   1. Create ScrollFrame (viewport)
--   2. Create child Frame (content, can be larger than viewport)
--   3. SetScrollChild() to link them
--   4. Add slider for manual scrolling
--   5. Handle mouse wheel events
--
-- SIMILAR TO: JScrollPane in Java, overflow:scroll in CSS
-- ============================================================================
function RPMItems_CreateContent(parent)
    -- Main container frame (fills parent)
    itemsContent = CreateFrame("Frame", "RPMItemsContent", parent)
    itemsContent:SetAllPoints()  -- Anchor to all 4 corners of parent

    -- Scrollable item list
    scrollFrame = CreateFrame("ScrollFrame", "RPMItemsScrollFrame", itemsContent)
    scrollFrame:SetPoint("TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 60)  -- Leave room for scrollbar (right) and buttons (bottom)
    scrollFrame:EnableMouseWheel(true)  -- Allow mouse wheel scrolling

    -- Scroll slider (create BEFORE setting up scroll child)
    slider = CreateFrame("Slider", "RPMItemsScrollBar", scrollFrame, "UIPanelScrollBarTemplate")
    slider:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 4, -16)
    slider:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4, 16)
    slider:SetMinMaxValues(0, 100)
    slider:SetValueStep(1)
    slider:SetValue(0)
    slider:SetWidth(16)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(600)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Link scrollbar position to scroll offset
    -- Lua 5.0: Use arg1 for offset parameter
    scrollFrame:SetScript("OnVerticalScroll", function()
        local offset = arg1  -- Lua 5.0: arg1 is the offset parameter
        slider:SetValue(offset)  -- Update scrollbar when content scrolls
    end)

    -- Mouse wheel script
    -- Lua 5.0: Use arg1 for delta parameter
    scrollFrame:SetScript("OnMouseWheel", function()
        local delta = arg1  -- Lua 5.0: arg1 is scroll delta
        local current = slider:GetValue()
        local minVal, maxVal = slider:GetMinMaxValues()
        if delta > 0 then
            slider:SetValue(math.max(minVal, current - 20))
        else
            slider:SetValue(math.min(maxVal, current + 20))
        end
    end)

    -- Link slider to scroll position
    -- Lua 5.0: Use arg1 for value parameter
    slider:SetScript("OnValueChanged", function()
        local value = arg1  -- Lua 5.0: arg1 is the new value
        scrollFrame:SetVerticalScroll(value)
    end)

    -- Action buttons
    local newItemBtn = CreateFrame("Button", nil, itemsContent, "UIPanelButtonTemplate")
    newItemBtn:SetPoint("BOTTOMLEFT", 10, 10)
    newItemBtn:SetWidth(150)
    newItemBtn:SetHeight(30)
    newItemBtn:SetText("New Item")
    newItemBtn:SetScript("OnClick", function()
        RPMItems_OpenEditForm(nil)
    end)

    local refreshBtn = CreateFrame("Button", nil, itemsContent, "UIPanelButtonTemplate")
    refreshBtn:SetPoint("BOTTOMLEFT", 170, 10)
    refreshBtn:SetWidth(150)
    refreshBtn:SetHeight(30)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        RPMItems_RefreshItemList()
    end)

    -- ========================================================================
    -- DATABASE SECTION - Name and commit controls
    -- ========================================================================
    -- DESIGN:
    --   - Database name identifies this RPMaster's item collection
    --   - Supports multiple RPMasters running different campaigns
    --   - Players can sync to specific database by name
    --   - "Commit" creates snapshot for syncing (uncommitted edits not synced)
    -- ========================================================================

    -- Database label
    local dbLabel = itemsContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dbLabel:SetPoint("BOTTOMLEFT", 340, 15)
    dbLabel:SetText("Database:")

    -- Database name input field
    -- PURPOSE: User-friendly name for this item collection (e.g., "Dragon Campaign", "Winter Event")
    local dbNameEdit = CreateFrame("EditBox", nil, itemsContent, "InputBoxTemplate")
    dbNameEdit:SetPoint("BOTTOMLEFT", 410, 13)
    dbNameEdit:SetWidth(140)
    dbNameEdit:SetHeight(25)
    dbNameEdit:SetAutoFocus(false)
    dbNameEdit:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    dbNameEdit:SetScript("OnEditFocusLost", function()
        -- Save database name when focus lost
        if not RPMasterDB then RPMasterDB = {} end
        RPMasterDB.databaseName = this:GetText()
    end)
    itemsContent.dbNameEdit = dbNameEdit

    -- Commit Database button
    -- PURPOSE: Creates snapshot of current itemLibrary
    local commitBtn = CreateFrame("Button", nil, itemsContent, "UIPanelButtonTemplate")
    commitBtn:SetPoint("LEFT", dbNameEdit, "RIGHT", 10, 0)
    commitBtn:SetWidth(100)
    commitBtn:SetHeight(25)
    commitBtn:SetText("Commit DB")
    commitBtn:SetScript("OnClick", function()
        RPMItems_CommitDatabase()
    end)

    -- Sync to Raid button (NEW: sends committed database to all players)
    -- PURPOSE: Synchronize committed database with raid members
    -- WORKFLOW: Players receive database once, then GIVE messages only send GUID
    local syncBtn = CreateFrame("Button", nil, itemsContent, "UIPanelButtonTemplate")
    syncBtn:SetPoint("LEFT", commitBtn, "RIGHT", 5, 0)
    syncBtn:SetWidth(100)
    syncBtn:SetHeight(25)
    syncBtn:SetText("Sync to Raid")
    syncBtn:SetScript("OnClick", function()
        RPMItems_SyncDatabaseToRaid()
    end)

    -- Create edit frame and icon picker (child windows)
    RPMItems_CreateEditFrame()
    RPMItems_CreateIconPicker()

    return itemsContent
end

-- Function: Create edit form
function RPMItems_CreateEditFrame()
    editFrame = CreateFrame("Frame", "RPMItemsEditFrame", UIParent)
    editFrame:SetWidth(650)  -- Wider to accommodate content template columns
    editFrame:SetHeight(600)  -- Content at bottom can overflow down
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

    local editTitle = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    editTitle:SetPoint("TOP", 0, -15)
    editTitle:SetText("Edit RP Item")

    local editCloseBtn = CreateFrame("Button", nil, editFrame, "UIPanelCloseButton")
    editCloseBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Edit fields
    local function CreateEditBox(parent, label, yOffset, height, multiline)
        local labelText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelText:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
        labelText:SetText(label)

        local editBox
        if multiline then
            -- Create container frame for clipping
            local container = CreateFrame("Frame", nil, parent)
            container:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset - 20)
            container:SetWidth(440)
            container:SetHeight(height)

            local bg = container:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(container)
            bg:SetTexture(0, 0, 0, 0.5)

            editBox = CreateFrame("EditBox", nil, container)
            editBox:SetMultiLine(true)
            editBox:SetAutoFocus(false)
            editBox:SetFontObject(GameFontHighlight)
            editBox:SetPoint("TOPLEFT", 5, -5)
            editBox:SetPoint("BOTTOMRIGHT", -5, 5)
            editBox:EnableMouse(true)
            editBox:SetMaxLetters(0)

            -- Critical: Set text insets to prevent overflow
            editBox:SetTextInsets(5, 5, 5, 5)

            -- Enable internal scrolling with arrow keys
            editBox:SetAltArrowKeyMode(false)

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

    nameEdit = CreateEditBox(editFrame, "Item name:", -50, 30, false)
    iconEdit = CreateEditBox(editFrame, "Icon (texture):", -100, 30, false)
    iconEdit:SetWidth(320)
    iconEdit:SetText("Interface\\Icons\\INV_Misc_Note_01")

    -- Icon preview display
    local iconPreviewFrame = CreateFrame("Frame", nil, editFrame)
    iconPreviewFrame:SetPoint("LEFT", iconEdit, "RIGHT", 130, 0)
    iconPreviewFrame:SetWidth(40)
    iconPreviewFrame:SetHeight(40)

    local iconPreviewBg = iconPreviewFrame:CreateTexture(nil, "BACKGROUND")
    iconPreviewBg:SetAllPoints()
    iconPreviewBg:SetTexture("Interface\\Buttons\\UI-EmptySlot")

    local iconPreview = iconPreviewFrame:CreateTexture(nil, "ARTWORK")
    iconPreview:SetWidth(36)
    iconPreview:SetHeight(36)
    iconPreview:SetPoint("CENTER", 0, 0)
    iconPreview:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    editFrame.iconPreview = iconPreview

    -- Update preview when icon path changes
    iconEdit:SetScript("OnTextChanged", function()
        local iconPath = iconEdit:GetText()
        if iconPath and iconPath ~= "" then
            iconPreview:SetTexture(iconPath)
        end
    end)

    tooltipEdit = CreateEditBox(editFrame, "Tooltip (short description):", -150, 60, true)
    tooltipEdit:SetMaxLetters(120)

    -- Initial counter field
    local counterLabel = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    counterLabel:SetPoint("TOPLEFT", editFrame, "TOPLEFT", 20, -220)
    counterLabel:SetText("Initial counter (optional, 0 = none):")

    initialCounterEdit = CreateFrame("EditBox", nil, editFrame, "InputBoxTemplate")
    initialCounterEdit:SetPoint("TOPLEFT", editFrame, "TOPLEFT", 240, -220 - 2)
    initialCounterEdit:SetWidth(60)
    initialCounterEdit:SetHeight(25)
    initialCounterEdit:SetAutoFocus(false)
    initialCounterEdit:SetNumeric(true)
    initialCounterEdit:SetText("0")

    -- Save button - positioned at top-right, below title
    local saveBtn = CreateFrame("Button", nil, editFrame, "UIPanelButtonTemplate")
    saveBtn:SetPoint("TOPRIGHT", -15, -45)
    saveBtn:SetWidth(100)
    saveBtn:SetHeight(25)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        RPMItems_SaveItem()
    end)

    -- Delete button - positioned next to save button
    local deleteBtn = CreateFrame("Button", nil, editFrame, "UIPanelButtonTemplate")
    deleteBtn:SetPoint("RIGHT", saveBtn, "LEFT", -10, 0)
    deleteBtn:SetWidth(100)
    deleteBtn:SetHeight(25)
    deleteBtn:SetText("Delete")
    deleteBtn:SetScript("OnClick", function()
        RPMItems_DeleteItem()
    end)
    editFrame.deleteBtn = deleteBtn

    -- Icon picker button
    local iconPickerBtn = CreateFrame("Button", nil, editFrame, "UIPanelButtonTemplate")
    iconPickerBtn:SetPoint("LEFT", iconEdit, "RIGHT", 10, 0)
    iconPickerBtn:SetWidth(100)
    iconPickerBtn:SetHeight(22)
    iconPickerBtn:SetText("Choose Icon")
    iconPickerBtn:SetScript("OnClick", function()
        RPMItems_OpenIconPicker()
    end)

    -- Actions section
    local actionsLabel = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    actionsLabel:SetPoint("TOPLEFT", editFrame, "TOPLEFT", 20, -260)
    actionsLabel:SetText("Actions:")

    -- Actions list frame
    actionsListFrame = CreateFrame("Frame", nil, editFrame)
    actionsListFrame:SetPoint("TOPLEFT", editFrame, "TOPLEFT", 20, -280)
    actionsListFrame:SetWidth(590)  -- Wider to match new frame width
    actionsListFrame:SetHeight(80)

    local actionsListBg = actionsListFrame:CreateTexture(nil, "BACKGROUND")
    actionsListBg:SetAllPoints(actionsListFrame)
    actionsListBg:SetTexture(0, 0, 0, 0.5)

    editFrame.actionsListFrame = actionsListFrame

    -- Add Action button
    local addActionBtn = CreateFrame("Button", nil, editFrame, "UIPanelButtonTemplate")
    addActionBtn:SetPoint("TOPLEFT", actionsListFrame, "BOTTOMLEFT", 0, -5)
    addActionBtn:SetWidth(100)
    addActionBtn:SetHeight(22)
    addActionBtn:SetText("Add Action")
    addActionBtn:SetScript("OnClick", function()
        -- v0.2.0: Use new multi-method ActionEditor (works with currentItemActions)
        RPMActionEditor_Show(nil)  -- nil = new action
    end)

    -- Content fields at BOTTOM of form (two columns with copy buttons)
    -- Left column: Default Content
    local contentLabel = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    contentLabel:SetPoint("TOPLEFT", editFrame, "TOPLEFT", 20, -380)
    contentLabel:SetText("Default content:")

    local contentContainer = CreateFrame("Frame", nil, editFrame)
    contentContainer:SetPoint("TOPLEFT", editFrame, "TOPLEFT", 20, -400)
    contentContainer:SetWidth(260)  -- Wider for better readability
    contentContainer:SetHeight(200)

    local contentBg = contentContainer:CreateTexture(nil, "BACKGROUND")
    contentBg:SetAllPoints(contentContainer)
    contentBg:SetTexture(0, 0, 0, 0.5)

    contentEdit = CreateFrame("EditBox", nil, contentContainer)
    contentEdit:SetMultiLine(true)
    contentEdit:SetAutoFocus(false)
    contentEdit:SetFontObject(GameFontHighlight)
    contentEdit:SetPoint("TOPLEFT", 5, -5)
    contentEdit:SetPoint("BOTTOMRIGHT", -5, 5)
    contentEdit:EnableMouse(true)
    contentEdit:SetMaxLetters(0)
    contentEdit:SetTextInsets(5, 5, 5, 5)
    contentEdit:SetAltArrowKeyMode(false)
    contentEdit:SetScript("OnEscapePressed", function() this:ClearFocus() end)

    -- Copy button: Content → Template
    local copyRightBtn = CreateFrame("Button", nil, editFrame, "UIPanelButtonTemplate")
    copyRightBtn:SetPoint("LEFT", contentContainer, "RIGHT", 5, 0)
    copyRightBtn:SetWidth(35)
    copyRightBtn:SetHeight(25)
    copyRightBtn:SetText("->")  -- ASCII arrow (Unicode doesn't work in WoW 1.12)
    copyRightBtn:SetScript("OnClick", function()
        if contentTemplateEdit then
            contentTemplateEdit:SetText(contentEdit:GetText())
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r Copied to template", 0, 1, 0)
        end
    end)

    -- Copy button: Template → Content
    local copyLeftBtn = CreateFrame("Button", nil, editFrame, "UIPanelButtonTemplate")
    copyLeftBtn:SetPoint("TOP", copyRightBtn, "BOTTOM", 0, -5)
    copyLeftBtn:SetWidth(35)
    copyLeftBtn:SetHeight(25)
    copyLeftBtn:SetText("<-")  -- ASCII arrow (Unicode doesn't work in WoW 1.12)
    copyLeftBtn:SetScript("OnClick", function()
        if contentTemplateEdit then
            contentEdit:SetText(contentTemplateEdit:GetText())
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r Copied to default", 0, 1, 0)
        end
    end)

    -- Right column: Content Template
    local templateLabel = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    templateLabel:SetPoint("LEFT", contentLabel, "LEFT", 335, 0)  -- Same Y as contentLabel, offset by column width
    templateLabel:SetText("Template (use {custom-text}):")

    local templateContainer = CreateFrame("Frame", nil, editFrame)
    templateContainer:SetPoint("LEFT", contentContainer, "LEFT", 335, 0)  -- Same Y as contentContainer, offset by column width
    templateContainer:SetWidth(260)  -- Wider for better readability
    templateContainer:SetHeight(200)

    local templateBg = templateContainer:CreateTexture(nil, "BACKGROUND")
    templateBg:SetAllPoints(templateContainer)
    templateBg:SetTexture(0, 0, 0, 0.5)

    contentTemplateEdit = CreateFrame("EditBox", nil, templateContainer)
    contentTemplateEdit:SetMultiLine(true)
    contentTemplateEdit:SetAutoFocus(false)
    contentTemplateEdit:SetFontObject(GameFontHighlight)
    contentTemplateEdit:SetPoint("TOPLEFT", 5, -5)
    contentTemplateEdit:SetPoint("BOTTOMRIGHT", -5, 5)
    contentTemplateEdit:EnableMouse(true)
    contentTemplateEdit:SetMaxLetters(0)
    contentTemplateEdit:SetTextInsets(5, 5, 5, 5)
    contentTemplateEdit:SetAltArrowKeyMode(false)
    contentTemplateEdit:SetScript("OnEscapePressed", function() this:ClearFocus() end)
end

local function RPMItems_UpdateScrollRange()
    if not scrollFrame or not scrollChild or not slider then return end

    -- Met à jour les dimensions internes
    scrollFrame:UpdateScrollChildRect()

    -- Hauteur visible
    local viewHeight = scrollFrame:GetHeight() or 0
    -- Hauteur du contenu
    local contentHeight = scrollChild:GetHeight() or 0

    -- Distance totale scrollable (jamais négative)
    local max = contentHeight - viewHeight
    if max < 0 then max = 0 end

    slider:SetMinMaxValues(0, max)

    -- Optionnel : remet en haut à chaque refresh
    if slider:GetValue() > max then
        slider:SetValue(max)
    end
end


-- ============================================================================
-- ICON LIST (Loaded from icon-list.lua)
-- ============================================================================
-- Icon list is now maintained in separate icon-list.lua file
-- Total: 1420 WoW 1.12 icons
-- ============================================================================
local iconList = nil  -- Will be loaded from icon-list.lua
local currentIconFilter = ""  -- Text filter for icon search

-- Function: Create icon picker
function RPMItems_CreateIconPicker()
    iconPickerFrame = CreateFrame("Frame", "RPMItemsIconPicker", UIParent)
    iconPickerFrame:SetWidth(480)
    iconPickerFrame:SetHeight(600)
    iconPickerFrame:SetPoint("TOP", UIParent, "TOP", 0, -50)  -- Position at top of screen
    iconPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")  -- Higher z-index to render above other dialogs
    iconPickerFrame:SetBackdrop({
        bgFile = "Interface\\AddOns\\turtle-rp-master\\black",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    iconPickerFrame:SetBackdropColor(0, 0, 0, 1)  -- Fully black background
    iconPickerFrame:SetMovable(true)
    iconPickerFrame:EnableMouse(true)
    iconPickerFrame:RegisterForDrag("LeftButton")
    iconPickerFrame:SetScript("OnDragStart", iconPickerFrame.StartMoving)
    iconPickerFrame:SetScript("OnDragStop", iconPickerFrame.StopMovingOrSizing)
    iconPickerFrame:Hide()

    local pickerTitle = iconPickerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pickerTitle:SetPoint("TOP", 0, -20)
    pickerTitle:SetText("Choose Icon (1420 icons)")

    local pickerCloseBtn = CreateFrame("Button", nil, iconPickerFrame, "UIPanelCloseButton")
    pickerCloseBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Text filter input (positioned below title)
    local filterLabel = iconPickerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filterLabel:SetPoint("TOPLEFT", 20, -50)
    filterLabel:SetText("Filter (e.g., book, sword, ring):")

    local filterEdit = CreateFrame("EditBox", nil, iconPickerFrame, "InputBoxTemplate")
    filterEdit:SetPoint("TOPLEFT", filterLabel, "BOTTOMLEFT", 0, -5)
    filterEdit:SetWidth(440)
    filterEdit:SetHeight(25)
    filterEdit:SetAutoFocus(false)
    filterEdit:SetScript("OnEnterPressed", function() this:ClearFocus() end)
    filterEdit:SetScript("OnTextChanged", function()
        -- Lua 5.0: Use arg1 to check if user typed (not programmatic)
        if arg1 then
            currentIconFilter = string.lower(filterEdit:GetText() or "")
            RPMItems_PopulateIconPicker()
        end
    end)
    iconPickerFrame.filterEdit = filterEdit

    -- Scrollable icon grid (positioned below filter)
    local iconScrollFrame = CreateFrame("ScrollFrame", "RPMItemsIconScrollFrame", iconPickerFrame, "UIPanelScrollFrameTemplate")
    iconScrollFrame:SetPoint("TOPLEFT", 20, -110)  -- Below filter (adjusted for filter on new line)
    iconScrollFrame:SetPoint("BOTTOMRIGHT", -40, 20)

    local iconScrollChild = CreateFrame("Frame", nil, iconScrollFrame)
    iconScrollChild:SetWidth(400)
    iconScrollChild:SetHeight(1)

    local scrollBg = iconScrollChild:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetAllPoints(iconScrollChild)
    scrollBg:SetTexture(0, 0, 0, 1)  -- Black background

    iconScrollFrame:SetScrollChild(iconScrollChild)
    iconPickerFrame.scrollChild = iconScrollChild
end

-- Function: Populate icon picker
function RPMItems_PopulateIconPicker()
    -- Load icon list if not already loaded
    if not iconList then
        iconList = RPMaster_GetIconList()
    end

    local iconScrollChild = iconPickerFrame.scrollChild

    -- Clean up old buttons
    for i, child in ipairs({iconScrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    -- Filter icons based on currentIconFilter
    local filteredIcons = {}
    for i = 1, table.getn(iconList) do
        local iconPath = iconList[i]
        -- Extract icon name from path (after last backslash)
        -- Lua 5.0: Use string.find to locate last backslash, then string.sub to extract name
        local lastSlash = 0
        local pos = 1
        while pos do
            pos = string.find(iconPath, "\\", pos, true)
            if pos then
                lastSlash = pos
                pos = pos + 1
            end
        end
        local iconName = string.sub(iconPath, lastSlash + 1)
        iconName = string.lower(iconName)

        -- Filter: show icon if filter is empty OR icon name contains filter text
        if currentIconFilter == "" or string.find(iconName, currentIconFilter, 1, true) then
            table.insert(filteredIcons, iconPath)
        end
    end

    local iconsPerRow = 7
    local iconSize = 40
    local spacing = 10
    local xOffset = 10
    local yOffset = -10

    for index, iconPath in ipairs(filteredIcons) do
        local col = math.mod(index - 1, iconsPerRow)
        local row = math.floor((index - 1) / iconsPerRow)

        local btn = CreateFrame("Button", nil, iconScrollChild)
        btn:SetWidth(iconSize)
        btn:SetHeight(iconSize)
        btn:SetPoint("TOPLEFT", xOffset + col * (iconSize + spacing), yOffset - row * (iconSize + spacing))

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\UI-EmptySlot")

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(iconSize - 4)
        icon:SetHeight(iconSize - 4)
        icon:SetPoint("CENTER", 0, 0)
        icon:SetTexture(iconPath)

        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        highlight:SetBlendMode("ADD")

        do
            local selectedIcon = iconPath
            btn:SetScript("OnClick", function()
                iconEdit:SetText(selectedIcon)
                iconPickerFrame:Hide()
            end)
        end

        btn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            if iconPath and iconPath ~= "" then
                GameTooltip:SetText(iconPath, 1, 1, 1)
            else
                GameTooltip:SetText("(No icon path)", 1, 1, 1)
            end
            GameTooltip:Show()
        end)

        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    local rowCount = math.ceil(table.getn(filteredIcons) / iconsPerRow)
    iconScrollChild:SetHeight(math.max(1, rowCount * (iconSize + spacing) + 20))
end

-- Function: Open icon picker
function RPMItems_OpenIconPicker()
    -- Reset filter when opening
    currentIconFilter = ""
    if iconPickerFrame.filterEdit then
        iconPickerFrame.filterEdit:SetText("")
    end

    RPMItems_PopulateIconPicker()
    iconPickerFrame:Show()
end

-- ============================================================================
-- ACTION MANAGEMENT FUNCTIONS (v0.2.0)
-- ============================================================================
-- Note: ActionEditor.lua provides the GUI for editing multi-method actions
-- This file only provides the actions list display
-- ============================================================================

-- Refresh actions list display
function RPMItems_RefreshActionsList()
    if not actionsListFrame then return end

    -- Clear existing widgets (buttons)
    local children = { actionsListFrame:GetChildren() }
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end

    -- Clear existing FontStrings (text labels)
    -- FontStrings are regions, not children, so need separate cleanup
    local regions = { actionsListFrame:GetRegions() }
    for _, region in ipairs(regions) do
        if region:GetObjectType() == "FontString" then
            region:Hide()
            region:SetParent(nil)
        end
    end

    -- Display each action
    local yOffset = -5
    for i = 1, table.getn(currentItemActions) do
        local action = currentItemActions[i]

        local actionText = actionsListFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        actionText:SetPoint("TOPLEFT", 5, yOffset)
        -- v0.2.0: Show number of methods instead of method type
        local methodCount = action.methods and table.getn(action.methods) or 0
        actionText:SetText(string.format("|cFFFFD700%d.|r %s |cFF888888(%d methods)|r", i, action.label, methodCount))

        -- Remove button
        local removeBtn = CreateFrame("Button", nil, actionsListFrame, "UIPanelButtonTemplate")
        removeBtn:SetPoint("TOPRIGHT", -5, yOffset + 2)
        removeBtn:SetWidth(60)
        removeBtn:SetHeight(18)
        removeBtn:SetText("Remove")

        -- Edit button
        local editBtn = CreateFrame("Button", nil, actionsListFrame, "UIPanelButtonTemplate")
        editBtn:SetPoint("RIGHT", removeBtn, "LEFT", -3, 0)
        editBtn:SetWidth(50)
        editBtn:SetHeight(18)
        editBtn:SetText("Edit")

        -- Lua 5.0: Capture index in closure
        do
            local actionIndex = i
            removeBtn:SetScript("OnClick", function()
                RPMItems_RemoveAction(actionIndex)
            end)

            editBtn:SetScript("OnClick", function()
                -- v0.2.0: Use new multi-method ActionEditor (works with currentItemActions)
                RPMActionEditor_Show(actionIndex)
            end)
        end

        yOffset = yOffset - 20
    end
end

-- Remove action
function RPMItems_RemoveAction(index)
    table.remove(currentItemActions, index)
    RPMItems_RefreshActionsList()
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r Action removed!", 0, 1, 0)
end

-- Function: Open edit form
function RPMItems_OpenEditForm(item)
    currentEditingItem = item

    if item then
        nameEdit:SetText(item.name or "")
        iconEdit:SetText(item.icon or "Interface\\Icons\\INV_Misc_Note_01")
        tooltipEdit:SetText(item.tooltip or "")
        contentEdit:SetText(item.content or "")
        contentTemplateEdit:SetText(item.contentTemplate or "")
        initialCounterEdit:SetText(tostring(item.initialCounter or 0))

        -- Update icon preview
        if editFrame.iconPreview then
            editFrame.iconPreview:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_Note_01")
        end

        nameEdit:HighlightText(0, 0)
        iconEdit:HighlightText(0, 0)

        -- Load actions
        currentItemActions = {}
        if item.actions then
            for i = 1, table.getn(item.actions) do
                table.insert(currentItemActions, item.actions[i])
            end
        end

        editFrame.deleteBtn:Show()
    else
        nameEdit:SetText("")
        iconEdit:SetText("Interface\\Icons\\INV_Misc_Note_01")
        tooltipEdit:SetText("")
        contentEdit:SetText("")
        contentTemplateEdit:SetText("")
        initialCounterEdit:SetText("0")

        -- Reset icon preview to default
        if editFrame.iconPreview then
            editFrame.iconPreview:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        end

        -- Clear actions for new item
        currentItemActions = {}

        editFrame.deleteBtn:Hide()
    end

    RPMItems_RefreshActionsList()
    editFrame:Show()
    editFrame:Raise()
end

-- Function: Save item
function RPMItems_SaveItem()
    -- Safety check
    if not RPMasterDB then
        RPMasterDB = {itemLibrary = {}, nextItemID = 1}
    end
    if not RPMasterDB.itemLibrary then
        RPMasterDB.itemLibrary = {}
    end
    if not RPMasterDB.nextItemID then
        RPMasterDB.nextItemID = 1
    end

    local name = nameEdit:GetText()
    local icon = iconEdit:GetText()
    local tooltip = tooltipEdit:GetText()
    local content = contentEdit:GetText()
    local contentTemplate = contentTemplateEdit:GetText()
    local initialCounter = tonumber(initialCounterEdit:GetText()) or 0

    if name == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Name is required!", 1, 0, 0)
        return
    end

    -- Validate field lengths (GUID-based protocol doesn't transmit these per-message)
    -- These limits ensure reasonable display sizes and database consistency

    -- Name validation: Max 50 characters for display
    if string.len(name) > 50 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Name too long! Max 50 characters (currently: " .. string.len(name) .. ")", 1, 0, 0)
        return
    end

    -- Tooltip validation: Max 120 characters (short description)
    if string.len(tooltip) > 120 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Tooltip too long! Max 120 characters (currently: " .. string.len(tooltip) .. ")", 1, 0, 0)
        return
    end

    -- Icon validation: Must start with "Interface\"
    if icon ~= "" and not string.find(icon, "^Interface\\") then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Icon path must start with 'Interface\\'", 1, 0, 0)
        return
    end

    -- Content has no size limit (stored in database, transmitted via chunked sync)
    Log("Item validation passed - Name: " .. string.len(name) .. " chars, Tooltip: " .. string.len(tooltip) .. " chars, Content: " .. string.len(content) .. " chars")

    if currentEditingItem then
        -- Update existing item
        local itemID = currentEditingItem.id

        if RPMasterDB.itemLibrary[itemID] then
            -- Update using objectDatabase pattern (regenerate GUID on name change)
            local guidToUse = RPMasterDB.itemLibrary[itemID].guid
            if RPMasterDB.itemLibrary[itemID].name ~= name or not guidToUse then
                guidToUse = GenerateGUID(name)
            end

            -- Use objectDatabase.CreateObject to ensure consistent structure
            RPMasterDB.itemLibrary[itemID] = objectDatabase.CreateObject(
                guidToUse,
                name,
                icon,
                tooltip,
                content,
                currentItemActions,
                contentTemplate,
                initialCounter
            )
            RPMasterDB.itemLibrary[itemID].id = itemID  -- Preserve ID for backward compatibility

            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r Item updated! ID: "..itemID, 0, 1, 0)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Error: Item ID "..itemID.." not found!", 1, 0, 0)
            return
        end
    else
        -- Create new item using objectDatabase.CreateObject
        local newItem = objectDatabase.CreateObject(
            nil,  -- Let CreateObject generate GUID
            name,
            icon,
            tooltip,
            content,
            currentItemActions,
            contentTemplate,
            initialCounter
        )
        newItem.id = RPMasterDB.nextItemID  -- Add ID for backward compatibility

        RPMasterDB.itemLibrary[newItem.id] = newItem
        RPMasterDB.nextItemID = RPMasterDB.nextItemID + 1
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r Item created! ID: "..newItem.id, 0, 1, 0)
    end

    currentEditingItem = nil
    currentItemActions = {}
    editFrame:Hide()
    RPMItems_RefreshItemList()
end

-- Function: Delete item
function RPMItems_DeleteItem()
    if currentEditingItem then
        RPMasterDB.itemLibrary[currentEditingItem.id] = nil
        editFrame:Hide()
        RPMItems_RefreshItemList()
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8800[RPMaster]|r Item deleted!", 1, 0.5, 0)
    end
end

-- Function: Revert item to committed version
function RPMItems_RevertItem(itemId)
    if not RPMasterDB or not RPMasterDB.committedDatabase or not RPMasterDB.committedDatabase.items then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r No committed database to revert to!", 1, 0, 0)
        return
    end

    local committedItem = RPMasterDB.committedDatabase.items[itemId]
    if not committedItem then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Item not found in committed database!", 1, 0, 0)
        return
    end

    -- Deep copy the committed item back to itemLibrary
    local revertedItem = {
        id = committedItem.id,
        guid = committedItem.guid,
        name = committedItem.name,
        icon = committedItem.icon,
        tooltip = committedItem.tooltip,
        content = committedItem.content,
        actions = {}
    }

    -- Deep copy actions
    if committedItem.actions then
        for i = 1, table.getn(committedItem.actions) do
            local action = committedItem.actions[i]
            table.insert(revertedItem.actions, {
                id = action.id,
                label = action.label,
                method = action.method,
                params = action.params
            })
        end
    end

    RPMasterDB.itemLibrary[itemId] = revertedItem
    RPMItems_RefreshItemList()
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r Item reverted to committed version: " .. revertedItem.name, 0, 1, 0)
end

-- Function: Refresh item list
function RPMItems_RefreshItemList()
    if not scrollChild then return end

    -- Safety check
    if not RPMasterDB then
        RPMasterDB = {itemLibrary = {}, nextItemID = 1}
    end
    if not RPMasterDB.itemLibrary then
        RPMasterDB.itemLibrary = {}
    end

    -- Clean up old buttons
    for i, child in ipairs({scrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    local yOffset = -10
    local itemCount = 0

    for id, item in pairs(RPMasterDB.itemLibrary) do
        itemCount = itemCount + 1

        -- Check if item is uncommitted (new or modified since last commit)
        local isUncommitted = false
        local committedItem = nil
        if RPMasterDB.committedDatabase and RPMasterDB.committedDatabase.items then
            -- Look for this item in committed database by ID (use pairs, not ipairs - it's a hash table!)
            committedItem = RPMasterDB.committedDatabase.items[item.id]

            if not committedItem then
                -- Item doesn't exist in committed database = new item
                isUncommitted = true
            else
                -- Item exists, check if modified (including actions)
                if committedItem.name ~= item.name or
                   committedItem.icon ~= item.icon or
                   committedItem.tooltip ~= item.tooltip or
                   committedItem.content ~= item.content or
                   committedItem.contentTemplate ~= item.contentTemplate or
                   committedItem.guid ~= item.guid then
                    isUncommitted = true
                else
                    -- Check if actions have changed
                    local currentActionsCount = item.actions and table.getn(item.actions) or 0
                    local committedActionsCount = committedItem.actions and table.getn(committedItem.actions) or 0

                    if currentActionsCount ~= committedActionsCount then
                        isUncommitted = true
                    else
                        -- Compare each action (v0.2.0: compare methods array)
                        for i = 1, currentActionsCount do
                            local currentAction = item.actions[i]
                            local committedAction = committedItem.actions[i]
                            if currentAction.id ~= committedAction.id or
                               currentAction.label ~= committedAction.label then
                                isUncommitted = true
                                break
                            end

                            -- Compare methods arrays
                            local currentMethodsCount = currentAction.methods and table.getn(currentAction.methods) or 0
                            local committedMethodsCount = committedAction.methods and table.getn(committedAction.methods) or 0

                            if currentMethodsCount ~= committedMethodsCount then
                                isUncommitted = true
                                break
                            end

                            -- Compare each method
                            for j = 1, currentMethodsCount do
                                local currentMethod = currentAction.methods[j]
                                local committedMethod = committedAction.methods[j]

                                if currentMethod.type ~= committedMethod.type then
                                    isUncommitted = true
                                    break
                                end

                                -- Compare params
                                if currentMethod.params and committedMethod.params then
                                    for key, value in pairs(currentMethod.params) do
                                        if tostring(committedMethod.params[key]) ~= tostring(value) then
                                            isUncommitted = true
                                            break
                                        end
                                    end
                                    for key, value in pairs(committedMethod.params) do
                                        if tostring(currentMethod.params[key]) ~= tostring(value) then
                                            isUncommitted = true
                                            break
                                        end
                                    end
                                end
                            end

                            if isUncommitted then
                                break
                            end
                        end
                    end
                end
            end
        else
            -- No committed database exists = all items are uncommitted
            isUncommitted = true
        end

        local itemFrame = CreateFrame("Frame", nil, scrollChild)
        itemFrame:SetWidth(580)
        itemFrame:SetHeight(50)
        itemFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)

        local bg = itemFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(0.1, 0.1, 0.1, 0.5)

        local iconTex = itemFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetWidth(40)
        iconTex:SetHeight(40)
        iconTex:SetPoint("LEFT", 5, 0)
        iconTex:SetTexture(item.icon)

        local nameText = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        nameText:SetPoint("LEFT", iconTex, "RIGHT", 10, 0)
        nameText:SetText(item.name)

        -- Color uncommitted items red
        if isUncommitted then
            nameText:SetTextColor(1, 0.3, 0.3)  -- Red for uncommitted
        else
            nameText:SetTextColor(1, 1, 1)  -- White for committed
        end

        -- Revert button (only show if uncommitted AND has committed version - not for new items)
        if isUncommitted and committedItem then
            local revertBtn = CreateFrame("Button", nil, itemFrame, "UIPanelButtonTemplate")
            revertBtn:SetPoint("RIGHT", -210, 0)
            revertBtn:SetWidth(80)
            revertBtn:SetHeight(25)
            revertBtn:SetText("Revert")
            do
                local itemIdToRevert = item.id
                revertBtn:SetScript("OnClick", function()
                    RPMItems_RevertItem(itemIdToRevert)
                end)
            end
        end

        local editBtn = CreateFrame("Button", nil, itemFrame, "UIPanelButtonTemplate")
        editBtn:SetPoint("RIGHT", -120, 0)
        editBtn:SetWidth(80)
        editBtn:SetHeight(25)
        editBtn:SetText("Edit")
        do
            local itemToEdit = item
            editBtn:SetScript("OnClick", function()
                RPMItems_OpenEditForm(itemToEdit)
            end)
        end

        local giveBtn = CreateFrame("Button", nil, itemFrame, "UIPanelButtonTemplate")
        giveBtn:SetPoint("RIGHT", -30, 0)
        giveBtn:SetWidth(80)
        giveBtn:SetHeight(25)
        giveBtn:SetText("Give")
        do
            local itemToGive = item
            giveBtn:SetScript("OnClick", function()
                RPMItems_ShowPlayerSelector(itemToGive)
            end)
        end

        yOffset = yOffset - 60
    end

    -- Each item is 60px tall (50px item + 10px spacing)
    scrollChild:SetHeight(math.max(1, itemCount * 60))
    RPMItems_UpdateScrollRange()
end

-- Give Item Frame (created once, reused)
local giveItemFrame = nil
local currentGiveItem = nil

-- Function: Player selector for giving item
function RPMItems_ShowPlayerSelector(item)
    Log("ShowPlayerSelector called for item: " .. tostring(item.name))
    currentGiveItem = item

    -- Create frame if it doesn't exist
    if not giveItemFrame then
        giveItemFrame = CreateFrame("Frame", "RPMasterGiveItemFrame", UIParent)
        giveItemFrame:SetWidth(400)
        giveItemFrame:SetHeight(320)
        giveItemFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        giveItemFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })
        giveItemFrame:SetBackdropColor(0, 0, 0, 1)
        giveItemFrame:SetMovable(true)
        giveItemFrame:SetFrameStrata("DIALOG")
        giveItemFrame:EnableMouse(true)

        -- Title
        local title = giveItemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -15)
        title:SetText("Give Item to Player")
        giveItemFrame.title = title

        -- Item name label
        local itemLabel = giveItemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        itemLabel:SetPoint("TOPLEFT", 20, -50)
        itemLabel:SetText("Item:")

        local itemName = giveItemFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        itemName:SetPoint("LEFT", itemLabel, "RIGHT", 5, 0)
        itemName:SetText("")
        giveItemFrame.itemName = itemName

        -- Player dropdown label
        local playerLabel = giveItemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        playerLabel:SetPoint("TOPLEFT", 20, -85)
        playerLabel:SetText("Player:")

        -- Player dropdown
        local playerDropdown = CreateFrame("Frame", "RPMGivePlayerDropdown", giveItemFrame, "UIDropDownMenuTemplate")
        playerDropdown:SetPoint("TOPLEFT", 70, -80)
        UIDropDownMenu_SetWidth(280, playerDropdown)  -- WoW 1.12: width first, then dropdown
        giveItemFrame.playerDropdown = playerDropdown

        -- Message label
        local messageLabel = giveItemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        messageLabel:SetPoint("TOPLEFT", 20, -130)
        messageLabel:SetText("Message (optional):")

        -- Message edit box
        local messageEdit = CreateFrame("EditBox", nil, giveItemFrame)
        messageEdit:SetPoint("TOPLEFT", 20, -155)
        messageEdit:SetWidth(360)
        messageEdit:SetHeight(80)
        messageEdit:SetMultiLine(true)
        messageEdit:SetAutoFocus(false)
        messageEdit:SetFontObject(GameFontHighlight)
        messageEdit:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        messageEdit:SetBackdropColor(0, 0, 0, 0.8)
        messageEdit:SetText("You found this item, check /rpplayer")
        messageEdit:SetMaxLetters(255)
        messageEdit:SetScript("OnEscapePressed", function() 
            messageEdit:ClearFocus()
        end)
        giveItemFrame.messageEdit = messageEdit

        -- Give button
        local giveBtn = CreateFrame("Button", nil, giveItemFrame, "UIPanelButtonTemplate")
        giveBtn:SetWidth(100)
        giveBtn:SetHeight(25)
        giveBtn:SetPoint("BOTTOMRIGHT", -20, 15)
        giveBtn:SetText("Give Item")
        giveBtn:SetScript("OnClick", function()
            local selectedPlayer = UIDropDownMenu_GetText(playerDropdown)
            local message = messageEdit:GetText()

            if selectedPlayer and selectedPlayer ~= "" then
                RPMItems_GiveItemToPlayer(currentGiveItem, selectedPlayer, message)
                giveItemFrame:Hide()
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Please select a player!", 1, 0, 0)
            end
        end)

        -- Cancel button
        local cancelBtn = CreateFrame("Button", nil, giveItemFrame, "UIPanelButtonTemplate")
        cancelBtn:SetWidth(100)
        cancelBtn:SetHeight(25)
        cancelBtn:SetPoint("RIGHT", giveBtn, "LEFT", -10, 0)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function()
            giveItemFrame:Hide()
        end)

        -- Close button
        local closeBtn = CreateFrame("Button", nil, giveItemFrame, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)

        -- Make draggable
        giveItemFrame:SetScript("OnMouseDown", function()
            this:StartMoving()
        end)
        giveItemFrame:SetScript("OnMouseUp", function()
            this:StopMovingOrSizing()
        end)
    end

    -- Update item name
    giveItemFrame.itemName:SetText(item.name)

    -- Populate dropdown with raid/party members + self
    UIDropDownMenu_Initialize(giveItemFrame.playerDropdown, function()
        -- Always add self first
        local playerName = UnitName("player")
        if playerName then
            local info = {}
            info.text = playerName .. " (self)"
            info.value = playerName
            -- Create closure-safe reference
            do
                local selfName = playerName
                info.func = function()
                    UIDropDownMenu_SetSelectedValue(giveItemFrame.playerDropdown, selfName)
                    UIDropDownMenu_SetText(selfName .. " (self)", giveItemFrame.playerDropdown)
                end
            end
            UIDropDownMenu_AddButton(info)
        end

        -- Add raid members
        if GetNumRaidMembers() > 0 then
            for i = 1, GetNumRaidMembers() do
                local name = GetRaidRosterInfo(i)
                -- Skip self (already added above)
                if name and name ~= playerName then
                    local info = {}
                    info.text = name
                    info.value = name
                    -- Create closure-safe reference
                    do
                        local raidMemberName = name
                        info.func = function()
                            UIDropDownMenu_SetSelectedValue(giveItemFrame.playerDropdown, raidMemberName)
                            UIDropDownMenu_SetText(raidMemberName, giveItemFrame.playerDropdown)
                        end
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end
        elseif GetNumPartyMembers() > 0 then
            -- Add party members
            for i = 1, GetNumPartyMembers() do
                local name = UnitName("party"..i)
                if name then
                    local info = {}
                    info.text = name
                    info.value = name
                    -- Create closure-safe reference
                    do
                        local partyMemberName = name
                        info.func = function()
                            UIDropDownMenu_SetSelectedValue(giveItemFrame.playerDropdown, partyMemberName)
                            UIDropDownMenu_SetText(partyMemberName, giveItemFrame.playerDropdown)
                        end
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end
        end
    end)

    -- Reset dropdown
    UIDropDownMenu_SetText("Select player...", giveItemFrame.playerDropdown)

    -- Reset message to default
    giveItemFrame.messageEdit:SetText("You found this item, check /rpplayer")

    giveItemFrame:Show()
end

-- ============================================================================
-- BASE64 ENCODING (for safe addon message transmission)
-- GetDistribution and SendTwoPartMessage moved to turtle-rp-common/rp-business.lua
-- Use rpBusiness.GetDistribution() and rpBusiness.CreateGiveMessage()

-- ============================================================================
-- RPMItems_GiveItemToPlayer() - Send item to player via GUID-based message
-- ============================================================================
-- @param item: Table - The item to send (from RPMasterDB.itemLibrary)
-- @param playerName: String - Target player name
-- @param customMessage: String - Optional custom message shown in popup
-- @returns: void
--
-- NEW PROTOCOL: GUID-based (tiny messages, no Base64, no size limits)
-- Format: GIVE^playerName^itemGuid^customMessage
-- ============================================================================
function RPMItems_GiveItemToPlayer(item, playerName, customMessage)
    Log("RPMItems_GiveItemToPlayer called - Item: " .. tostring(item.name) .. ", Player: " .. playerName)

    -- Validate item has GUID
    if not item or not item.guid then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Item missing GUID!", 1, 0, 0)
        Log("ERROR: Item missing GUID")
        return
    end

    -- Warn if no committed database (players won't be able to receive items)
    if not RPMasterDB or not RPMasterDB.committedDatabase then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFAA00[RPMaster]|r WARNING: No committed database! Players cannot receive items.", 1, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFAA00[RPMaster]|r Click 'Commit Database' and 'Sync to Raid' first.", 1, 1, 0)
        Log("WARNING: Giving item without committed database - players won't be able to receive it")
        -- Don't return - still send the message, but warn the user
    end

    -- Send message (messaging.lua handles creation + distribution + sending)
    -- Use item's initialCounter (GM-defined starting value) for customNumber
    Log("Sending GIVE message - Player: " .. playerName .. ", GUID: " .. item.guid .. ", Custom: " .. tostring(customMessage or "") .. ", InitialCounter: " .. tostring(item.initialCounter or 0))

    local success = messaging.SendGiveMessage(playerName, item.guid, customMessage or "", "", item.initialCounter or 0)

    if not success then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Failed to send message!", 1, 0, 0)
        Log("ERROR: Failed to send GIVE message")
        return
    end

    -- Show confirmation in chat
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF00FF00[RPMaster]|r Item '%s' sent to %s (GUID: %s)",
        item.name, playerName, item.guid), 0, 1, 0)
    Log("GIVE message sent successfully")
end

-- ============================================================================
-- RPMItems_CommitDatabase() - Create committed snapshot for player sync
-- ============================================================================
-- PURPOSE:
--   - Creates a snapshot of current itemLibrary that players will receive
--   - Uncommitted changes (edits in progress) are not synced to players
--   - Updates committedVersion timestamp for tracking sync status
--
-- WORKFLOW:
--   1. GM creates/edits items (saved to RPMasterDB.itemLibrary immediately)
--   2. GM clicks "Commit Database" (creates committedDatabase snapshot with metadata)
--   3. Players sync and receive committedDatabase.items (not current edits)
--   4. GM can continue editing without affecting already-synced players
--
-- SIMILAR TO: Git commit (staging changes), database migrations
-- ============================================================================
function RPMItems_CommitDatabase()
    -- Initialize database if needed
    if not RPMasterDB then
        RPMasterDB = {itemLibrary = {}, nextItemID = 1}
    end

    -- Ensure database has a name
    if not RPMasterDB.databaseName or RPMasterDB.databaseName == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Please enter a database name first!", 1, 0, 0)
        return
    end

    -- Use objectDatabase.CreateCommittedDatabase to create snapshot with metadata and checksum
    -- This creates a deep copy with proper structure: {items, metadata}
    local committedDatabase = objectDatabase.CreateCommittedDatabase(
        RPMasterDB.itemLibrary,
        RPMasterDB.databaseName
    )

    -- Save committed snapshot (new structure with metadata)
    RPMasterDB.committedDatabase = committedDatabase
    RPMasterDB.committedVersion = committedDatabase.metadata.version  -- Use version from metadata

    -- Backward compatibility: keep old databaseId or generate from new metadata
    if not RPMasterDB.databaseId then
        RPMasterDB.databaseId = committedDatabase.metadata.id
        Log("Generated new database ID: " .. RPMasterDB.databaseId)
    end

    -- Count items (committedDatabase.items is a hash table indexed by ID, not a sequential array)
    local itemCount = 0
    for _ in pairs(committedDatabase.items) do
        itemCount = itemCount + 1
    end

    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF00FF00[RPMaster]|r Database '%s' committed! (%d items, checksum: %s)",
        RPMasterDB.databaseName, itemCount, committedDatabase.metadata.checksum), 0, 1, 0)

    Log(string.format("Database committed: %s (ID: %s, %d items, checksum: %s)",
        RPMasterDB.databaseName, committedDatabase.metadata.id, itemCount, committedDatabase.metadata.checksum))

    -- Update Monitor tab database status if it exists
    -- Call global function from Monitor.lua (may not exist if Monitor not loaded yet)
    if RPMMonitor_UpdateDatabaseStatus then
        RPMMonitor_UpdateDatabaseStatus()
    end

    -- Refresh item list to update uncommitted indicators (red -> white)
    RPMItems_RefreshItemList()
end

-- ============================================================================
-- RPMItems_InitializeDatabase() - Ensure database structure exists
-- ============================================================================
-- PURPOSE: Initialize RPMasterDB on first load or after reset
-- CALLED BY: RPMItems_Show() to ensure database exists before UI operations
-- ============================================================================
local function RPMItems_InitializeDatabase()
    if not RPMasterDB then
        RPMasterDB = {}
    end

    -- Item library (working copy, changes saved immediately)
    if not RPMasterDB.itemLibrary then
        RPMasterDB.itemLibrary = {}
    end

    -- Next item ID counter
    if not RPMasterDB.nextItemID then
        RPMasterDB.nextItemID = 1
    end

    -- Database name (user-provided, for identification)
    if not RPMasterDB.databaseName then
        RPMasterDB.databaseName = ""
    end

    -- Database ID (auto-generated, unique per Master instance)
    -- NOT generated until first commit (see RPMItems_CommitDatabase)
    -- Format: "timestamp-random"

    -- Committed library (snapshot for player sync)
    -- nil until first commit

    -- Committed version (timestamp of last commit)
    -- nil until first commit
end

-- ============================================================================
-- RPMItems_SyncDatabaseToRaid() - Send committed database to all raid members
-- ============================================================================
-- PURPOSE: Synchronize GM's item database to all players in raid
--
-- WORKFLOW:
--   1. GM commits database (creates committed snapshot)
--   2. GM clicks "Sync to Raid" button
--   3. Sends DB_SYNC message with serialized database to raid
--   4. Players receive and store database locally
--   5. Players can now look up items by GUID when receiving GIVE messages
--
-- NEW PROTOCOL: Database sync enables GUID-based item distribution
-- ============================================================================
function RPMItems_SyncDatabaseToRaid()
    -- Validate committed database exists
    if not RPMasterDB or not RPMasterDB.committedDatabase then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r No committed database to sync! Click 'Commit & Sync' first.", 1, 0, 0)
        return
    end

    -- Validate database has name
    if not RPMasterDB.databaseName or RPMasterDB.databaseName == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Database must have a name before syncing!", 1, 0, 0)
        return
    end

    -- Create chunked sync messages (WoW 1.12 has 255 byte limit)
    local messages = objectDatabase.CreateSyncMessageChunks(RPMasterDB.committedDatabase)

    if not messages or table.getn(messages) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Failed to create sync messages!", 1, 0, 0)
        return
    end

    -- Send to entire raid
    if GetNumRaidMembers() > 0 then
        -- Send each chunk sequentially
        for i = 1, table.getn(messages) do
            Log("Attempting to send message " .. i .. "/" .. table.getn(messages))
            Log("Message length: " .. string.len(messages[i]) .. " bytes")
            Log("Message content (first 100 chars): " .. string.sub(messages[i], 1, 100))

            SendAddonMessage(ADDON_PREFIX, messages[i], "RAID")
            Log("Sent sync message " .. i .. "/" .. table.getn(messages))
        end

        -- Count items (hash table indexed by ID)
        local itemCount = 0
        for _ in pairs(RPMasterDB.committedDatabase.items) do
            itemCount = itemCount + 1
        end
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF00FF00[RPMaster]|r Database '%s' synced to raid (%d items, %d messages)",
            RPMasterDB.databaseName, itemCount, table.getn(messages)), 0, 1, 0)
        Log("Database synced to RAID: " .. RPMasterDB.databaseName .. " (" .. itemCount .. " items, " .. table.getn(messages) .. " messages)")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Not in a raid! Cannot sync database.", 1, 0, 0)
    end
end

-- ============================================================================
-- MODULE LIFECYCLE CALLBACKS
-- ============================================================================
-- These functions are called by Core.lua when tab is shown/hidden
-- Similar to React's componentDidMount/componentWillUnmount
-- ============================================================================

-- RPMItems_Show() - Called when Items tab becomes active
function RPMItems_Show()
    RPMItems_InitializeDatabase()  -- Ensure database structure exists

    -- Load database name into input field
    if itemsContent and itemsContent.dbNameEdit then
        itemsContent.dbNameEdit:SetText(RPMasterDB.databaseName or "")
    end

    RPMItems_RefreshItemList()  -- Refresh list to show any newly created items
end

-- RPMItems_Hide() - Called when switching away from Items tab
function RPMItems_Hide()
    -- Nothing special needed (frames stay in memory, just hidden)
end

-- ============================================================================
-- MODULE REGISTRATION (Plugin pattern)
-- ============================================================================
-- Register this module with Core.lua's plugin system
--
-- EXECUTION ORDER:
--   1. ItemLibrary.lua loads (this file)
--   2. This RPM_RegisterModule() call executes
--   3. Core.lua now knows about "items" module
--   4. When user clicks Items tab, Core calls createContent()
--   5. When tab shown, Core calls onShow()
--   6. When tab hidden, Core calls onHide()
--
-- SIMILAR TO: Angular's NgModule, Vue's component registration
-- ============================================================================
RPM_RegisterModule("items", {
    createContent = RPMItems_CreateContent,  -- Factory function (builds UI)
    onShow = RPMItems_Show,                   -- Activation callback
    onHide = RPMItems_Hide                    -- Deactivation callback
})

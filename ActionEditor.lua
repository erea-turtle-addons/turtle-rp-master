-- ============================================================================
-- ActionEditor.lua - Multi-Method Action Editor for Turtle RP Master (v0.2.0)
-- ============================================================================
-- PURPOSE: GUI for creating/editing actions with multiple methods
--
-- RESPONSIBILITIES:
--   - Display action editor dialog with label and methods list
--   - Show method selector dropdown (AddText, CreateObject, etc.)
--   - Generate parameter editors based on paramSchema
--   - Handle add/remove methods
--   - Save action with methods array
--
-- ARCHITECTURE:
--   - Main dialog: 500x500 with ScrollFrame for methods
--   - Each method: Frame with type dropdown + parameter editors
--   - Dynamic parameter editors based on METHOD_REGISTRY.paramSchema
--   - Methods stored as array in action.methods
--
-- USAGE:
--   RPMActionEditor_Show(itemId, actionIndex)
--   RPMActionEditor_Hide()
-- ============================================================================

-- Import dependencies
local rpActions = RequireRPActions()
local objectDatabase = RequireObjectDatabase()

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local actionEditorDialog = nil  -- Main dialog frame
local currentActionIndex = nil  -- Index of action being edited (nil = new action)
local currentMethods = {}       -- Array of method definitions being edited
local currentConditions = {}    -- Conditions for action availability

-- Method frames storage
local methodFrames = {}         -- Array of UI frames for each method

-- External reference to ItemLibrary's currentItemActions
-- Will be accessed via global scope (ItemLibrary sets this)
-- This allows ActionEditor to work with unsaved items

-- ============================================================================
-- PARAMETER EDITOR BUILDERS
-- ============================================================================

-- ============================================================================
-- CreateTextParameterEditor - Create text input field
-- ============================================================================
local function CreateTextParameterEditor(parent, paramDef, yOffset)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 10, yOffset)
    label:SetText(paramDef.label .. ":")

    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetPoint("TOPLEFT", 10, yOffset - 20)
    editBox:SetWidth(340)
    editBox:SetHeight(25)
    editBox:SetAutoFocus(false)
    editBox.paramKey = paramDef.key

    return editBox, 50  -- Return editBox and height consumed
end

-- ============================================================================
-- CreateTextWithPlaceholderEditor - Create text input with placeholder hint
-- ============================================================================
local function CreateTextWithPlaceholderEditor(parent, paramDef, yOffset)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 10, yOffset)
    label:SetText(paramDef.label .. ":")

    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetPoint("TOPLEFT", 10, yOffset - 20)
    editBox:SetWidth(340)
    editBox:SetHeight(25)
    editBox:SetAutoFocus(false)
    editBox.paramKey = paramDef.key

    -- Show placeholder hint
    if paramDef.placeholder then
        local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("LEFT", editBox, "RIGHT", 5, 0)
        hint:SetText("|cFF888888(Use " .. paramDef.placeholder .. ")|r")
    end

    return editBox, 50
end

-- ============================================================================
-- CreateNumberParameterEditor - Create number input field
-- ============================================================================
local function CreateNumberParameterEditor(parent, paramDef, yOffset)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 10, yOffset)
    label:SetText(paramDef.label .. ":")

    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetPoint("TOPLEFT", 10, yOffset - 20)
    editBox:SetWidth(100)
    editBox:SetHeight(25)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(true)  -- WoW 1.12: Accept only numbers
    editBox.paramKey = paramDef.key

    return editBox, 50
end

-- ============================================================================
-- CreateObjectDropdownEditor - Create object GUID selector dropdown
-- ============================================================================
-- Counter for generating unique dropdown names (WoW 1.12 requires global names)
local dropdownCounter = 0

local function CreateObjectDropdownEditor(parent, paramDef, yOffset)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 10, yOffset)
    label:SetText(paramDef.label .. ":")

    -- Create dropdown with unique global name (WoW 1.12 requirement)
    dropdownCounter = dropdownCounter + 1
    local dropdownName = "RPMActionEditorDropdown" .. dropdownCounter
    local dropdown = CreateFrame("Frame", dropdownName, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", 0, yOffset - 20)
    UIDropDownMenu_SetWidth(320, dropdown)  -- WoW 1.12: width first, then dropdown
    dropdown.paramKey = paramDef.key

    -- Initialize with objects from database
    UIDropDownMenu_Initialize(dropdown, function()
        -- Get committed database items
        if RPMasterDB and RPMasterDB.committedDatabase and RPMasterDB.committedDatabase.items then
            for id, obj in pairs(RPMasterDB.committedDatabase.items) do
                local info = {}
                info.text = obj.name
                info.value = obj.guid
                info.tooltipTitle = obj.name
                info.tooltipText = "GUID: " .. obj.guid
                -- Lua 5.0: Create closure
                do
                    local selectedGuid = obj.guid
                    local selectedName = obj.name
                    info.func = function()
                        UIDropDownMenu_SetSelectedValue(dropdown, selectedGuid)
                        UIDropDownMenu_SetText(selectedName, dropdown)
                    end
                end
                UIDropDownMenu_AddButton(info)
            end
        end
    end)

    UIDropDownMenu_SetText("Select object...", dropdown)

    return dropdown, 60
end

-- ============================================================================
-- CreateParameterEditor - Create appropriate editor based on type
-- ============================================================================
local function CreateParameterEditor(parent, paramDef, yOffset)
    if paramDef.type == "text" then
        return CreateTextParameterEditor(parent, paramDef, yOffset)
    elseif paramDef.type == "text_with_placeholder" then
        return CreateTextWithPlaceholderEditor(parent, paramDef, yOffset)
    elseif paramDef.type == "number" then
        return CreateNumberParameterEditor(parent, paramDef, yOffset)
    elseif paramDef.type == "object_dropdown" then
        return CreateObjectDropdownEditor(parent, paramDef, yOffset)
    else
        -- Unknown type - create text field as fallback
        return CreateTextParameterEditor(parent, paramDef, yOffset)
    end
end

-- ============================================================================
-- METHOD FRAME MANAGEMENT
-- ============================================================================

-- ============================================================================
-- CreateMethodFrame - Create UI frame for a single method
-- ============================================================================
local function CreateMethodFrame(parent, methodIndex)
    local method = currentMethods[methodIndex]
    local methodDef = rpActions.GetMethodRegistry()[method.type]

    if not methodDef then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Unknown method type: " .. tostring(method.type), 1, 0, 0)
        return nil
    end

    -- Create method container frame
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetWidth(360)
    frame.methodIndex = methodIndex

    -- Background
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetTexture(0.1, 0.1, 0.1, 0.8)

    -- Method name label
    local nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", 5, -5)
    nameLabel:SetText("|cFFFFD700Method " .. methodIndex .. ":|r " .. methodDef.name)

    -- Remove button
    local removeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    removeBtn:SetPoint("TOPRIGHT", -5, -2)
    removeBtn:SetWidth(60)
    removeBtn:SetHeight(20)
    removeBtn:SetText("Remove")
    removeBtn:SetScript("OnClick", function()
        RPMActionEditor_RemoveMethod(methodIndex)
    end)

    -- Create parameter editors
    local yOffset = -30
    local paramEditors = {}

    if methodDef.paramSchema and table.getn(methodDef.paramSchema) > 0 then
        for i = 1, table.getn(methodDef.paramSchema) do
            local paramDef = methodDef.paramSchema[i]
            local editor, height = CreateParameterEditor(frame, paramDef, yOffset)

            if editor then
                -- Populate editor with existing value (if editing)
                if method.params and method.params[paramDef.key] then
                    if editor.GetText then
                        -- EditBox (has GetText method)
                        editor:SetText(method.params[paramDef.key])
                    else
                        -- Dropdown (doesn't have GetText)
                        UIDropDownMenu_SetSelectedValue(editor, method.params[paramDef.key])
                        -- Try to find the name for display
                        if RPMasterDB and RPMasterDB.committedDatabase and RPMasterDB.committedDatabase.items then
                            for id, obj in pairs(RPMasterDB.committedDatabase.items) do
                                if obj.guid == method.params[paramDef.key] then
                                    UIDropDownMenu_SetText(obj.name, editor)
                                    break
                                end
                            end
                        end
                    end
                end

                table.insert(paramEditors, editor)
                yOffset = yOffset - height
            end
        end
    else
        -- No parameters
        local noParamsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noParamsLabel:SetPoint("TOPLEFT", 10, -30)
        noParamsLabel:SetText("|cFF888888(No parameters required)|r")
        yOffset = yOffset - 25
    end

    frame:SetHeight(math.abs(yOffset) + 10)
    frame.paramEditors = paramEditors

    return frame
end

-- ============================================================================
-- RefreshMethodsList - Rebuild all method frames
-- ============================================================================
local function RefreshMethodsList()
    -- Clear existing frames
    for i = 1, table.getn(methodFrames) do
        if methodFrames[i] then
            methodFrames[i]:Hide()
            methodFrames[i]:SetParent(nil)
            methodFrames[i] = nil
        end
    end
    methodFrames = {}

    -- Create new frames
    local scrollChild = actionEditorDialog.methodsScrollChild
    local yOffset = -5

    for i = 1, table.getn(currentMethods) do
        local frame = CreateMethodFrame(scrollChild, i)
        if frame then
            frame:SetPoint("TOPLEFT", 5, yOffset)
            yOffset = yOffset - frame:GetHeight() - 5
            table.insert(methodFrames, frame)
        end
    end

    -- Update scroll child height
    local totalHeight = math.abs(yOffset) + 100
    scrollChild:SetHeight(math.max(totalHeight, actionEditorDialog.methodsScroll:GetHeight()))

    -- Update scroll range
    actionEditorDialog.methodsScroll:UpdateScrollChildRect()
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- ============================================================================
-- RPMActionEditor_Show - Show action editor
-- ============================================================================
-- @param actionIndex: number or nil - Index in currentItemActions (nil = new action)
--
-- NOTE: Works with ItemLibrary's currentItemActions global variable
-- This allows editing actions for items that haven't been saved yet
-- ============================================================================
function RPMActionEditor_Show(actionIndex)
    if not actionEditorDialog then
        RPMActionEditor_CreateDialog()
    end

    currentActionIndex = actionIndex

    -- Access ItemLibrary's currentItemActions via global scope
    if not currentItemActions then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Error: currentItemActions not found!", 1, 0, 0)
        return
    end

    -- Load action data from currentItemActions
    if actionIndex then
        -- Editing existing action
        local action = currentItemActions[actionIndex]
        if action then
            actionEditorDialog.labelEdit:SetText(action.label or "")

            -- Load methods array (v0.2.0) - deep copy
            currentMethods = {}
            if action.methods then
                for i = 1, table.getn(action.methods) do
                    local method = action.methods[i]
                    local methodCopy = {
                        type = method.type,
                        params = {}
                    }
                    -- Deep copy params
                    if method.params then
                        for key, value in pairs(method.params) do
                            methodCopy.params[key] = value
                        end
                    end
                    table.insert(currentMethods, methodCopy)
                end
            end

            -- Load conditions (v0.2.1)
            currentConditions = {
                customTextEmpty = action.conditions and action.conditions.customTextEmpty or false,
                counterGreaterThanZero = action.conditions and action.conditions.counterGreaterThanZero or false
            }
            actionEditorDialog.customTextEmptyCheck:SetChecked(currentConditions.customTextEmpty)
            actionEditorDialog.counterGreaterThanZeroCheck:SetChecked(currentConditions.counterGreaterThanZero)
        end
    else
        -- New action
        actionEditorDialog.labelEdit:SetText("")
        currentMethods = {}
        currentConditions = {
            customTextEmpty = false,
            counterGreaterThanZero = false
        }
        actionEditorDialog.customTextEmptyCheck:SetChecked(false)
        actionEditorDialog.counterGreaterThanZeroCheck:SetChecked(false)
    end

    RefreshMethodsList()
    actionEditorDialog:Show()
end

-- ============================================================================
-- RPMActionEditor_Hide - Hide action editor
-- ============================================================================
function RPMActionEditor_Hide()
    if actionEditorDialog then
        actionEditorDialog:Hide()
    end
    currentActionIndex = nil
    currentMethods = {}
end

-- ============================================================================
-- RPMActionEditor_AddMethod - Show method selector dropdown
-- ============================================================================
function RPMActionEditor_AddMethod()
    -- Show dropdown menu with available methods
    local availableMethods = rpActions.GetAvailableMethods()

    local menuFrame = CreateFrame("Frame", "RPMActionEditorMethodMenu", UIParent, "UIDropDownMenuTemplate")

    local function MenuInit()
        for i = 1, table.getn(availableMethods) do
            local methodInfo = availableMethods[i]
            local info = {}
            info.text = methodInfo.name
            info.tooltipTitle = methodInfo.name
            info.tooltipText = methodInfo.description
            info.notCheckable = true
            -- Lua 5.0: Create closure
            do
                local methodType = methodInfo.type
                info.func = function()
                    -- Add method to currentMethods
                    table.insert(currentMethods, {
                        type = methodType,
                        params = {}
                    })
                    RefreshMethodsList()
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end

    UIDropDownMenu_Initialize(menuFrame, MenuInit)
    ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
end

-- ============================================================================
-- RPMActionEditor_RemoveMethod - Remove method from list
-- ============================================================================
function RPMActionEditor_RemoveMethod(methodIndex)
    table.remove(currentMethods, methodIndex)
    RefreshMethodsList()
end

-- ============================================================================
-- RPMActionEditor_Save - Save action to currentItemActions
-- ============================================================================
-- NOTE: Saves to ItemLibrary's currentItemActions, not directly to database
-- ItemLibrary will save currentItemActions when user clicks "Save" on item
-- ============================================================================
function RPMActionEditor_Save()
    local label = actionEditorDialog.labelEdit:GetText()

    if label == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Label is required!", 1, 0, 0)
        return
    end

    if table.getn(currentMethods) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r At least one method is required!", 1, 0, 0)
        return
    end

    -- Access ItemLibrary's currentItemActions
    if not currentItemActions then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Error: currentItemActions not found!", 1, 0, 0)
        return
    end

    -- Extract parameter values from UI
    for i = 1, table.getn(methodFrames) do
        local frame = methodFrames[i]
        local method = currentMethods[i]

        if frame and frame.paramEditors then
            method.params = {}

            for j = 1, table.getn(frame.paramEditors) do
                local editor = frame.paramEditors[j]
                local paramKey = editor.paramKey

                if editor.GetText then
                    -- EditBox
                    method.params[paramKey] = editor:GetText()
                else
                    -- Dropdown
                    method.params[paramKey] = UIDropDownMenu_GetSelectedValue(editor) or ""
                end
            end
        end
    end

    -- Auto-generate ID from label (BEFORE validation - validation requires ID)
    local id

    if currentActionIndex then
        -- Preserve existing ID when editing
        id = currentItemActions[currentActionIndex].id
    else
        -- Generate new ID from label
        id = string.lower(label)
        id = string.gsub(id, "%s+", "_")
        id = string.gsub(id, "[^%w_]", "")

        -- Ensure uniqueness within currentItemActions
        local baseId = id
        local counter = 1
        for i = 1, table.getn(currentItemActions) do
            if currentItemActions[i].id == id then
                id = baseId .. "_" .. counter
                counter = counter + 1
            end
        end
    end

    -- Read conditions from checkboxes (v0.2.1)
    local conditions = {
        customTextEmpty = actionEditorDialog.customTextEmptyCheck:GetChecked() or false,
        counterGreaterThanZero = actionEditorDialog.counterGreaterThanZeroCheck:GetChecked() or false
    }

    -- Validate action (with ID already set)
    local action = {
        id = id,
        label = label,
        methods = currentMethods,
        conditions = conditions
    }

    local valid, errorMsg = rpActions.ValidateAction(action)
    if not valid then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Validation failed: " .. errorMsg, 1, 0, 0)
        return
    end

    -- Save to currentItemActions (NOT to database)
    if currentActionIndex then
        currentItemActions[currentActionIndex] = action
    else
        table.insert(currentItemActions, action)
    end

    -- Refresh main item editor's actions list
    if RPMItems_RefreshActionsList then
        RPMItems_RefreshActionsList()
    end

    RPMActionEditor_Hide()
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r Action saved!", 0, 1, 0)
end

-- ============================================================================
-- RPMActionEditor_CreateDialog - Create main action editor dialog
-- ============================================================================
function RPMActionEditor_CreateDialog()
    actionEditorDialog = CreateFrame("Frame", "RPMActionEditorDialog", UIParent)
    actionEditorDialog:SetWidth(450)
    actionEditorDialog:SetHeight(500)
    actionEditorDialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    actionEditorDialog:SetFrameStrata("FULLSCREEN")
    actionEditorDialog:SetBackdrop({
        bgFile = "Interface\\AddOns\\turtle-rp-master\\black",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    actionEditorDialog:SetBackdropColor(0, 0, 0, 1)
    actionEditorDialog:SetMovable(true)
    actionEditorDialog:EnableMouse(true)
    actionEditorDialog:RegisterForDrag("LeftButton")
    actionEditorDialog:SetScript("OnDragStart", actionEditorDialog.StartMoving)
    actionEditorDialog:SetScript("OnDragStop", actionEditorDialog.StopMovingOrSizing)
    actionEditorDialog:Hide()

    -- Title
    local title = actionEditorDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("Action Editor (v0.2.0)")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, actionEditorDialog, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function()
        RPMActionEditor_Hide()
    end)

    -- Label field
    local labelLabel = actionEditorDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelLabel:SetPoint("TOPLEFT", 20, -50)
    labelLabel:SetText("Action Label (shown to player):")

    local labelEdit = CreateFrame("EditBox", nil, actionEditorDialog, "InputBoxTemplate")
    labelEdit:SetPoint("TOPLEFT", 20, -70)
    labelEdit:SetWidth(390)
    labelEdit:SetHeight(25)
    labelEdit:SetAutoFocus(false)
    actionEditorDialog.labelEdit = labelEdit

    -- Conditions section
    local conditionsLabel = actionEditorDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    conditionsLabel:SetPoint("TOPLEFT", 20, -100)
    conditionsLabel:SetText("Conditions (show action only when):")

    -- Checkbox: Custom Text Empty
    local customTextEmptyCheck = CreateFrame("CheckButton", nil, actionEditorDialog, "UICheckButtonTemplate")
    customTextEmptyCheck:SetPoint("TOPLEFT", 20, -120)
    customTextEmptyCheck:SetWidth(20)
    customTextEmptyCheck:SetHeight(20)
    actionEditorDialog.customTextEmptyCheck = customTextEmptyCheck

    local customTextEmptyLabel = actionEditorDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customTextEmptyLabel:SetPoint("LEFT", customTextEmptyCheck, "RIGHT", 5, 0)
    customTextEmptyLabel:SetText("Custom Text Empty")

    -- Checkbox: Counter > 0
    local counterGreaterThanZeroCheck = CreateFrame("CheckButton", nil, actionEditorDialog, "UICheckButtonTemplate")
    counterGreaterThanZeroCheck:SetPoint("LEFT", customTextEmptyLabel, "RIGHT", 20, 0)
    counterGreaterThanZeroCheck:SetWidth(20)
    counterGreaterThanZeroCheck:SetHeight(20)
    actionEditorDialog.counterGreaterThanZeroCheck = counterGreaterThanZeroCheck

    local counterGreaterThanZeroLabel = actionEditorDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    counterGreaterThanZeroLabel:SetPoint("LEFT", counterGreaterThanZeroCheck, "RIGHT", 5, 0)
    counterGreaterThanZeroLabel:SetText("Counter > 0")

    -- Methods section
    local methodsLabel = actionEditorDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    methodsLabel:SetPoint("TOPLEFT", 20, -145)
    methodsLabel:SetText("Methods (executed in order):")

    -- ScrollFrame for methods
    local methodsScroll = CreateFrame("ScrollFrame", nil, actionEditorDialog)
    methodsScroll:SetPoint("TOPLEFT", 20, -165)
    methodsScroll:SetPoint("BOTTOMRIGHT", -40, 80)
    methodsScroll:EnableMouseWheel(true)
    actionEditorDialog.methodsScroll = methodsScroll

    -- Slider
    local slider = CreateFrame("Slider", nil, methodsScroll, "UIPanelScrollBarTemplate")
    slider:SetPoint("TOPLEFT", methodsScroll, "TOPRIGHT", 4, -16)
    slider:SetPoint("BOTTOMLEFT", methodsScroll, "BOTTOMRIGHT", 4, 16)
    slider:SetMinMaxValues(0, 100)
    slider:SetValueStep(1)
    slider:SetValue(0)
    slider:SetWidth(16)
    methodsScroll.slider = slider

    -- Scroll child
    local scrollChild = CreateFrame("Frame", nil, methodsScroll)
    scrollChild:SetWidth(370)
    scrollChild:SetHeight(1)
    methodsScroll:SetScrollChild(scrollChild)
    actionEditorDialog.methodsScrollChild = scrollChild

    -- Link slider to scroll (Lua 5.0: use arg1)
    slider:SetScript("OnValueChanged", function()
        local value = arg1
        methodsScroll:SetVerticalScroll(value)
    end)

    methodsScroll:SetScript("OnVerticalScroll", function()
        local offset = arg1
        slider:SetValue(offset)
    end)

    methodsScroll:SetScript("OnMouseWheel", function()
        local delta = arg1
        local current = slider:GetValue()
        local minVal, maxVal = slider:GetMinMaxValues()
        if delta > 0 then
            slider:SetValue(math.max(minVal, current - 20))
        else
            slider:SetValue(math.min(maxVal, current + 20))
        end
    end)

    -- Add Method button
    local addMethodBtn = CreateFrame("Button", nil, actionEditorDialog, "UIPanelButtonTemplate")
    addMethodBtn:SetPoint("BOTTOMLEFT", 20, 50)
    addMethodBtn:SetWidth(120)
    addMethodBtn:SetHeight(25)
    addMethodBtn:SetText("Add Method")
    addMethodBtn:SetScript("OnClick", function()
        RPMActionEditor_AddMethod()
    end)

    -- Save button
    local saveBtn = CreateFrame("Button", nil, actionEditorDialog, "UIPanelButtonTemplate")
    saveBtn:SetPoint("BOTTOM", -60, 15)
    saveBtn:SetWidth(100)
    saveBtn:SetHeight(25)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        RPMActionEditor_Save()
    end)

    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, actionEditorDialog, "UIPanelButtonTemplate")
    cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 10, 0)
    cancelBtn:SetWidth(100)
    cancelBtn:SetHeight(25)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        RPMActionEditor_Hide()
    end)
end

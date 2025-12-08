-- ItemLibrary.lua - Item Library module for RPMaster
-- Manages item library, creation, editing, and distribution

local ADDON_PREFIX = "RPMSTR"

-- Local logging function (reference to global Log from Core.lua)
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

-- Local references
local itemsContent = nil
local scrollFrame = nil
local scrollChild = nil
local slider = nil
local editFrame = nil
local iconPickerFrame = nil

-- Edit form fields
local nameEdit, iconEdit, tooltipEdit, contentEdit
local currentEditingItem = nil

-- Function: Generate unique GUID
local function GenerateGUID()
    local timestamp = time()
    local random = math.random(1000, 9999)
    return string.format("%d-%d-%d", timestamp, random, RPMasterDB.nextItemID)
end

-- Function: Create items content frame
function RPMItems_CreateContent(parent)
    itemsContent = CreateFrame("Frame", "RPMItemsContent", parent)
    itemsContent:SetAllPoints()

    -- Item list (ScrollFrame)
    scrollFrame = CreateFrame("ScrollFrame", "RPMItemsScrollFrame", itemsContent)
    scrollFrame:SetPoint("TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 60)
    scrollFrame:EnableMouseWheel(true)

    -- Scroll slider
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

    -- Mouse wheel script
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = slider:GetValue()
        local minVal, maxVal = slider:GetMinMaxValues()
        if delta > 0 then
            slider:SetValue(math.max(minVal, current - 20))
        else
            slider:SetValue(math.min(maxVal, current + 20))
        end
    end)

    slider:SetScript("OnValueChanged", function(self, value)
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

    -- Create edit frame and icon picker (child windows)
    RPMItems_CreateEditFrame()
    RPMItems_CreateIconPicker()

    return itemsContent
end

-- Function: Create edit form
function RPMItems_CreateEditFrame()
    editFrame = CreateFrame("Frame", "RPMItemsEditFrame", UIParent)
    editFrame:SetWidth(500)
    editFrame:SetHeight(450)
    editFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    editFrame:SetFrameStrata("DIALOG")
    editFrame:SetBackdrop({
        bgFile = "Interface\\AddOns\\RPMaster\\black",
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
    editTitle:SetPoint("TOP", 0, -20)
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

    nameEdit = CreateEditBox(editFrame, "Item name:", -50, 30, false)
    iconEdit = CreateEditBox(editFrame, "Icon (texture):", -100, 30, false)
    iconEdit:SetWidth(320)
    iconEdit:SetText("Interface\\Icons\\INV_Misc_Note_01")

    tooltipEdit = CreateEditBox(editFrame, "Tooltip (short description):", -150, 60, true)
    tooltipEdit:SetMaxLetters(120)
    contentEdit = CreateEditBox(editFrame, "Content (long text for letters):", -240, 100, true)

    local saveBtn = CreateFrame("Button", nil, editFrame, "UIPanelButtonTemplate")
    saveBtn:SetPoint("BOTTOM", -80, 20)
    saveBtn:SetWidth(120)
    saveBtn:SetHeight(30)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        RPMItems_SaveItem()
    end)

    local deleteBtn = CreateFrame("Button", nil, editFrame, "UIPanelButtonTemplate")
    deleteBtn:SetPoint("BOTTOM", 80, 20)
    deleteBtn:SetWidth(120)
    deleteBtn:SetHeight(30)
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
end

-- Common WoW icon list
local iconList = {
    -- Notes, Scrolls, Letters
    "Interface\\Icons\\INV_Misc_Note_01", "Interface\\Icons\\INV_Misc_Note_02", "Interface\\Icons\\INV_Misc_Note_03",
    "Interface\\Icons\\INV_Misc_Note_04", "Interface\\Icons\\INV_Misc_Note_05", "Interface\\Icons\\INV_Misc_Note_06",
    "Interface\\Icons\\INV_Scroll_01", "Interface\\Icons\\INV_Scroll_02", "Interface\\Icons\\INV_Scroll_03",
    "Interface\\Icons\\INV_Scroll_04", "Interface\\Icons\\INV_Scroll_05", "Interface\\Icons\\INV_Scroll_06",
    "Interface\\Icons\\INV_Scroll_07", "Interface\\Icons\\INV_Scroll_08", "Interface\\Icons\\INV_Scroll_09",
    "Interface\\Icons\\INV_Letter_01", "Interface\\Icons\\INV_Letter_02", "Interface\\Icons\\INV_Letter_03",
    "Interface\\Icons\\INV_Letter_04", "Interface\\Icons\\INV_Letter_05", "Interface\\Icons\\INV_Letter_06",
    "Interface\\Icons\\INV_Letter_07", "Interface\\Icons\\INV_Letter_08", "Interface\\Icons\\INV_Letter_09",
    "Interface\\Icons\\INV_Letter_10", "Interface\\Icons\\INV_Letter_11", "Interface\\Icons\\INV_Letter_12",
    "Interface\\Icons\\INV_Letter_13", "Interface\\Icons\\INV_Letter_14", "Interface\\Icons\\INV_Letter_15",
    -- Books
    "Interface\\Icons\\INV_Misc_Book_01", "Interface\\Icons\\INV_Misc_Book_02", "Interface\\Icons\\INV_Misc_Book_03",
    "Interface\\Icons\\INV_Misc_Book_04", "Interface\\Icons\\INV_Misc_Book_05", "Interface\\Icons\\INV_Misc_Book_06",
    "Interface\\Icons\\INV_Misc_Book_07", "Interface\\Icons\\INV_Misc_Book_08", "Interface\\Icons\\INV_Misc_Book_09",
    "Interface\\Icons\\INV_Misc_Book_10", "Interface\\Icons\\INV_Misc_Book_11", "Interface\\Icons\\INV_Misc_Book_12",
    "Interface\\Icons\\INV_Misc_Book_13", "Interface\\Icons\\INV_Misc_Book_14", "Interface\\Icons\\INV_Misc_Book_15",
    "Interface\\Icons\\INV_Misc_Book_16", "Interface\\Icons\\INV_Misc_Book_17",
    -- Jewelry
    "Interface\\Icons\\INV_Jewelry_Ring_01", "Interface\\Icons\\INV_Jewelry_Ring_02", "Interface\\Icons\\INV_Jewelry_Ring_03",
    "Interface\\Icons\\INV_Jewelry_Ring_04", "Interface\\Icons\\INV_Jewelry_Ring_05", "Interface\\Icons\\INV_Jewelry_Ring_06",
    "Interface\\Icons\\INV_Jewelry_Ring_07", "Interface\\Icons\\INV_Jewelry_Ring_08", "Interface\\Icons\\INV_Jewelry_Ring_09",
    "Interface\\Icons\\INV_Jewelry_Ring_10", "Interface\\Icons\\INV_Jewelry_Necklace_01", "Interface\\Icons\\INV_Jewelry_Necklace_02",
    "Interface\\Icons\\INV_Jewelry_Necklace_03", "Interface\\Icons\\INV_Jewelry_Necklace_04", "Interface\\Icons\\INV_Jewelry_Necklace_05",
    "Interface\\Icons\\INV_Jewelry_Necklace_06", "Interface\\Icons\\INV_Jewelry_Necklace_07", "Interface\\Icons\\INV_Jewelry_Necklace_08",
    "Interface\\Icons\\INV_Jewelry_Talisman_01", "Interface\\Icons\\INV_Jewelry_Talisman_02", "Interface\\Icons\\INV_Jewelry_Talisman_03",
    "Interface\\Icons\\INV_Jewelry_Talisman_04", "Interface\\Icons\\INV_Jewelry_Talisman_05", "Interface\\Icons\\INV_Jewelry_Talisman_06",
    "Interface\\Icons\\INV_Jewelry_Talisman_07", "Interface\\Icons\\INV_Jewelry_Talisman_08", "Interface\\Icons\\INV_Jewelry_Talisman_09",
    "Interface\\Icons\\INV_Jewelry_Talisman_10", "Interface\\Icons\\INV_Jewelry_Talisman_11", "Interface\\Icons\\INV_Jewelry_Talisman_12",
    -- Gems & Stones
    "Interface\\Icons\\INV_Misc_Gem_01", "Interface\\Icons\\INV_Misc_Gem_02", "Interface\\Icons\\INV_Misc_Gem_03",
    "Interface\\Icons\\INV_Misc_Gem_Diamond_01", "Interface\\Icons\\INV_Misc_Gem_Diamond_02", "Interface\\Icons\\INV_Misc_Gem_Diamond_03",
    "Interface\\Icons\\INV_Misc_Gem_Emerald_01", "Interface\\Icons\\INV_Misc_Gem_Emerald_02", "Interface\\Icons\\INV_Misc_Gem_Emerald_03",
    "Interface\\Icons\\INV_Misc_Gem_Ruby_01", "Interface\\Icons\\INV_Misc_Gem_Ruby_02", "Interface\\Icons\\INV_Misc_Gem_Ruby_03",
    "Interface\\Icons\\INV_Misc_Gem_Sapphire_01", "Interface\\Icons\\INV_Misc_Gem_Sapphire_02", "Interface\\Icons\\INV_Misc_Gem_Sapphire_03",
    "Interface\\Icons\\INV_Misc_Gem_Opal_01", "Interface\\Icons\\INV_Misc_Gem_Opal_02", "Interface\\Icons\\INV_Misc_Gem_Opal_03",
    "Interface\\Icons\\INV_Misc_Gem_Pearl_01", "Interface\\Icons\\INV_Misc_Gem_Pearl_02", "Interface\\Icons\\INV_Misc_Gem_Pearl_03",
    "Interface\\Icons\\INV_Misc_Gem_Topaz_01", "Interface\\Icons\\INV_Misc_Gem_Topaz_02", "Interface\\Icons\\INV_Misc_Gem_Topaz_03",
    "Interface\\Icons\\INV_Stone_01", "Interface\\Icons\\INV_Stone_02", "Interface\\Icons\\INV_Stone_03",
    "Interface\\Icons\\INV_Stone_04", "Interface\\Icons\\INV_Stone_05", "Interface\\Icons\\INV_Stone_06",
    "Interface\\Icons\\INV_Stone_07", "Interface\\Icons\\INV_Stone_08", "Interface\\Icons\\INV_Stone_09",
    "Interface\\Icons\\INV_Stone_10", "Interface\\Icons\\INV_Stone_11", "Interface\\Icons\\INV_Stone_12",
    "Interface\\Icons\\INV_Stone_13", "Interface\\Icons\\INV_Stone_14", "Interface\\Icons\\INV_Stone_15",
    -- Misc Items
    "Interface\\Icons\\INV_Misc_QuestionMark", "Interface\\Icons\\INV_Misc_Orb_01", "Interface\\Icons\\INV_Misc_Orb_02",
    "Interface\\Icons\\INV_Misc_Orb_03", "Interface\\Icons\\INV_Misc_Orb_04", "Interface\\Icons\\INV_Misc_Orb_05",
    "Interface\\Icons\\INV_Misc_Rune_01", "Interface\\Icons\\INV_Misc_Rune_02", "Interface\\Icons\\INV_Misc_Rune_03",
    "Interface\\Icons\\INV_Misc_Rune_04", "Interface\\Icons\\INV_Misc_Rune_05", "Interface\\Icons\\INV_Misc_Rune_06",
    "Interface\\Icons\\INV_Misc_Key_01", "Interface\\Icons\\INV_Misc_Key_02", "Interface\\Icons\\INV_Misc_Key_03",
    "Interface\\Icons\\INV_Misc_Coin_01", "Interface\\Icons\\INV_Misc_Coin_02", "Interface\\Icons\\INV_Misc_Map_01"
}

-- Function: Create icon picker
function RPMItems_CreateIconPicker()
    iconPickerFrame = CreateFrame("Frame", "RPMItemsIconPicker", UIParent)
    iconPickerFrame:SetWidth(400)
    iconPickerFrame:SetHeight(500)
    iconPickerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    iconPickerFrame:SetFrameStrata("DIALOG")
    iconPickerFrame:SetBackdrop({
        bgFile = "Interface\\AddOns\\RPMaster\\black",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    iconPickerFrame:SetBackdropColor(0, 0, 0, 1)
    iconPickerFrame:SetMovable(true)
    iconPickerFrame:EnableMouse(true)
    iconPickerFrame:RegisterForDrag("LeftButton")
    iconPickerFrame:SetScript("OnDragStart", iconPickerFrame.StartMoving)
    iconPickerFrame:SetScript("OnDragStop", iconPickerFrame.StopMovingOrSizing)
    iconPickerFrame:Hide()

    local pickerTitle = iconPickerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pickerTitle:SetPoint("TOP", 0, -20)
    pickerTitle:SetText("Choose Icon")

    local pickerCloseBtn = CreateFrame("Button", nil, iconPickerFrame, "UIPanelCloseButton")
    pickerCloseBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Scrollable icon grid
    local iconScrollFrame = CreateFrame("ScrollFrame", "RPMItemsIconScrollFrame", iconPickerFrame, "UIPanelScrollFrameTemplate")
    iconScrollFrame:SetPoint("TOPLEFT", 20, -50)
    iconScrollFrame:SetPoint("BOTTOMRIGHT", -40, 20)

    local iconScrollChild = CreateFrame("Frame", nil, iconScrollFrame)
    iconScrollChild:SetWidth(320)
    iconScrollChild:SetHeight(1)

    local scrollBg = iconScrollChild:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetAllPoints(iconScrollChild)
    scrollBg:SetTexture(0, 0, 0, 1)

    iconScrollFrame:SetScrollChild(iconScrollChild)
    iconPickerFrame.scrollChild = iconScrollChild
end

-- Function: Populate icon picker
function RPMItems_PopulateIconPicker()
    local iconScrollChild = iconPickerFrame.scrollChild

    -- Clean up old buttons
    for i, child in ipairs({iconScrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    local iconsPerRow = 6
    local iconSize = 40
    local spacing = 10
    local xOffset = 10
    local yOffset = -10

    for index, iconPath in ipairs(iconList) do
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
            GameTooltip:SetText(iconPath, 1, 1, 1)
            GameTooltip:Show()
        end)

        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    local rowCount = math.ceil(table.getn(iconList) / iconsPerRow)
    iconScrollChild:SetHeight(math.max(1, rowCount * (iconSize + spacing) + 20))
end

-- Function: Open icon picker
function RPMItems_OpenIconPicker()
    RPMItems_PopulateIconPicker()
    iconPickerFrame:Show()
end

-- Function: Open edit form
function RPMItems_OpenEditForm(item)
    currentEditingItem = item

    if item then
        nameEdit:SetText(item.name or "")
        iconEdit:SetText(item.icon or "Interface\\Icons\\INV_Misc_Note_01")
        tooltipEdit:SetText(item.tooltip or "")
        contentEdit:SetText(item.content or "")

        nameEdit:HighlightText(0, 0)
        iconEdit:HighlightText(0, 0)

        editFrame.deleteBtn:Show()
    else
        nameEdit:SetText("")
        iconEdit:SetText("Interface\\Icons\\INV_Misc_Note_01")
        tooltipEdit:SetText("")
        contentEdit:SetText("")
        editFrame.deleteBtn:Hide()
    end

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

    if name == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Name is required!", 1, 0, 0)
        return
    end

    if currentEditingItem then
        -- Update existing item
        local itemID = currentEditingItem.id

        if RPMasterDB.itemLibrary[itemID] then
            RPMasterDB.itemLibrary[itemID].name = name
            RPMasterDB.itemLibrary[itemID].icon = icon
            RPMasterDB.itemLibrary[itemID].tooltip = tooltip
            RPMasterDB.itemLibrary[itemID].content = content
            if not RPMasterDB.itemLibrary[itemID].guid then
                RPMasterDB.itemLibrary[itemID].guid = GenerateGUID()
            end
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r Item updated! ID: "..itemID, 0, 1, 0)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Error: Item ID "..itemID.." not found!", 1, 0, 0)
            return
        end
    else
        -- Create new item
        local newItem = {
            id = RPMasterDB.nextItemID,
            guid = GenerateGUID(),
            name = name,
            icon = icon,
            tooltip = tooltip,
            content = content
        }
        RPMasterDB.itemLibrary[newItem.id] = newItem
        RPMasterDB.nextItemID = RPMasterDB.nextItemID + 1
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r Item created! ID: "..newItem.id, 0, 1, 0)
    end

    currentEditingItem = nil
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

        local itemFrame = CreateFrame("Frame", nil, scrollChild)
        itemFrame:SetWidth(580)
        itemFrame:SetHeight(50)
        itemFrame:SetPoint("TOPLEFT", 10, yOffset)

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

    scrollChild:SetHeight(math.max(1, itemCount * 60))
end

-- Function: Player selector for giving item
function RPMItems_ShowPlayerSelector(item)
    Log("ShowPlayerSelector called for item: " .. tostring(item.name))

    -- Create edit box for player name input
    StaticPopupDialogs["RPMASTER_GIVE_ITEM"] = {
        text = "Enter player name to give '" .. item.name .. "':",
        button1 = "Give",
        button2 = "Cancel",
        hasEditBox = 1,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnAccept = function()
            local playerName = getglobal(this:GetParent():GetName().."EditBox"):GetText()
            if playerName and playerName ~= "" then
                RPMItems_GiveItemToPlayer(item, playerName)
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r No player name entered!", 1, 0, 0)
            end
        end,
        EditBoxOnEnterPressed = function()
            local playerName = getglobal(this:GetParent():GetName().."EditBox"):GetText()
            if playerName and playerName ~= "" then
                RPMItems_GiveItemToPlayer(item, playerName)
            end
            this:GetParent():Hide()
        end,
        EditBoxOnEscapePressed = function()
            this:GetParent():Hide()
        end,
    }

    StaticPopup_Show("RPMASTER_GIVE_ITEM")
end

-- Base64 encoding (safe for transmission, no escape sequences)
local base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

-- Helper: get character from base64 alphabet
local function base64char(index)
    return string.sub(base64_chars, index + 1, index + 1)
end

local function Base64Encode(data)
    if not data or data == "" then return "" end

    local result = {}
    local padding = ""

    -- Process 3 bytes at a time
    local i = 1
    while i <= string.len(data) do
        local b1, b2, b3 = string.byte(data, i), string.byte(data, i + 1), string.byte(data, i + 2)

        -- First 6 bits of b1
        local enc1 = math.floor(b1 / 4)
        table.insert(result, base64char(enc1))

        if b2 then
            -- Last 2 bits of b1 + first 4 bits of b2
            local enc2 = math.mod(b1, 4) * 16 + math.floor(b2 / 16)
            table.insert(result, base64char(enc2))

            if b3 then
                -- Last 4 bits of b2 + first 2 bits of b3
                local enc3 = math.mod(b2, 16) * 4 + math.floor(b3 / 64)
                table.insert(result, base64char(enc3))

                -- Last 6 bits of b3
                local enc4 = math.mod(b3, 64)
                table.insert(result, base64char(enc4))
            else
                -- Last 4 bits of b2, padded
                local enc3 = math.mod(b2, 16) * 4
                table.insert(result, base64char(enc3))
                table.insert(result, "=")
            end
        else
            -- Last 2 bits of b1, padded
            local enc2 = math.mod(b1, 4) * 16
            table.insert(result, base64char(enc2))
            table.insert(result, "==")
        end

        i = i + 3
    end

    return table.concat(result)
end

-- Function: Send item to player
function RPMItems_GiveItemToPlayer(item, playerName)
    -- Use SendAddonMessage (always invisible)
    -- Build raw message (playerName is not encoded since it can't have special chars)
    local rawData = "GIVE|" .. playerName .. "|" .. tostring(item.id) .. "|" .. (item.name or "") .. "|" .. (item.icon or "") .. "|" .. (item.tooltip or "") .. "|" .. (item.content or "")

    Log("Raw message before encoding: " .. rawData)

    -- Base64 encode the entire message to avoid any escape sequence issues
    local data = Base64Encode(rawData)

    Log("Base64 encoded message: " .. data)
    Log("Base64 message length: " .. string.len(data))

    -- Determine best distribution method
    local distribution = nil
    local target = nil

    if GetNumRaidMembers() > 0 then
        -- In a raid - use RAID distribution (invisible, works across server)
        distribution = "RAID"
        Log("Using RAID distribution (invisible)")
    elseif GetNumPartyMembers() > 0 then
        -- In a party - use PARTY distribution (invisible, works across server)
        distribution = "PARTY"
        Log("Using PARTY distribution (invisible)")
    else
        -- Solo - use WHISPER (invisible, range limited)
        distribution = "WHISPER"
        target = playerName
        Log("Using WHISPER distribution to " .. playerName .. " (invisible, range limited)")
    end

    Log("Sending item via " .. distribution)
    SendAddonMessage("RPMSTR", data, distribution, target)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF00FF00[RPMaster]|r Item '%s' sent to %s", item.name, playerName), 0, 1, 0)
    Log("Item sent successfully via " .. distribution)
end

-- Function: Show callback
function RPMItems_Show()
    RPMItems_RefreshItemList()
end

-- Function: Hide callback
function RPMItems_Hide()
    -- Nothing special needed
end

-- Register module with Core
RPM_RegisterModule("items", {
    createContent = RPMItems_CreateContent,
    onShow = RPMItems_Show,
    onHide = RPMItems_Hide
})

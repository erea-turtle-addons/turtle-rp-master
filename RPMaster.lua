-- RPMaster.lua - Game Master Addon
-- Manages item library and distribution to players

local ADDON_NAME = "RPMaster"
local ADDON_PREFIX = "RPMSTR"
local ADDON_VERSION = "artifact_v31"

-- Initialize saved variables
RPMasterDB = RPMasterDB or {
    itemLibrary = {},
    nextItemID = 1
}

-- Addon is loaded if this code is running
local isLoaded = true

-- Function: Generate unique GUID
local function GenerateGUID()
    local timestamp = time()
    local random = math.random(1000, 9999)
    return string.format("%d-%d-%d", timestamp, random, RPMasterDB.nextItemID)
end

-- Show welcome message on login
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("PLAYER_LOGIN")
loadFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[RPMaster "..ADDON_VERSION.."]|r Game Master Addon loaded. Command: /rpmaster", 0, 1, 1)
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- Main frame
local RPMasterFrame = CreateFrame("Frame", "RPMasterFrame", UIParent)
RPMasterFrame:SetWidth(700)
RPMasterFrame:SetHeight(500)
RPMasterFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
RPMasterFrame:SetBackdrop({
    bgFile = "Interface\\AddOns\\RPMaster\\black",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
RPMasterFrame:SetBackdropColor(0, 0, 0, 1)  -- Fully opaque black background
RPMasterFrame:SetMovable(true)
RPMasterFrame:EnableMouse(true)
RPMasterFrame:RegisterForDrag("LeftButton")
RPMasterFrame:SetScript("OnDragStart", RPMasterFrame.StartMoving)
RPMasterFrame:SetScript("OnDragStop", RPMasterFrame.StopMovingOrSizing)
RPMasterFrame:Hide()

-- Title
local title = RPMasterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", RPMasterFrame, "TOP", 0, -20)
title:SetText("Game Master - RP Item Library")

-- Close button
local closeBtn = CreateFrame("Button", nil, RPMasterFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -5, -5)

-- Item list (ScrollFrame)
local scrollFrame = CreateFrame("ScrollFrame", "RPMasterScrollFrame", RPMasterFrame)
scrollFrame:SetPoint("TOPLEFT", RPMasterFrame, "TOPLEFT", 20, -50)
scrollFrame:SetPoint("BOTTOMRIGHT", RPMasterFrame, "BOTTOMRIGHT", -40, 100)
scrollFrame:EnableMouseWheel(true)

-- Scroll slider
local slider = CreateFrame("Slider", "RPMasterScrollBar", scrollFrame, "UIPanelScrollBarTemplate")
slider:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 4, -16)
slider:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4, 16)
slider:SetMinMaxValues(0, 100)
slider:SetValueStep(1)
slider:SetValue(0)
slider:SetWidth(16)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
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
local newItemBtn = CreateFrame("Button", nil, RPMasterFrame, "UIPanelButtonTemplate")
newItemBtn:SetPoint("BOTTOMLEFT", 20, 20)
newItemBtn:SetWidth(150)
newItemBtn:SetHeight(30)
newItemBtn:SetText("New Item")

local refreshBtn = CreateFrame("Button", nil, RPMasterFrame, "UIPanelButtonTemplate")
refreshBtn:SetPoint("BOTTOMLEFT", 180, 20)
refreshBtn:SetWidth(150)
refreshBtn:SetHeight(30)
refreshBtn:SetText("Refresh")

-- Item edit frame
local editFrame = CreateFrame("Frame", "RPMasterEditFrame", UIParent)
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
editFrame:SetBackdropColor(0, 0, 0, 1)  -- Fully opaque black background
editFrame:SetMovable(true)
editFrame:EnableMouse(true)
editFrame:RegisterForDrag("LeftButton")
editFrame:SetScript("OnDragStart", editFrame.StartMoving)
editFrame:SetScript("OnDragStop", editFrame.StopMovingOrSizing)
editFrame:Hide()

local editTitle = editFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
editTitle:SetPoint("TOP", editFrame, "TOP", 0, -20)
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
        editBox:SetMaxLetters(0)  -- No character limit

        local bg = editBox:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(editBox)
        bg:SetTexture(0, 0, 0, 0.5)

        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        editBox:SetScript("OnMouseDown", function(self) self:SetFocus() end)
    else
        editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        editBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset - 20)
        editBox:SetWidth(440)
        editBox:SetHeight(height)
        editBox:SetAutoFocus(false)
    end
    
    return editBox
end

local nameEdit = CreateEditBox(editFrame, "Item name:", -50, 30, false)
local iconEdit = CreateEditBox(editFrame, "Icon (texture):", -100, 30, false)
iconEdit:SetWidth(320)
iconEdit:SetText("Interface\\Icons\\INV_Misc_Note_01")

local tooltipEdit = CreateEditBox(editFrame, "Tooltip (short description):", -150, 60, true)
tooltipEdit:SetMaxLetters(120)  -- Limit tooltip to 120 characters
local contentEdit = CreateEditBox(editFrame, "Content (long text for letters):", -240, 100, true)

local saveBtn = CreateFrame("Button", nil, editFrame, "UIPanelButtonTemplate")
saveBtn:SetPoint("BOTTOM", editFrame, "BOTTOM", -80, 20)
saveBtn:SetWidth(120)
saveBtn:SetHeight(30)
saveBtn:SetText("Save")

local deleteBtn = CreateFrame("Button", nil, editFrame, "UIPanelButtonTemplate")
deleteBtn:SetPoint("BOTTOM", editFrame, "BOTTOM", 80, 20)
deleteBtn:SetWidth(120)
deleteBtn:SetHeight(30)
deleteBtn:SetText("Delete")

-- Icon picker button
local iconPickerBtn = CreateFrame("Button", nil, editFrame, "UIPanelButtonTemplate")
iconPickerBtn:SetPoint("LEFT", iconEdit, "RIGHT", 10, 0)
iconPickerBtn:SetWidth(100)
iconPickerBtn:SetHeight(22)
iconPickerBtn:SetText("Choose Icon")

-- Icon picker frame
local iconPickerFrame = CreateFrame("Frame", "RPMasterIconPicker", UIParent)
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
local iconScrollFrame = CreateFrame("ScrollFrame", "RPMasterIconScrollFrame", iconPickerFrame, "UIPanelScrollFrameTemplate")
iconScrollFrame:SetPoint("TOPLEFT", 20, -50)
iconScrollFrame:SetPoint("BOTTOMRIGHT", -40, 20)

local iconScrollChild = CreateFrame("Frame", nil, iconScrollFrame)
iconScrollChild:SetWidth(320)
iconScrollChild:SetHeight(1)

-- Black background for scroll area
local scrollBg = iconScrollChild:CreateTexture(nil, "BACKGROUND")
scrollBg:SetAllPoints(iconScrollChild)
scrollBg:SetTexture(0, 0, 0, 1)

iconScrollFrame:SetScrollChild(iconScrollChild)

-- Common WoW icon list
local iconList = {
    -- Notes, Scrolls, Letters
    "Interface\\Icons\\INV_Misc_Note_01",
    "Interface\\Icons\\INV_Misc_Note_02",
    "Interface\\Icons\\INV_Misc_Note_03",
    "Interface\\Icons\\INV_Misc_Note_04",
    "Interface\\Icons\\INV_Misc_Note_05",
    "Interface\\Icons\\INV_Misc_Note_06",
    "Interface\\Icons\\INV_Scroll_01",
    "Interface\\Icons\\INV_Scroll_02",
    "Interface\\Icons\\INV_Scroll_03",
    "Interface\\Icons\\INV_Scroll_04",
    "Interface\\Icons\\INV_Scroll_05",
    "Interface\\Icons\\INV_Scroll_06",
    "Interface\\Icons\\INV_Scroll_07",
    "Interface\\Icons\\INV_Scroll_08",
    "Interface\\Icons\\INV_Scroll_09",
    "Interface\\Icons\\INV_Letter_01",
    "Interface\\Icons\\INV_Letter_02",
    "Interface\\Icons\\INV_Letter_03",
    "Interface\\Icons\\INV_Letter_04",
    "Interface\\Icons\\INV_Letter_05",
    "Interface\\Icons\\INV_Letter_06",
    "Interface\\Icons\\INV_Letter_07",
    "Interface\\Icons\\INV_Letter_08",
    "Interface\\Icons\\INV_Letter_09",
    "Interface\\Icons\\INV_Letter_10",
    "Interface\\Icons\\INV_Letter_11",
    "Interface\\Icons\\INV_Letter_12",
    "Interface\\Icons\\INV_Letter_13",
    "Interface\\Icons\\INV_Letter_14",
    "Interface\\Icons\\INV_Letter_15",
    -- Books
    "Interface\\Icons\\INV_Misc_Book_01",
    "Interface\\Icons\\INV_Misc_Book_02",
    "Interface\\Icons\\INV_Misc_Book_03",
    "Interface\\Icons\\INV_Misc_Book_04",
    "Interface\\Icons\\INV_Misc_Book_05",
    "Interface\\Icons\\INV_Misc_Book_06",
    "Interface\\Icons\\INV_Misc_Book_07",
    "Interface\\Icons\\INV_Misc_Book_08",
    "Interface\\Icons\\INV_Misc_Book_09",
    "Interface\\Icons\\INV_Misc_Book_10",
    "Interface\\Icons\\INV_Misc_Book_11",
    "Interface\\Icons\\INV_Misc_Book_12",
    "Interface\\Icons\\INV_Misc_Book_13",
    "Interface\\Icons\\INV_Misc_Book_14",
    "Interface\\Icons\\INV_Misc_Book_15",
    "Interface\\Icons\\INV_Misc_Book_16",
    "Interface\\Icons\\INV_Misc_Book_17",
    -- Jewelry
    "Interface\\Icons\\INV_Jewelry_Ring_01",
    "Interface\\Icons\\INV_Jewelry_Ring_02",
    "Interface\\Icons\\INV_Jewelry_Ring_03",
    "Interface\\Icons\\INV_Jewelry_Ring_04",
    "Interface\\Icons\\INV_Jewelry_Ring_05",
    "Interface\\Icons\\INV_Jewelry_Ring_06",
    "Interface\\Icons\\INV_Jewelry_Ring_07",
    "Interface\\Icons\\INV_Jewelry_Ring_08",
    "Interface\\Icons\\INV_Jewelry_Ring_09",
    "Interface\\Icons\\INV_Jewelry_Ring_10",
    "Interface\\Icons\\INV_Jewelry_Necklace_01",
    "Interface\\Icons\\INV_Jewelry_Necklace_02",
    "Interface\\Icons\\INV_Jewelry_Necklace_03",
    "Interface\\Icons\\INV_Jewelry_Necklace_04",
    "Interface\\Icons\\INV_Jewelry_Necklace_05",
    "Interface\\Icons\\INV_Jewelry_Necklace_06",
    "Interface\\Icons\\INV_Jewelry_Necklace_07",
    "Interface\\Icons\\INV_Jewelry_Necklace_08",
    "Interface\\Icons\\INV_Jewelry_Talisman_01",
    "Interface\\Icons\\INV_Jewelry_Talisman_02",
    "Interface\\Icons\\INV_Jewelry_Talisman_03",
    "Interface\\Icons\\INV_Jewelry_Talisman_04",
    "Interface\\Icons\\INV_Jewelry_Talisman_05",
    "Interface\\Icons\\INV_Jewelry_Talisman_06",
    "Interface\\Icons\\INV_Jewelry_Talisman_07",
    "Interface\\Icons\\INV_Jewelry_Talisman_08",
    "Interface\\Icons\\INV_Jewelry_Talisman_09",
    "Interface\\Icons\\INV_Jewelry_Talisman_10",
    "Interface\\Icons\\INV_Jewelry_Talisman_11",
    "Interface\\Icons\\INV_Jewelry_Talisman_12",
    -- Gems & Stones
    "Interface\\Icons\\INV_Misc_Gem_01",
    "Interface\\Icons\\INV_Misc_Gem_02",
    "Interface\\Icons\\INV_Misc_Gem_03",
    "Interface\\Icons\\INV_Misc_Gem_Diamond_01",
    "Interface\\Icons\\INV_Misc_Gem_Diamond_02",
    "Interface\\Icons\\INV_Misc_Gem_Diamond_03",
    "Interface\\Icons\\INV_Misc_Gem_Emerald_01",
    "Interface\\Icons\\INV_Misc_Gem_Emerald_02",
    "Interface\\Icons\\INV_Misc_Gem_Emerald_03",
    "Interface\\Icons\\INV_Misc_Gem_Ruby_01",
    "Interface\\Icons\\INV_Misc_Gem_Ruby_02",
    "Interface\\Icons\\INV_Misc_Gem_Ruby_03",
    "Interface\\Icons\\INV_Misc_Gem_Sapphire_01",
    "Interface\\Icons\\INV_Misc_Gem_Sapphire_02",
    "Interface\\Icons\\INV_Misc_Gem_Sapphire_03",
    "Interface\\Icons\\INV_Misc_Gem_Opal_01",
    "Interface\\Icons\\INV_Misc_Gem_Opal_02",
    "Interface\\Icons\\INV_Misc_Gem_Opal_03",
    "Interface\\Icons\\INV_Misc_Gem_Pearl_01",
    "Interface\\Icons\\INV_Misc_Gem_Pearl_02",
    "Interface\\Icons\\INV_Misc_Gem_Pearl_03",
    "Interface\\Icons\\INV_Misc_Gem_Topaz_01",
    "Interface\\Icons\\INV_Misc_Gem_Topaz_02",
    "Interface\\Icons\\INV_Misc_Gem_Topaz_03",
    "Interface\\Icons\\INV_Stone_01",
    "Interface\\Icons\\INV_Stone_02",
    "Interface\\Icons\\INV_Stone_03",
    "Interface\\Icons\\INV_Stone_04",
    "Interface\\Icons\\INV_Stone_05",
    "Interface\\Icons\\INV_Stone_06",
    "Interface\\Icons\\INV_Stone_07",
    "Interface\\Icons\\INV_Stone_08",
    "Interface\\Icons\\INV_Stone_09",
    "Interface\\Icons\\INV_Stone_10",
    "Interface\\Icons\\INV_Stone_11",
    "Interface\\Icons\\INV_Stone_12",
    "Interface\\Icons\\INV_Stone_13",
    "Interface\\Icons\\INV_Stone_14",
    "Interface\\Icons\\INV_Stone_15",
    -- Food & Drink
    "Interface\\Icons\\INV_Misc_Food_01",
    "Interface\\Icons\\INV_Misc_Food_02",
    "Interface\\Icons\\INV_Misc_Food_03",
    "Interface\\Icons\\INV_Misc_Food_04",
    "Interface\\Icons\\INV_Misc_Food_05",
    "Interface\\Icons\\INV_Misc_Food_06",
    "Interface\\Icons\\INV_Misc_Food_07",
    "Interface\\Icons\\INV_Misc_Food_08",
    "Interface\\Icons\\INV_Misc_Food_09",
    "Interface\\Icons\\INV_Misc_Food_10",
    "Interface\\Icons\\INV_Drink_01",
    "Interface\\Icons\\INV_Drink_02",
    "Interface\\Icons\\INV_Drink_03",
    "Interface\\Icons\\INV_Drink_04",
    "Interface\\Icons\\INV_Drink_05",
    "Interface\\Icons\\INV_Drink_06",
    "Interface\\Icons\\INV_Drink_07",
    "Interface\\Icons\\INV_Drink_08",
    "Interface\\Icons\\INV_Drink_09",
    "Interface\\Icons\\INV_Drink_10",
    -- Potions
    "Interface\\Icons\\INV_Potion_01",
    "Interface\\Icons\\INV_Potion_02",
    "Interface\\Icons\\INV_Potion_03",
    "Interface\\Icons\\INV_Potion_04",
    "Interface\\Icons\\INV_Potion_05",
    "Interface\\Icons\\INV_Potion_06",
    "Interface\\Icons\\INV_Potion_07",
    "Interface\\Icons\\INV_Potion_08",
    "Interface\\Icons\\INV_Potion_09",
    "Interface\\Icons\\INV_Potion_10",
    "Interface\\Icons\\INV_Potion_11",
    "Interface\\Icons\\INV_Potion_12",
    "Interface\\Icons\\INV_Potion_13",
    "Interface\\Icons\\INV_Potion_14",
    "Interface\\Icons\\INV_Potion_15",
    "Interface\\Icons\\INV_Potion_16",
    "Interface\\Icons\\INV_Potion_17",
    "Interface\\Icons\\INV_Potion_18",
    "Interface\\Icons\\INV_Potion_19",
    "Interface\\Icons\\INV_Potion_20",
    -- Bags & Boxes
    "Interface\\Icons\\INV_Misc_Bag_01",
    "Interface\\Icons\\INV_Misc_Bag_02",
    "Interface\\Icons\\INV_Misc_Bag_03",
    "Interface\\Icons\\INV_Misc_Bag_04",
    "Interface\\Icons\\INV_Misc_Bag_05",
    "Interface\\Icons\\INV_Misc_Bag_06",
    "Interface\\Icons\\INV_Misc_Bag_07",
    "Interface\\Icons\\INV_Misc_Bag_08",
    "Interface\\Icons\\INV_Misc_Bag_09",
    "Interface\\Icons\\INV_Misc_Bag_10",
    "Interface\\Icons\\INV_Box_01",
    "Interface\\Icons\\INV_Box_02",
    "Interface\\Icons\\INV_Box_03",
    "Interface\\Icons\\INV_Box_04",
    "Interface\\Icons\\INV_Chest_Chain",
    "Interface\\Icons\\INV_Chest_Cloth_01",
    "Interface\\Icons\\INV_Chest_Cloth_02",
    "Interface\\Icons\\INV_Chest_Cloth_03",
    "Interface\\Icons\\INV_Chest_Leather_01",
    "Interface\\Icons\\INV_Chest_Leather_02",
    -- Keys
    "Interface\\Icons\\INV_Misc_Key_01",
    "Interface\\Icons\\INV_Misc_Key_02",
    "Interface\\Icons\\INV_Misc_Key_03",
    "Interface\\Icons\\INV_Misc_Key_04",
    "Interface\\Icons\\INV_Misc_Key_05",
    "Interface\\Icons\\INV_Misc_Key_06",
    "Interface\\Icons\\INV_Misc_Key_07",
    "Interface\\Icons\\INV_Misc_Key_08",
    "Interface\\Icons\\INV_Misc_Key_09",
    "Interface\\Icons\\INV_Misc_Key_10",
    "Interface\\Icons\\INV_Misc_Key_11",
    "Interface\\Icons\\INV_Misc_Key_12",
    -- Coins & Currency
    "Interface\\Icons\\INV_Misc_Coin_01",
    "Interface\\Icons\\INV_Misc_Coin_02",
    "Interface\\Icons\\INV_Misc_Coin_03",
    "Interface\\Icons\\INV_Misc_Coin_04",
    "Interface\\Icons\\INV_Misc_Coin_05",
    "Interface\\Icons\\INV_Misc_Coin_06",
    "Interface\\Icons\\INV_Misc_Coin_07",
    "Interface\\Icons\\INV_Misc_Coin_08",
    "Interface\\Icons\\INV_Misc_Coin_09",
    "Interface\\Icons\\INV_Misc_Coin_10",
    "Interface\\Icons\\INV_Misc_Coin_11",
    "Interface\\Icons\\INV_Misc_Coin_12",
    "Interface\\Icons\\INV_Misc_Coin_13",
    "Interface\\Icons\\INV_Misc_Coin_14",
    "Interface\\Icons\\INV_Misc_Coin_15",
    "Interface\\Icons\\INV_Misc_Coin_16",
    "Interface\\Icons\\INV_Misc_Coin_17",
    -- Maps
    "Interface\\Icons\\INV_Misc_Map_01",
    "Interface\\Icons\\INV_Misc_Map_02",
    "Interface\\Icons\\INV_Misc_Map_03",
    "Interface\\Icons\\INV_Misc_Map_04",
    "Interface\\Icons\\INV_Misc_Map_05",
    "Interface\\Icons\\INV_Misc_Map_06",
    "Interface\\Icons\\INV_Misc_Map_07",
    -- Weapons - Swords
    "Interface\\Icons\\INV_Sword_01",
    "Interface\\Icons\\INV_Sword_02",
    "Interface\\Icons\\INV_Sword_03",
    "Interface\\Icons\\INV_Sword_04",
    "Interface\\Icons\\INV_Sword_05",
    "Interface\\Icons\\INV_Sword_06",
    "Interface\\Icons\\INV_Sword_07",
    "Interface\\Icons\\INV_Sword_08",
    "Interface\\Icons\\INV_Sword_09",
    "Interface\\Icons\\INV_Sword_10",
    "Interface\\Icons\\INV_Weapon_Shortblade_01",
    "Interface\\Icons\\INV_Weapon_Shortblade_02",
    "Interface\\Icons\\INV_Weapon_Shortblade_03",
    "Interface\\Icons\\INV_Weapon_Shortblade_04",
    "Interface\\Icons\\INV_Weapon_Shortblade_05",
    -- Weapons - Daggers
    "Interface\\Icons\\INV_Weapon_Bow_01",
    "Interface\\Icons\\INV_Weapon_Bow_02",
    "Interface\\Icons\\INV_Weapon_Bow_03",
    "Interface\\Icons\\INV_Weapon_Bow_04",
    "Interface\\Icons\\INV_Weapon_Bow_05",
    "Interface\\Icons\\INV_Weapon_Crossbow_01",
    "Interface\\Icons\\INV_Weapon_Crossbow_02",
    "Interface\\Icons\\INV_Weapon_Crossbow_03",
    -- Weapons - Misc
    "Interface\\Icons\\INV_Staff_01",
    "Interface\\Icons\\INV_Staff_02",
    "Interface\\Icons\\INV_Staff_03",
    "Interface\\Icons\\INV_Staff_04",
    "Interface\\Icons\\INV_Staff_05",
    "Interface\\Icons\\INV_Wand_01",
    "Interface\\Icons\\INV_Wand_02",
    "Interface\\Icons\\INV_Wand_03",
    "Interface\\Icons\\INV_Wand_04",
    "Interface\\Icons\\INV_Wand_05",
    "Interface\\Icons\\INV_Axe_01",
    "Interface\\Icons\\INV_Axe_02",
    "Interface\\Icons\\INV_Axe_03",
    "Interface\\Icons\\INV_Hammer_01",
    "Interface\\Icons\\INV_Hammer_02",
    "Interface\\Icons\\INV_Hammer_03",
    "Interface\\Icons\\INV_Mace_01",
    "Interface\\Icons\\INV_Mace_02",
    "Interface\\Icons\\INV_Mace_03",
    -- Armor
    "Interface\\Icons\\INV_Shield_01",
    "Interface\\Icons\\INV_Shield_02",
    "Interface\\Icons\\INV_Shield_03",
    "Interface\\Icons\\INV_Shield_04",
    "Interface\\Icons\\INV_Shield_05",
    "Interface\\Icons\\INV_Shield_06",
    "Interface\\Icons\\INV_Helmet_01",
    "Interface\\Icons\\INV_Helmet_02",
    "Interface\\Icons\\INV_Helmet_03",
    "Interface\\Icons\\INV_Helmet_04",
    "Interface\\Icons\\INV_Helmet_05",
    "Interface\\Icons\\INV_Belt_01",
    "Interface\\Icons\\INV_Belt_02",
    "Interface\\Icons\\INV_Belt_03",
    "Interface\\Icons\\INV_Boots_01",
    "Interface\\Icons\\INV_Boots_02",
    "Interface\\Icons\\INV_Boots_03",
    "Interface\\Icons\\INV_Gauntlets_01",
    "Interface\\Icons\\INV_Gauntlets_02",
    "Interface\\Icons\\INV_Gauntlets_03",
    "Interface\\Icons\\INV_Shoulder_01",
    "Interface\\Icons\\INV_Shoulder_02",
    "Interface\\Icons\\INV_Shoulder_03",
    -- Misc Items
    "Interface\\Icons\\INV_Misc_QuestionMark",
    "Interface\\Icons\\INV_Misc_Orb_01",
    "Interface\\Icons\\INV_Misc_Orb_02",
    "Interface\\Icons\\INV_Misc_Orb_03",
    "Interface\\Icons\\INV_Misc_Orb_04",
    "Interface\\Icons\\INV_Misc_Orb_05",
    "Interface\\Icons\\INV_Misc_Rune_01",
    "Interface\\Icons\\INV_Misc_Rune_02",
    "Interface\\Icons\\INV_Misc_Rune_03",
    "Interface\\Icons\\INV_Misc_Rune_04",
    "Interface\\Icons\\INV_Misc_Rune_05",
    "Interface\\Icons\\INV_Misc_Rune_06",
    "Interface\\Icons\\INV_Misc_Bone_01",
    "Interface\\Icons\\INV_Misc_Bone_02",
    "Interface\\Icons\\INV_Misc_Bone_03",
    "Interface\\Icons\\INV_Misc_Bone_04",
    "Interface\\Icons\\INV_Misc_Bone_05",
    "Interface\\Icons\\INV_Misc_Bone_06",
    "Interface\\Icons\\INV_Misc_Bone_07",
    "Interface\\Icons\\INV_Misc_Bone_08",
    "Interface\\Icons\\INV_Misc_Bone_09",
    "Interface\\Icons\\INV_Misc_Bone_10",
    "Interface\\Icons\\INV_Misc_Head_01",
    "Interface\\Icons\\INV_Misc_Head_02",
    "Interface\\Icons\\INV_Misc_Head_03",
    "Interface\\Icons\\INV_Misc_Flower_01",
    "Interface\\Icons\\INV_Misc_Flower_02",
    "Interface\\Icons\\INV_Misc_Flower_03",
    "Interface\\Icons\\INV_Misc_Herb_01",
    "Interface\\Icons\\INV_Misc_Herb_02",
    "Interface\\Icons\\INV_Misc_Herb_03",
    "Interface\\Icons\\INV_Misc_Herb_04",
    "Interface\\Icons\\INV_Misc_Herb_05",
    "Interface\\Icons\\INV_Misc_Herb_06",
    "Interface\\Icons\\INV_Misc_Herb_07",
    "Interface\\Icons\\INV_Misc_Herb_08",
    "Interface\\Icons\\INV_Misc_Herb_09",
    "Interface\\Icons\\INV_Misc_Herb_10",
    -- Quest Items
    "Interface\\Icons\\INV_Misc_Idol_01",
    "Interface\\Icons\\INV_Misc_Idol_02",
    "Interface\\Icons\\INV_Misc_Idol_03",
    "Interface\\Icons\\INV_Misc_Idol_04",
    "Interface\\Icons\\INV_Misc_Idol_05",
    "Interface\\Icons\\INV_Misc_Cape_01",
    "Interface\\Icons\\INV_Misc_Cape_02",
    "Interface\\Icons\\INV_Misc_Cape_03",
    "Interface\\Icons\\INV_Misc_Cape_04",
    "Interface\\Icons\\INV_Misc_Cape_05",
    "Interface\\Icons\\INV_Misc_Cape_06",
    -- Spells
    "Interface\\Icons\\Spell_Holy_SealOfWisdom",
    "Interface\\Icons\\Spell_Holy_SealOfMight",
    "Interface\\Icons\\Spell_Holy_SealOfRighteousness",
    "Interface\\Icons\\Spell_Nature_HealingTouch",
    "Interface\\Icons\\Spell_Nature_Lightning",
    "Interface\\Icons\\Spell_Fire_FlameShock",
    "Interface\\Icons\\Spell_Fire_FireBolt",
    "Interface\\Icons\\Spell_Fire_Fireball",
    "Interface\\Icons\\Spell_Frost_FrostShock",
    "Interface\\Icons\\Spell_Frost_FrostBolt",
    "Interface\\Icons\\Spell_Frost_IceShock",
    "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
    "Interface\\Icons\\Spell_Shadow_DeathAndDecay",
    "Interface\\Icons\\Spell_Shadow_ShadowBolt",
    "Interface\\Icons\\Spell_Arcane_ArcaneMissiles",
    "Interface\\Icons\\Spell_Arcane_Blink",
    "Interface\\Icons\\Spell_Arcane_PortalOrgrimmar"
}

-- Function: Populate icon picker
local function PopulateIconPicker()
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

        -- Background
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\UI-EmptySlot")

        -- Icon
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(iconSize - 4)
        icon:SetHeight(iconSize - 4)
        icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        icon:SetTexture(iconPath)

        -- Highlight on hover
        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        highlight:SetBlendMode("ADD")

        -- Click handler
        do
            local selectedIcon = iconPath
            btn:SetScript("OnClick", function()
                iconEdit:SetText(selectedIcon)
                iconPickerFrame:Hide()
            end)
        end

        -- Tooltip
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
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

-- Open icon picker button handler
iconPickerBtn:SetScript("OnClick", function()
    PopulateIconPicker()
    iconPickerFrame:Show()
end)

-- Current editing item variable
local currentEditingItem = nil

-- Function: Create or update an item
local function SaveItem()
    -- Safety check: ensure RPMasterDB is initialized
    if not RPMasterDB then
        RPMasterDB = {
            itemLibrary = {},
            nextItemID = 1
        }
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
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[Debug]|r Editing item ID: "..tostring(itemID), 1, 1, 0)

        if RPMasterDB.itemLibrary[itemID] then
            RPMasterDB.itemLibrary[itemID].name = name
            RPMasterDB.itemLibrary[itemID].icon = icon
            RPMasterDB.itemLibrary[itemID].tooltip = tooltip
            RPMasterDB.itemLibrary[itemID].content = content
            -- Ensure GUID exists
            if not RPMasterDB.itemLibrary[itemID].guid then
                RPMasterDB.itemLibrary[itemID].guid = GenerateGUID()
            end
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r Item updated! ID: "..itemID..", GUID: "..RPMasterDB.itemLibrary[itemID].guid, 0, 1, 0)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Error: Item ID "..itemID.." not found in library!", 1, 0, 0)
            return
        end
    else
        -- Create new item with GUID
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[Debug]|r Creating new item", 1, 1, 0)
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
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[RPMaster]|r Item created! ID: "..newItem.id..", GUID: "..newItem.guid, 0, 1, 0)
    end

    -- Clear editing state and close
    currentEditingItem = nil
    editFrame:Hide()
    RPMaster_RefreshItemList()
end

-- Function: Delete an item
local function DeleteItem()
    if currentEditingItem then
        RPMasterDB.itemLibrary[currentEditingItem.id] = nil
        editFrame:Hide()
        RPMaster_RefreshItemList()
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8800[RPMaster]|r Item deleted!", 1, 0.5, 0)
    end
end

saveBtn:SetScript("OnClick", SaveItem)
deleteBtn:SetScript("OnClick", DeleteItem)

-- Function: Open edit form
local function OpenEditForm(item)
    currentEditingItem = item

    if item then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[Debug]|r OpenEditForm - Editing item ID: "..tostring(item.id), 1, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[Debug]|r   Name: "..tostring(item.name), 1, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[Debug]|r   Icon: "..tostring(item.icon), 1, 1, 0)

        nameEdit:SetText(item.name or "")
        iconEdit:SetText(item.icon or "Interface\\Icons\\INV_Misc_Note_01")
        tooltipEdit:SetText(item.tooltip or "")
        contentEdit:SetText(item.content or "")

        -- Force update the edit boxes
        nameEdit:HighlightText(0, 0)
        iconEdit:HighlightText(0, 0)

        deleteBtn:Show()

        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[Debug]|r   Form fields set!", 1, 1, 0)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[Debug]|r OpenEditForm - Creating NEW item", 1, 1, 0)
        nameEdit:SetText("")
        iconEdit:SetText("Interface\\Icons\\INV_Misc_Note_01")
        tooltipEdit:SetText("")
        contentEdit:SetText("")
        deleteBtn:Hide()
    end

    editFrame:Show()
    editFrame:Raise()  -- Bring to front
end

-- Function: Refresh item list
function RPMaster_RefreshItemList()
    -- Safety check: ensure RPMasterDB is initialized
    if not RPMasterDB then
        RPMasterDB = {
            itemLibrary = {},
            nextItemID = 1
        }
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

        -- Item frame
        local itemFrame = CreateFrame("Frame", nil, scrollChild)
        itemFrame:SetWidth(580)
        itemFrame:SetHeight(50)
        itemFrame:SetPoint("TOPLEFT", 10, yOffset)

        local bg = itemFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(0.1, 0.1, 0.1, 0.5)

        -- Icon
        local iconTex = itemFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetWidth(40)
        iconTex:SetHeight(40)
        iconTex:SetPoint("LEFT", 5, 0)
        iconTex:SetTexture(item.icon)

        -- Name
        local nameText = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        nameText:SetPoint("LEFT", iconTex, "RIGHT", 10, 0)
        nameText:SetText(item.name)

        -- Edit button
        local editBtn = CreateFrame("Button", nil, itemFrame, "UIPanelButtonTemplate")
        editBtn:SetPoint("RIGHT", -120, 0)
        editBtn:SetWidth(80)
        editBtn:SetHeight(25)
        editBtn:SetText("Edit")
        -- Create closure with explicit item reference
        do
            local itemToEdit = item
            editBtn:SetScript("OnClick", function()
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[Debug]|r Edit button clicked for item ID: "..tostring(itemToEdit.id), 1, 1, 0)
                OpenEditForm(itemToEdit)
            end)
        end

        -- Give button
        local giveBtn = CreateFrame("Button", nil, itemFrame, "UIPanelButtonTemplate")
        giveBtn:SetPoint("RIGHT", -30, 0)
        giveBtn:SetWidth(80)
        giveBtn:SetHeight(25)
        giveBtn:SetText("Give")
        -- Create closure with explicit item reference
        do
            local itemToGive = item
            giveBtn:SetScript("OnClick", function()
                RPMaster_ShowPlayerSelector(itemToGive)
            end)
        end
        
        yOffset = yOffset - 60
    end
    
    scrollChild:SetHeight(math.max(1, itemCount * 60))
end

-- Function: Player selector for giving item
function RPMaster_ShowPlayerSelector(item)
    -- Create dropdown menu with raid members
    local menu = {}
    
    for i = 1, GetNumRaidMembers() do
        local name = GetRaidRosterInfo(i)
        if name and name ~= UnitName("player") then
            table.insert(menu, {
                text = name,
                func = function()
                    RPMaster_GiveItemToPlayer(item, name)
                end
            })
        end
    end
    
    if table.getn(menu) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r No players in raid!", 1, 0, 0)
        return
    end
    
    local dropdown = CreateFrame("Frame", "RPMasterPlayerDropdown", UIParent, "UIDropDownMenuTemplate")
    EasyMenu(menu, dropdown, "cursor", 0, 0, "MENU")
end

-- Function: Send item to player
function RPMaster_GiveItemToPlayer(item, playerName)
    -- Encode item as string for sending
    local data = string.format("GIVE|%d|%s|%s|%s|%s",
        item.id,
        item.name:gsub("|", ""),
        item.icon:gsub("|", ""),
        (item.tooltip or ""):gsub("|", ""),
        (item.content or ""):gsub("|", "")
    )
    
    SendAddonMessage(ADDON_PREFIX, data, "WHISPER", playerName)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF00FF00[RPMaster]|r Item '%s' sent to %s", item.name, playerName), 0, 1, 0)
end

-- Action buttons
newItemBtn:SetScript("OnClick", function()
    if not isLoaded then return end
    OpenEditForm(nil)
end)

refreshBtn:SetScript("OnClick", function()
    if not isLoaded then return end
    RPMaster_RefreshItemList()
end)

-- Slash command
SLASH_RPMASTER1 = "/rpmaster"
SLASH_RPMASTER2 = "/rpm"
SlashCmdList["RPMASTER"] = function(msg)
    if not isLoaded then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[RPMaster]|r Addon not yet loaded, wait a few seconds.", 1, 0, 0)
        return
    end

    if RPMasterFrame:IsShown() then
        RPMasterFrame:Hide()
    else
        RPMasterFrame:Show()
        RPMaster_RefreshItemList()
    end
end
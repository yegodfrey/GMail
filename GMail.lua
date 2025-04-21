-- GMail.lua
-- GMail addon for automating mail sending

-- Localization
local L = {}
local locale = GetLocale()

-- English (enUS) - Default
L["enUS"] = {
    -- Panel
    ["SETTINGS_PANEL_TITLE"] = "|cFFFFD700GMail %s|r",
    ["GMAIL_SECTION"] = "Mail Automation",
    ["RECIPIENT"] = "Default Recipient",
    ["RECIPIENT_TOOLTIP"] = "Set the default mail recipient",
    ["KEYBINDING"] = "Keybinding",
    ["ITEM_ID"] = "Item ID",
    ["ADD_BUTTON"] = "Add",
    ["SHOW_ITEM_LIST"] = "Show Item List",
    ["HIDE_ITEM_LIST"] = "Hide Item List",
    ["INVALID_ITEM_ID"] = "Item ID %d not yet loaded, retrying...",
    ["ONE_CLICK_MAIL"] = "One-Click Mail",

    -- GMail
    ["OPEN_MAILBOX"] = "Please open the mailbox first.",
    ["ATTACHMENTS_FULL"] = "Mail attachments full (max 12), stopping item addition",
    ["NO_ITEMS_FOUND"] = "No mailable items found in bags",
    ["ATTACHMENT_FAILED"] = "Failed to attach all items, please try again",
}

-- Chinese (zhCN)
L["zhCN"] = {
    -- Panel
    ["SETTINGS_PANEL_TITLE"] = "|cFFFFD700GMail %s|r",
    ["GMAIL_SECTION"] = "邮件自动化",
    ["RECIPIENT"] = "默认收件人",
    ["RECIPIENT_TOOLTIP"] = "设置默认邮件收件人",
    ["KEYBINDING"] = "快捷键",
    ["ITEM_ID"] = "物品ID",
    ["ADD_BUTTON"] = "添加",
    ["SHOW_ITEM_LIST"] = "显示物品列表",
    ["HIDE_ITEM_LIST"] = "隐藏物品列表",
    ["INVALID_ITEM_ID"] = "物品ID %d 尚未加载，正在重试...",
    ["ONE_CLICK_MAIL"] = "一键邮寄",

    -- GMail
    ["OPEN_MAILBOX"] = "先打开邮箱。",
    ["ATTACHMENTS_FULL"] = "邮件附件已满（最多12个），停止添加物品",
    ["NO_ITEMS_FOUND"] = "背包中未找到可邮寄的物品",
    ["ATTACHMENT_FAILED"] = "无法附上所有物品，请重试",
}

-- Simplify localization validation
local function MergeLocalization(loc)
    for key, value in pairs(L["enUS"]) do
        if not loc[key] then
            loc[key] = value
        end
    end
end

-- Set active localization
local GMailL = L[locale] or L["enUS"]
MergeLocalization(GMailL)

-- Utility Functions
local function DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

local function tContains(table, value)
    for _, v in ipairs(table) do
        if v == value then return true end
    end
    return false
end

-- Default Configuration
local defaultConfig = {
    Settings = {
        recipient = "",
        keyBinding = "F10",
        itemIDs = {},
    },
}

-- Initialize Database
function InitializeDB()
    if not GMailDB or type(GMailDB) ~= "table" then
        GMailDB = DeepCopy(defaultConfig)
    else
        for k, v in pairs(defaultConfig.Settings) do
            if GMailDB.Settings[k] == nil then
                GMailDB.Settings[k] = DeepCopy(v)
            end
        end
    end
end

-- Helper for Tooltip
function SetupTooltip(widget, tooltip)
    if tooltip then
        widget:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
end

-- Create EditBox Helper
function CreateEditBox(parent, width, height, labelText, tooltip, onChange, key, isNumeric, allowEmpty)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, height or 40)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 0, -5)
    label:SetText(labelText or "Label")
    local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    editBox:SetPoint("TOPLEFT", 0, -20)
    editBox:SetSize(width - 10, 24)
    editBox:SetAutoFocus(false)
    if isNumeric then
        editBox:SetNumeric(true)
    end
    editBox:SetText(tostring(GMailDB.Settings[key] or ""))
    editBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if not allowEmpty and text == "" then
            self:SetText(tostring(GMailDB.Settings[key] or ""))
        else
            onChange(text)
        end
        self:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        local text = self:GetText()
        if not allowEmpty and text == "" then
            self:SetText(tostring(GMailDB.Settings[key] or ""))
        else
            onChange(text)
        end
    end)
    SetupTooltip(editBox, tooltip)
    return frame
end

-- GMail Functionality
local function GMail_MailItem()
    if not MailFrame:IsShown() then
        print(GMailL["OPEN_MAILBOX"])
        return
    end
    local selectedItems = GMailDB.Settings.itemIDs
    if #selectedItems == 0 then
        print(GMailL["NO_ITEMS_FOUND"])
        return
    end
    local bagItems = {}
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID and tContains(selectedItems, itemID) then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and not info.isLocked then
                    table.insert(bagItems, { bag = bag, slot = slot, itemID = itemID })
                end
            end
        end
    end
    if #bagItems == 0 then
        print(GMailL["NO_ITEMS_FOUND"])
        return
    end

    local recipient = GMailDB.Settings.recipient
    if recipient == "" then
        recipient = UnitName("player")
    end

    -- Initialize mail composition
    SetSendMailShowing(true)
    SendMailNameEditBox:SetText(recipient)
    SendMailSubjectEditBox:SetText("GMail Items")

    -- Disable mail frame interaction
    MailFrame:EnableMouse(false)
    SendMailMailButton:Enable(false)

    -- Process attachments synchronously
    local attachmentCount = 0
    local currentIndex = 1
    local updateFrame = CreateFrame("Frame")
    local elapsedSinceLastCheck = 0
    updateFrame:SetScript("OnUpdate", function(self, elapsed)
        elapsedSinceLastCheck = elapsedSinceLastCheck + elapsed
        if elapsedSinceLastCheck < 0.7 then return end -- Check every 0.7 seconds
        elapsedSinceLastCheck = 0

        if currentIndex > #bagItems or attachmentCount >= 12 then
            -- Verify all attachments
            local attachedItems = {}
            for i = 1, 12 do
                local _, itemID = GetSendMailItem(i)
                if itemID then
                    table.insert(attachedItems, itemID)
                end
            end
            local allAttached = true
            for _, item in ipairs(bagItems) do
                if not tContains(attachedItems, item.itemID) then
                    allAttached = false
                    break
                end
            end
            if allAttached and MailFrame:IsShown() then
                SendMail(recipient, "GMail Items", "")
            else
                print(GMailL["ATTACHMENT_FAILED"])
                ClearSendMail()
            end
            self:SetScript("OnUpdate", nil)
            MailFrame:EnableMouse(true)
            SendMailMailButton:Enable(true)
            return
        end

        local item = bagItems[currentIndex]
        if attachmentCount < 12 then
            C_Container.UseContainerItem(item.bag, item.slot)
            -- Check if item was attached
            local attached = false
            for i = 1, 12 do
                local _, itemID = GetSendMailItem(i)
                if itemID == item.itemID then
                    attached = true
                    break
                end
            end
            if attached then
                attachmentCount = attachmentCount + 1
                currentIndex = currentIndex + 1
            end
        else
            print(GMailL["ATTACHMENTS_FULL"])
            currentIndex = currentIndex + 1
        end
    end)
end

local frame = CreateFrame("Frame")
GMail = { frame = frame }

function GMail_UpdateKeyBinding(key)
    if not key then return end
    ClearOverrideBindings(frame)
    SetOverrideBindingClick(frame, true, key, "GMailButton")
end

function InitializeGMail()
    InitializeDB()
    local mailButton = CreateFrame("Button", "GMailButton", nil, "SecureActionButtonTemplate")
    mailButton:SetScript("OnClick", GMail_MailItem)
    GMail_UpdateKeyBinding(GMailDB.Settings.keyBinding)

    -- Create One-Click Mail button
    local oneClickButton = CreateFrame("Button", "GMailOneClickButton", MailFrame, "UIPanelButtonTemplate")
    oneClickButton:SetSize(120, 25)
    oneClickButton:SetPoint("LEFT", MailFrame, "RIGHT", 10, 0)
    oneClickButton:SetText(GMailL["ONE_CLICK_MAIL"])
    oneClickButton:SetScript("OnClick", GMail_MailItem)
    oneClickButton:Hide()

    -- Show/Hide button with MailFrame
    MailFrame:HookScript("OnShow", function() oneClickButton:Show() end)
    MailFrame:HookScript("OnHide", function() oneClickButton:Hide() end)
end

function UpdateGMailItemList(frame)
    if not frame then return end
    if frame.items then
        for _, item in ipairs(frame.items) do
            for _, widget in ipairs(item) do
                widget:Hide()
            end
        end
    end
    frame.items = {}
    local yOffset = -10
    for i, id in ipairs(GMailDB.Settings.itemIDs) do
        local name, _, _, _, _, _, _, _, _, texture = C_Item.GetItemInfo(id)
        local row = {}
        local icon = CreateFrame("Button", nil, frame)
        icon:SetSize(24, 24)
        icon:SetPoint("TOPLEFT", 10, yOffset)
        local iconTexture = icon:CreateTexture(nil, "ARTWORK")
        iconTexture:SetAllPoints()
        iconTexture:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        icon:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(id)
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row[1] = icon
        local nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameLabel:SetPoint("LEFT", icon, "RIGHT", 10, 0)
        nameLabel:SetText(name or "Item " .. id)
        row[2] = nameLabel
        local deleteButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        deleteButton:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)
        deleteButton:SetSize(24, 24)
        deleteButton:SetScript("OnClick", function()
            for j, itemID in ipairs(GMailDB.Settings.itemIDs) do
                if itemID == id then
                    table.remove(GMailDB.Settings.itemIDs, j)
                    break
                end
            end
            UpdateGMailItemList(frame)
        end)
        row[3] = deleteButton
        table.insert(frame.items, row)
        yOffset = yOffset - 30
    end
    frame:SetHeight(math.abs(yOffset) + 10)
end

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "GET_ITEM_INFO_RECEIVED" and GMail.pendingItemIDs and GMail.pendingItemIDs[arg1] then
        GMail.pendingItemIDs[arg1] = nil
        if not next(GMail.pendingItemIDs) then
            self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        end
        if GMailPanel and GMailPanel.itemListFrame then
            UpdateGMailItemList(GMailPanel.itemListContent)
        end
    end
end)

-- Create Settings Panel
function CreateGMPanel()
    if GMailPanel then
        GMailPanel:SetShown(not GMailPanel:IsShown())
        if GMailPanel:IsShown() and GMailPanel.itemListFrame then
            UpdateGMailItemList(GMailPanel.itemListContent)
        end
        return
    end
    local panel = CreateFrame("Frame", "GMailPanel", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(600, 500)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    local version = C_AddOns.GetAddOnMetadata("GMail", "Version") or "1.0.0"
    title:SetText(string.format(GMailL["SETTINGS_PANEL_TITLE"], version))

    -- Scroll Frame
    local scrollFrame = CreateFrame("ScrollFrame", "GMailScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(560, 600)
    scrollFrame:SetScrollChild(scrollChild)

    -- Content Frame
    local gMailContent = CreateFrame("Frame", nil, scrollChild)
    gMailContent:SetSize(540, 580)
    gMailContent:SetPoint("TOPLEFT", 10, -10)

    -- Section: Recipient
    local recipientSection = gMailContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    recipientSection:SetPoint("TOPLEFT", 0, -10)
    recipientSection:SetText(GMailL["GMAIL_SECTION"])
    local recipientEdit = CreateEditBox(gMailContent, 250, 40, GMailL["RECIPIENT"], GMailL["RECIPIENT_TOOLTIP"], function(text)
        GMailDB.Settings.recipient = text
    end, "recipient", false, true)
    recipientEdit:SetPoint("TOPLEFT", 10, -40)

    -- Section: Keybinding
    local keySection = gMailContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    keySection:SetPoint("TOPLEFT", 0, -100)
    keySection:SetText(GMailL["KEYBINDING"])
    local keyEdit = CreateFrame("Button", nil, gMailContent, "UIPanelButtonTemplate")
    keyEdit:SetSize(120, 30)
    keyEdit:SetPoint("TOPLEFT", 10, -130)
    keyEdit:SetText(GMailDB.Settings.keyBinding or "F10")
    keyEdit:SetScript("OnClick", function(self)
        self:SetText("Press a key...")
        self:EnableKeyboard(true)
        self:SetScript("OnKeyDown", function(_, key)
            if key ~= "ESCAPE" then
                GMailDB.Settings.keyBinding = key
                self:SetText(key)
                GMail_UpdateKeyBinding(key)
            else
                self:SetText(GMailDB.Settings.keyBinding or "F10")
            end
            self:EnableKeyboard(false)
            self:SetScript("OnKeyDown", nil)
        end)
    end)

    -- Section: Item Input
    local itemSection = gMailContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    itemSection:SetPoint("TOPLEFT", 0, -180)
    itemSection:SetText(GMailL["ITEM_ID"])
    local itemInputBox = CreateFrame("EditBox", nil, gMailContent, "InputBoxTemplate")
    itemInputBox:SetSize(120, 30)
    itemInputBox:SetPoint("TOPLEFT", 10, -210)
    itemInputBox:SetAutoFocus(false)
    itemInputBox:SetNumeric(true)
    local addButton = CreateFrame("Button", nil, gMailContent, "UIPanelButtonTemplate")
    addButton:SetSize(100, 30)
    addButton:SetPoint("LEFT", itemInputBox, "RIGHT", 10, 0)
    addButton:SetText(GMailL["ADD_BUTTON"])
    addButton:SetScript("OnClick", function()
        local id = tonumber(itemInputBox:GetText())
        if id then
            local name = C_Item.GetItemInfo(id)
            if name then
                if not tContains(GMailDB.Settings.itemIDs, id) then
                    table.insert(GMailDB.Settings.itemIDs, id)
                    if panel.itemListFrame and panel.itemListFrame:IsShown() then
                        UpdateGMailItemList(panel.itemListContent)
                    end
                end
            else
                GMail.pendingItemIDs = GMail.pendingItemIDs or {}
                if not GMail.pendingItemIDs[id] then
                    GMail.pendingItemIDs[id] = true
                    print(string.format(GMailL["INVALID_ITEM_ID"], id))
                end
                GMail.frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
            end
        end
        itemInputBox:SetText("")
        itemInputBox:ClearFocus()
    end)
    itemInputBox:SetScript("OnEnterPressed", function(self) addButton:Click() end)

    -- Section: Item List
    local itemListToggle = CreateFrame("Button", nil, gMailContent, "UIPanelButtonTemplate")
    itemListToggle:SetSize(140, 30)
    itemListToggle:SetPoint("TOPLEFT", 10, -260)
    itemListToggle:SetText(GMailL["SHOW_ITEM_LIST"])
    local itemListFrame = CreateFrame("Frame", nil, gMailContent, "ThinBorderTemplate")
    itemListFrame:SetPoint("TOPLEFT", 10, -300)
    itemListFrame:SetSize(520, 250)
    itemListFrame:Hide()
    panel.itemListFrame = itemListFrame
    local itemListScroll = CreateFrame("ScrollFrame", "GMailItemScroll", itemListFrame, "UIPanelScrollFrameTemplate")
    itemListScroll:SetPoint("TOPLEFT", 5, -5)
    itemListScroll:SetPoint("BOTTOMRIGHT", -25, 5)
    local itemListContent = CreateFrame("Frame", nil, itemListScroll)
    itemListContent:SetSize(490, 1)
    itemListScroll:SetScrollChild(itemListContent)
    panel.itemListContent = itemListContent
    itemListToggle:SetScript("OnClick", function()
        if itemListFrame:IsShown() then
            itemListFrame:Hide()
            itemListToggle:SetText(GMailL["SHOW_ITEM_LIST"])
        else
            itemListFrame:Show()
            itemListToggle:SetText(GMailL["HIDE_ITEM_LIST"])
            UpdateGMailItemList(panel.itemListContent)
        end
    end)

    GMailPanel = panel
    UpdateGMailItemList(panel.itemListContent)
end

-- Slash Command
SLASH_GM1 = "/gm"
SlashCmdList["GM"] = CreateGMPanel

-- Initialize Addon
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "GMail" then
    elseif event == "PLAYER_LOGIN" then
        InitializeGMail()
    end
end)
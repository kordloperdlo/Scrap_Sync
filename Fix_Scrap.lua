-- Fix_Scrap.lua
-- Универсальный фикс для Scrap 3.3.5 с улучшенным управлением хламом и биндингом

local L = LibStub("AceLocale-3.0"):GetLocale("Scrap_Sync", true)

local function InitSirusFix()
    if not Scrap then
        ScrapSync_Debug(L["ScrapNotFound"] or "Scrap not found")
        return
    end

    -- Поиск таблицы списка
    local List = nil
    local listCandidates = {
        { name = "Scrap_List", ref = _G.Scrap_List },
        { name = "Scrap_Junk", ref = _G.Scrap_Junk },
        { name = "Scrap_CharSets.list", ref = _G.Scrap_CharSets and _G.Scrap_CharSets.list },
    }
    for _, cand in ipairs(listCandidates) do
        if cand.ref and type(cand.ref) == "table" then
            List = cand.ref
            ScrapSync_Debug((L["ListTableFound"] or "Found list table: %s"):format(cand.name))
            break
        end
    end
    if not List then
        ScrapSync_Debug(L["ListTableCreated"] or "List table not found, creating Scrap_List")
        _G.Scrap_List = {}
        List = _G.Scrap_List
    end

    local function CountList()
        local cnt = 0
        for k, v in pairs(List) do
            if v then cnt = cnt + 1 end
        end
        return cnt
    end
    ScrapSync_Debug((L["ListElementsCount"] or "Elements at start: %d"):format(CountList()))

    -- Оригинальная локализация Scrap
    local ScrapL = _G.Scrap_Locals or {}

    -- Функция добавления/удаления (выводит сообщение как в оригинале)
    local function ToggleItem(id, itemLink)
        if not id then
            ScrapSync_Debug(L["ToggleItemIdNil"] or "ToggleItem: id is nil")
            return
        end
        local isJunk = Scrap.IsJunk and Scrap:IsJunk(id) or (List[id] == true)
        local newState = not isJunk
        List[id] = newState and true or nil

        local itemName = GetItemInfo(id) or ("item:"..id)
        itemLink = itemLink or select(2, GetItemInfo(id)) or ("item:"..id)
        
        local stateStr = newState and (L["AddedShort"] or "added") or (L["RemovedShort"] or "removed")
        ScrapSync_Debug((L["ToggleItemState"] or "ToggleItem: id=%d (%s) state: %s, total: %d"):format(id, itemName, stateStr, CountList()), itemLink)

        -- Вывод сообщения точно как в оригинальном Scrap (зелёный текст, ссылка)
        if Scrap.Print then
            local template = newState and (ScrapL["Added"] or "Added to junk list: %s") or (ScrapL["Removed"] or "Removed from junk list: %s")
            -- Убедимся, что шаблон содержит %s, иначе добавим
            if not template:find("%%s") then
                template = template .. " %s"
            end
            Scrap:Print(template, itemLink, "LOOT")
        end

        if Scrap.UpdateButtonState then Scrap:UpdateButtonState() end
        if Scrap.Visualizer and Scrap.Visualizer.Update then Scrap.Visualizer:Update() end
    end

    -- Поиск кнопки Scrap
    local btn = _G["Scrap"]
    if not btn then
        local holder = _G["MerchantFrameButtonHolder"]
        if holder then
            for i = 1, holder:GetNumChildren() do
                local child = select(i, holder:GetChildren())
                if child and child:GetObjectType() == "Button" then
                    btn = child
                    break
                end
            end
        end
    end
    if not btn then
        ScrapSync_Debug(L["ButtonNotFound"] or "Scrap button not found")
        return
    end
    ScrapSync_Debug((L["ButtonFound"] or "Scrap button found: %s"):format(btn:GetName() or "unnamed"))

    local originalOnClick = btn:GetScript("OnClick")
    local origState = originalOnClick and (L["Present"] or "present") or (L["Missing"] or "missing")
    ScrapSync_Debug((L["OriginalOnClick"] or "Original OnClick: %s"):format(origState))

    local ourHandler
    ourHandler = function(self, button, down)
        ScrapSync_Debug((L["OnClickCalled"] or "OnClick called, button=%s"):format(tostring(button)))
        -- Предмет на курсоре
        local cursorType, cursorID = GetCursorInfo()
        if cursorType == "item" and cursorID then
            ScrapSync_Debug((L["ItemOnCursor"] or "Item on cursor: %d"):format(cursorID))
            GameTooltip:Hide()
            ClearCursor()
            ToggleItem(cursorID)
            if self.GetScript then self:GetScript('OnLeave')() end
            return
        end

        -- Предмет под мышью (в сумке)
        local focus = GetMouseFocus()
        if focus and focus.GetObjectType and focus:GetObjectType() == "Button" and focus:GetParent() and focus:GetParent().GetID then
            local parent = focus:GetParent()
            if parent and parent.GetID then
                local bag = parent:GetID()
                local slot = focus:GetID()
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local itemID = tonumber(link:match("item:(%d+)"))
                    ScrapSync_Debug((L["ItemUnderMouse"] or "Item under mouse: bag=%d slot=%d id=%s"):format(bag, slot, tostring(itemID)), link)
                    if itemID then
                        ToggleItem(itemID, link)
                        if self.GetScript then self:GetScript('OnLeave')() end
                        return
                    end
                else
                    ScrapSync_Debug((L["NoItemLink"] or "No item link (bag=%d slot=%d)"):format(bag, slot))
                end
            else
                ScrapSync_Debug(L["ParentNoGetID"] or "Parent has no GetID")
            end
        else
            ScrapSync_Debug(L["FocusNotItemButton"] or "Focus is not an item button in bag")
        end

        -- Оригинальное поведение
        ScrapSync_Debug(L["CallingOriginal"] or "Calling original OnClick")
        if originalOnClick then
            originalOnClick(self, button, down)
        else
            if button == "LeftButton" and Scrap.SellJunk then
                Scrap:SellJunk()
            elseif button == "RightButton" and LoadAddOn and LoadAddOn("Scrap_Options") then
                if ScrapOptions and ScrapOptions.ToggleDropdown then
                    ScrapOptions:ToggleDropdown()
                end
            end
        end
    end

    btn:SetScript("OnClick", ourHandler)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ScrapSync_Debug(L["OurOnClickSet"] or "Our OnClick set")

    -- Защита от переустановки OnClick
    local oldSetScript = btn.SetScript
    btn.SetScript = function(self, script, handler)
        if script == "OnClick" and handler ~= ourHandler then
            ScrapSync_Debug(L["SetScriptIntercept"] or "SetScript OnClick intercepted, saving as original")
            originalOnClick = handler
            return oldSetScript(self, script, ourHandler)
        end
        return oldSetScript(self, script, handler)
    end

    -- Alt+Click (только при включенной галке)
    hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, button)
        if ScrapSync_AltClickEnabled and IsAltKeyDown() then
            local bag = self:GetParent():GetID()
            local slot = self:GetID()
            local link = GetContainerItemLink(bag, slot)
            if link then
                local itemID = tonumber(link:match("item:(%d+)"))
                if itemID then
                    ScrapSync_Debug((L["AltClickId"] or "Alt+Click id=%d"):format(itemID), link)
                    ToggleItem(itemID, link)
                end
            end
        end
    end)

    -- Контекстное меню
    hooksecurefunc("UnitPopup_ShowMenu", function(dropdownMenu, which)
        if which == "ITEM" then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "|cff00ff00[Scrap]|r " .. (ScrapL["List"] or L["Junk"] or "Junk")
            info.notCheckable = true
            info.func = function()
                local link = G_ItemRef or ItemRefTooltip.itemLink
                if link then
                    local itemID = tonumber(link:match("item:(%d+)"))
                    if itemID then
                        ScrapSync_Debug((L["ContextMenuId"] or "Context menu id=%d"):format(itemID), link)
                        ToggleItem(itemID, link)
                    end
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- Функция для биндинга
    local function ToggleBinding()
        ScrapSync_Debug(L["BindingCalled"] or "Binding called")
        local itemID = nil
        local itemLink = nil

        -- 1. Тултип
        if GameTooltip:IsVisible() then
            local _, link = GameTooltip:GetItem()
            if link then
                itemID = tonumber(link:match("item:(%d+)"))
                itemLink = link
                ScrapSync_Debug((L["BindingTooltip"] or "Binding (tooltip): id=%s"):format(tostring(itemID)), link)
            end
        end

        -- 2. Фокус мыши
        if not itemID then
            local focus = GetMouseFocus()
            if focus and focus.GetObjectType and focus:GetObjectType() == "Button" and focus:GetParent() and focus:GetParent().GetID then
                local parent = focus:GetParent()
                if parent and parent.GetID then
                    local bag = parent:GetID()
                    local slot = focus:GetID()
                    local link = GetContainerItemLink(bag, slot)
                    if link then
                        itemID = tonumber(link:match("item:(%d+)"))
                        itemLink = link
                        ScrapSync_Debug((L["BindingFocus"] or "Binding (focus): bag=%d slot=%d id=%s"):format(bag, slot, tostring(itemID)), link)
                    end
                end
            end
        end

        -- 3. Курсор
        if not itemID then
            local cursorType, cursorID = GetCursorInfo()
            if cursorType == "item" and cursorID then
                itemID = cursorID
                itemLink = select(2, GetCursorInfo()) or GetItemInfo(cursorID)
                ScrapSync_Debug((L["BindingCursor"] or "Binding (cursor): id=%d"):format(itemID), itemLink)
            end
        end

        if itemID then
            ToggleItem(itemID, itemLink)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00[Scrap]|r " .. (L["BindingNoItemShort"] or "Could not identify item."))
        end
    end

    _G.ScrapSync_ToggleBinding = ToggleBinding
    if not _G.SCRAP_SYNC_TOGGLE then
        _G.SCRAP_SYNC_TOGGLE = ToggleBinding
    end

    print("|cff00ff00[Scrap_Sync]|r " .. (L["FixActivated"] or "Fix activated."))
end

-- Загрузка
if IsAddOnLoaded("Scrap") then
    InitSirusFix()
else
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, _, addon)
        if addon == "Scrap" then
            InitSirusFix()
        end
    end)
end
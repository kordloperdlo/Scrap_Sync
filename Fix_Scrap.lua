-- Фикс ошибки nil value в оригинальном Scrap
local function ApplyScrapFix()
    if Scrap and Scrap.Toggle then
        local originalToggle = Scrap.Toggle
        Scrap.Toggle = function(self, item, ...)
            if not item then return end -- Защита от nil
            return originalToggle(self, item, ...)
        end
    end
end

-- Безопасная инициализация после загрузки Scrap
if IsAddOnLoaded("Scrap") then
    ApplyScrapFix()
else
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, event, addon)
        if addon == "Scrap" then
            ApplyScrapFix()
            self:UnregisterEvent("ADDON_LOADED")
        end
    end)
end

-- Предположим, у вас есть функция вызова при бинде
local function OnBindKey()
    -- Получение предмета под курсором
    local item = GetItemUnderCursor() -- Ваша функция получения предмета
    if not item then
        print("Курсор не на предмете или предмета нет.")
        return
    end

    -- Далее логика определения мусора или действий
    if IsTrash(item) then
        -- Отметить как мусор или что-то делать
        print("Предмет отмечен как мусор.")
    else
        print("Предмет не является мусором.")
    end
end
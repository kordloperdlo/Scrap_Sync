-- Scrap Sync (PandaWoW 5.4.8)
-- глобальная синхронизация настроек Scrap между персонажами (на всех серверах)

local ADDON_NAME = ...

-- локализация
local L = LibStub("AceLocale-3.0"):GetLocale("Scrap_Sync")

-- библиотеки
local AceAddon   = LibStub("AceAddon-3.0")
local AceConsole = LibStub("AceConsole-3.0")
local AceEvent   = LibStub("AceEvent-3.0")
local AceDB      = LibStub("AceDB-3.0")
local AceConfig  = LibStub("AceConfig-3.0")
local AceDialog  = LibStub("AceConfigDialog-3.0")

local LDB     = LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub("LibDBIcon-1.0", true)

------------------------------------------------------------
-- Addon объект
------------------------------------------------------------
local ScrapSync = AceAddon:NewAddon("Scrap_Sync", "AceConsole-3.0", "AceEvent-3.0")

------------------------------------------------------------
-- Переменные для сохранения
------------------------------------------------------------
Scrap_SyncDB = Scrap_SyncDB or {}
Scrap_SyncDB_Internal = Scrap_SyncDB_Internal or {}

------------------------------------------------------------
-- Значения по умолчанию профиля, включая новые настройки
------------------------------------------------------------
local DEFAULTS = {
    profile = {
        selected = nil,
        minimap = { hide = false },
        -- новые настройки
        checkActivity = false,   -- галочка активности
        activityDays = 0,        -- кол-во дней активности
    },
}

-- глобальные переменные для текущих настроек
local checkActivity = false
local activityDays = 0

------------------------------------------------------------
-- Получение текущих ID персонажа
------------------------------------------------------------
local function CurrentIDs()
    local realm = GetRealmName()
    local char  = UnitName("player")
    local key   = realm.."-"..char
    return realm, char, key
end

local function IsCurrentCharacter(key)
    local _, _, curKey = CurrentIDs()
    return key == curKey
end

------------------------------------------------------------
-- Форматирование времени последнего видения
------------------------------------------------------------
local function FormatLastSeen(ts)
    if not ts then return L["LastSeenNever"] or "никогда" end
    return date("%d.%m.%Y %H:%M:%S", ts)
end

local function GetLastSeenColor(ts)
    if not ts then return "ffff0000" end -- старое
    local diff = time() - ts
    local INACTIVE_DAYS = 14
    local INACTIVE_SECONDS = INACTIVE_DAYS * 24 * 60 * 60
    if diff > INACTIVE_SECONDS * 2 then
        return "ffff0000" -- старое
    elseif diff > INACTIVE_SECONDS then
        return "ffff8000" -- неактивное
    else
        return "ff00ff00" -- активное
    end
end

------------------------------------------------------------
-- Сохранение данных текущего персонажа
------------------------------------------------------------
local function SaveCurrentCharToDB()
    local realm, char, key = CurrentIDs()
    Scrap_SyncDB.Characters = Scrap_SyncDB.Characters or {}
    Scrap_SyncDB.Characters[key] = Scrap_SyncDB.Characters[key] or {}

    local entry = Scrap_SyncDB.Characters[key]
    entry.Class   = select(2, UnitClass("player"))
    entry.Realm   = realm
    entry.Name    = char
    entry.Faction = UnitFactionGroup("player")
    entry.LastSeen = time()

    -- Импорт списка Scrap
    if Scrap and Scrap.Toggle then
        if Scrap_CharSets and Scrap_CharSets.list then
            entry.List = CopyTable(Scrap_CharSets.list)
        elseif Scrap_Junk then
            entry.List = CopyTable(Scrap_Junk)
        else
            entry.List = entry.List or {}
        end
    else
        entry.List = entry.List or {}
    end

    Scrap_SyncDB_Internal[key] = CopyTable(entry)
end

------------------------------------------------------------
-- Построение списка персонажей для выбора
------------------------------------------------------------
local function BuildCharacterList()
    local values, index = {}, {}
    local _, _, curKey = CurrentIDs()

    if Scrap_SyncDB.Characters then
        for key, data in pairs(Scrap_SyncDB.Characters) do
            if type(data) == "table" then
                local isCurrent = (key == curKey)
                local classColor = RAID_CLASS_COLORS[data.Class or "PRIEST"]
                                     and RAID_CLASS_COLORS[data.Class or "PRIEST"].colorStr
                                     or "ffffffff"
                local seenColor = GetLastSeenColor(data.LastSeen)
                local seenText  = FormatLastSeen(data.LastSeen)

                local nameLabel = data.Name or "?"
                if isCurrent then
                    nameLabel = nameLabel .. " (Текущий)"
                end

                values[key] = string.format("|c%s%s|r - %s  |c%s[%s]|r",
                                            classColor, nameLabel, data.Realm or "?", seenColor, seenText)
                index[key] = { realm = data.Realm, char = data.Name }
            end
        end
    end

    return values, index
end

------------------------------------------------------------
-- Построение статистики
------------------------------------------------------------
local function BuildStats(data)
    local counts, total = {}, 0
    if data and data.List then
        for itemID, val in pairs(data.List) do
            if val ~= nil then
                local _, _, quality = GetItemInfo(itemID)
                quality = quality or 0
                counts[quality] = (counts[quality] or 0) + 1
                total = total + 1
            end
        end
    end
    return total, counts
end

local function StatsToText(data)
    if type(data) ~= "table" or not data.List then
        return ""
    end

    local total, counts = BuildStats(data)
    local lines = {}
    table.insert(lines, L["LastSeen"] .. ": " .. FormatLastSeen(data.LastSeen))
    table.insert(lines, L["TotalItems"] .. ": " .. total)
    for q = 0, 6 do
        if counts[q] then
            local name = _G["ITEM_QUALITY"..q.."_DESC"] or "Качество "..q
            table.insert(lines, name .. ": " .. counts[q])
        end
    end
    return table.concat(lines, "\n")
end

------------------------------------------------------------

-- Основные функции
function ScrapSync:ResetCurrent()
    local _, _, key = CurrentIDs()
    if Scrap_SyncDB.Characters and Scrap_SyncDB.Characters[key] then
        Scrap_SyncDB.Characters[key].List = {}
        print(L["ResetDone"])
    end
end

local function DeleteCharacter(key)
    if not key then return end
    if IsCurrentCharacter(key) then
        print(L["CannotDeleteCurrent"])
        return
    end
    Scrap_SyncDB.Characters[key] = nil
    Scrap_SyncDB_Internal[key] = nil
    if ScrapSync.db.profile.selected == key then
        ScrapSync.db.profile.selected = nil
    end
end

function ScrapSync:CopyFromSelected()
    local selected = self.db.profile.selected
    if not selected or selected == "" then
        print(L["NoCharSelected"])
        return
    end

    local _, index = BuildCharacterList()
    local path = index[selected]
    if not path then
        print(L["NoScrapData"])
        return
    end

    local source = Scrap_SyncDB.Characters[selected]
    if not source or not source.List then
        print(L["NoScrapData"])
        return
    end

    local _, _, curKey = CurrentIDs()
    local dest = Scrap_SyncDB.Characters[curKey]
    dest.List = dest.List or {}

    local found, added, skipped = 0,0,0
    local foundJunk, foundKeep, addedJunk, addedKeep, skippedJunk, skippedKeep = 0,0,0,0,0,0

    for id,val in pairs(source.List) do
        if val ~= nil then
            found = found + 1
            if val then foundJunk = foundJunk + 1 else foundKeep = foundKeep + 1 end

            if dest.List[id] == nil then
                dest.List[id] = val
                added = added + 1
                if val then addedJunk = addedJunk + 1 else addedKeep = addedKeep + 1 end
            else
                skipped = skipped + 1
                if val then skippedJunk = skippedJunk + 1 else skippedKeep = skippedKeep + 1 end
            end
        end
    end

    print(L["CopyReportHeader"]:format(path.char, path.realm))
    print(L["CopyReportFound"]..": "..found.." ("..foundJunk.." "..L["Junk"]..", "..foundKeep.." "..L["NotJunk"]..")")
    print(L["CopyReportAdded"]..": "..added.." ("..addedJunk.." "..L["Junk"]..", "..addedKeep.." "..L["NotJunk"]..")")
    print(L["CopyReportSkipped"]..": "..skipped.." ("..skippedJunk.." "..L["Junk"]..", "..skippedKeep.." "..L["NotJunk"]..")")
end

------------------------------------------------------------
-- Настройки интерфейса с локализацией
local options = {
  type = "group",
  args = {
    activitySettings = {
      type = "group",
      name = L["ActivitySettings"],
      inline = true,
      order = 0,
      args = {
        checkActivity = {
          type = "toggle",
          name = L["CheckActivity"],
          desc = L["CheckActivityDesc"],
          get = function() return self.db.profile.checkActivity end,
          set = function(_, v)
            self.db.profile.checkActivity = v
            checkActivity = v
            daysInput:SetEnabled(v)
          end,
        },
        activityDays = {
          type = "input",
          name = L["Days"],
          desc = L["ActivityDaysDesc"],
          pattern = "%d+",
          get = function() return tostring(self.db.profile.activityDays) end,
          set = function(_, v)
            local num = tonumber(v)
            if num and num >= 0 then
              self.db.profile.activityDays = num
              activityDays = num
            else
              self.db.profile.activityDays = activityDays
            end
          end,
          disabled = function() return not self.db.profile.checkActivity end,
        },
      },
    },
    -- остальные пункты
    src = {
      type = "select",
      name = L["Character"],
      desc = L["SelectCharacterDesc"],
      order = 1,
      values = function() return BuildCharacterList() end,
      get = function() return ScrapSync.db.profile.selected end,
      set = function(_, v) ScrapSync.db.profile.selected = v end,
      width = "full",
    },
    stats = {
      type = "description",
      name = function()
        local selected = ScrapSync.db.profile.selected
        if not selected or selected == "" then return "" end
        local _, index = BuildCharacterList()
        local path = index[selected]
        if not path then return "" end
        local data = Scrap_SyncDB["Characters"][selected]
        if type(data) ~= "table" or not data.List then return "" end
        local total, counts = BuildStats(data)
        return StatsToText(data)
      end,
      order = 2,
      width = "full",
    },
    actions = {
      type = "group",
      inline = true,
      name = "",
      order = 3,
      args = {
        copy = {
          type = "execute",
          name = L["CopyScrap"],
          desc = L["CopyScrapDesc"],
          order = 1,
          confirm = function() return L["ConfirmCopy"] end,
          func = function() ScrapSync:CopyFromSelected() end,
          disabled = function()
            local selected = ScrapSync.db.profile.selected
            if not selected or selected == "" then return true end
            return not Scrap_SyncDB["Characters"][selected]
          end,
        },
        reset = {
          type = "execute",
          name = L["Reset"],
          desc = L["ResetDesc"],
          order = 2,
          confirm = function() return L["ResetConfirm"] end,
          func = function() ScrapSync:ResetCurrent() end,
        },
        update = {
          type = "execute",
          name = L["Refresh"],
          desc = L["RefreshDesc"],
          order = 3,
          func = function()
            SaveCurrentCharToDB()
            print(L["ListRefreshed"])
          end,
        },
        delete = {
          type = "execute",
          name = L["Delete"],
          desc = L["DeleteDesc"],
          order = 4,
          confirm = false,
          disabled = function()
            local selected = ScrapSync.db.profile.selected
            if not selected or selected == "" then return true end
            return IsCurrentCharacter(selected)
          end,
          func = function()
            local selected = ScrapSync.db.profile.selected
            if not selected then
              print(L["NoCharSelected"])
              return
            end
            local data = Scrap_SyncDB.Characters[selected]
            if not data then
              print(L["NoScrapData"])
              return
            end
            if IsCurrentCharacter(selected) then
              print(L["CannotDeleteCurrent"])
              return
            end
            StaticPopup_Show("CONFIRM_DELETE_CHARACTER")
          end,
        },
      },
    },
    minimap = {
      type = "toggle",
      name = L["Minimap"],
      desc = L["ShowIcon"],
      order = 4,
      width = "full",
      get = function() return not ScrapSync.db.profile.minimap.hide end,
      set = function(_, v)
        ScrapSync.db.profile.minimap.hide = not v
        if LDBIcon then
          if v then LDBIcon:Show("Scrap_Sync") else LDBIcon:Hide("Scrap_Sync") end
        end
      end,
    },
  },
}

-- Диалог подтверждения удаления
StaticPopupDialogs["CONFIRM_DELETE_CHARACTER"] = {
  text = L["ConfirmDeleteCharacter"],
  button1 = L["Yes"],
  button2 = L["No"],
  OnAccept = function()
    local selected = ScrapSync.db.profile.selected
    if selected and Scrap_SyncDB.Characters then
      local data = Scrap_SyncDB.Characters[selected]
      if data and not IsCurrentCharacter(selected) then
        Scrap_SyncDB.Characters[selected] = nil
        Scrap_SyncDB_Internal[selected] = nil
        if ScrapSync.db.profile.selected == selected then
          ScrapSync.db.profile.selected = nil
        end
        print(L["CharacterDeleted"])
      else
        print(L["CannotDeleteCurrent"])
      end
    end
  end,
  timeout = 0,
  while_dead = true,
  hide_on_escape = true,
}

-- Setup Minimap icon
local function SetupMinimap()
    if not LDB or not LDBIcon then return end
    local obj = LDB:NewDataObject("Scrap_Sync", {
        type = "launcher",
        icon = "Interface\\Icons\\INV_Misc_Gear_01",
        OnClick = function(_, button)
            if button == "LeftButton" then
                InterfaceOptionsFrame_OpenToCategory("Scrap Sync")
                InterfaceOptionsFrame_OpenToCategory("Scrap Sync")
            else
                ScrapSync:ResetCurrent()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("Scrap Sync")
            tt:AddLine(L["LMBTooltip"])
            tt:AddLine(L["RMBTooltip"])
        end,
    })
    LDBIcon:Register("Scrap_Sync", obj, ScrapSync.db.profile.minimap)
end

------------------------------------------------------------

-- Перехват Scrap.Toggle для защиты от nil
local function ApplyScrapFix()
    if Scrap and Scrap.Toggle then
        local originalToggle = Scrap.Toggle
        Scrap.Toggle = function(self, item, ...)
            if not item then return end -- защита от nil
            return originalToggle(self, item, ...)
        end
        print(L["Scrap.ToggleIntercepted"])
    end
end

-- Автоматическая инициализация при загрузке аддона
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

------------------------------------------------------------

-- Инициализация
function ScrapSync:OnInitialize()
    self.db = AceDB:New("Scrap_SyncDB", DEFAULTS, true)

    -- загрузка настроек в переменные
    checkActivity = self.db.profile.checkActivity
    activityDays = self.db.profile.activityDays

    SaveCurrentCharToDB()
    -- регистрируем опции
    AceConfig:RegisterOptionsTable("Scrap_Sync", options)
    AceDialog:AddToBlizOptions("Scrap_Sync", "Scrap Sync")
    SetupMinimap()
    print(L["Ready"])
end

function ScrapSync:OnEnable()
    self:RegisterEvent("PLAYER_LOGOUT", SaveCurrentCharToDB)
end

------------------------------------------------------------

-- Проверка активности
local function isActive(lastSeen)
    if not checkActivity or activityDays <= 0 then
        return true -- активность не проверяется
    end
    local now = time()
    local secondsLimit = activityDays * 24 * 60 * 60
    return (now - lastSeen) <= secondsLimit
end
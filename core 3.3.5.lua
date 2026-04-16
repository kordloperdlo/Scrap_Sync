-- Scrap Sync (Core)
-- Глобальная синхронизация настроек Scrap между персонажами для 3.3.5a

local ScrapSync = LibStub("AceAddon-3.0"):NewAddon("Scrap_Sync", "AceConsole-3.0", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("Scrap_Sync")

-- Глобальные БД (из .toc)
Scrap_SyncDB = Scrap_SyncDB or {}

-- Флаг отладки (глобальный) – по умолчанию выключен
ScrapSync_DebugEnabled = false
ScrapSync_AltClickEnabled = false

-- Функция отладки
function ScrapSync_Debug(msg, itemLink)
    if ScrapSync_DebugEnabled then
        if itemLink then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[Scrap_Sync отладка]|r " .. msg .. " " .. itemLink)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[Scrap_Sync отладка]|r " .. tostring(msg))
        end
    end
end

-- Настройки профиля
local DEFAULTS = {
  profile = {
    selected = nil,
    minimap = { hide = false },
    debug = false,
  }
}

-- Возвращает realm, char, key
local function CurrentIDs()
  local realm = GetRealmName()
  local char  = UnitName("player")
  local key   = realm.."-"..char
  return realm, char, key
end

-- Сохранение данных текущего чара
local function SaveCurrentCharToDB()
  local realm, char, key = CurrentIDs()

  Scrap_SyncDB["Characters"] = Scrap_SyncDB["Characters"] or {}
  Scrap_SyncDB["Characters"][key] = Scrap_SyncDB["Characters"][key] or {}

  local entry = Scrap_SyncDB["Characters"][key]
  entry.Class   = select(2, UnitClass("player"))
  entry.Realm   = realm
  entry.Name    = char
  entry.Faction = UnitFactionGroup("player")

  -- Импорт из Scrap (3.3.5)
  local scrapSource = _G["Scrap_Junk"] or (Scrap_CharSets and Scrap_CharSets.list)
  if scrapSource then
    entry.List = {}
    for id, val in pairs(scrapSource) do
      entry.List[id] = val
    end
  end
end

-- Список персонажей для селекта
local CharacterIndex = {}
local function BuildCharacterList()
  local values = {}
  local _, _, curKey = CurrentIDs()
  local temp = {}
  CharacterIndex = {}

  if Scrap_SyncDB["Characters"] then
    for key, data in pairs(Scrap_SyncDB["Characters"]) do
      if type(data) == "table" and key ~= curKey then
        local class = data.Class or "PRIEST"
        local color = RAID_CLASS_COLORS[class] and RAID_CLASS_COLORS[class].colorStr or "ffffffff"
        local factionIcon = ""
        if data.Faction == "Horde" then
          factionIcon = "|TInterface\\PVPFrame\\PVP-Currency-Horde:16:16:0:0|t "
        elseif data.Faction == "Alliance" then
          factionIcon = "|TInterface\\PVPFrame\\PVP-Currency-Alliance:16:16:0:0|t "
        end

        local label = factionIcon .. ("|c%s%s|r - %s"):format(color, data.Name or "?", data.Realm or "?")
        table.insert(temp, { key = key, label = label, realm = data.Realm, char = data.Name })
      end
    end
  end

  table.sort(temp, function(a,b) return a.label < b.label end)
  for _, entry in ipairs(temp) do
    values[entry.key] = entry.label
    CharacterIndex[entry.key] = { realm = entry.realm, char = entry.char }
  end
  return values
end

-- Расчет статистики
local function BuildStats(data)
  local counts, total = {}, 0
  if data and data.List then
    for id, val in pairs(data.List) do
      if val then
        local _, _, rarity = GetItemInfo(id)
        rarity = rarity or 0
        counts[rarity] = (counts[rarity] or 0) + 1
        total = total + 1
      end
    end
  end
  return total, counts
end

local function StatsToText(total, counts)
  local lines = { "|cffffd100" .. L["TotalItems"] .. ":|r " .. total }
  for rarity = 0, 6 do
    if counts[rarity] then
      local _, _, _, hex = GetItemQualityColor(rarity)
      local name = _G["ITEM_QUALITY"..rarity.."_DESC"] or (L["Rarity"].." "..rarity)
      table.insert(lines, "|c" .. hex .. name .. ":|r " .. counts[rarity])
    end
  end
  return table.concat(lines, "\n")
end

-- Копирование
function ScrapSync:CopyFromSelected()
  local selected = self.db.profile.selected
  if not selected or not CharacterIndex[selected] then 
    print(L["NoCharSelected"])
    return 
  end

  local source = Scrap_SyncDB["Characters"][selected]
  local realm, char, curKey = CurrentIDs()
  local destEntry = Scrap_SyncDB["Characters"][curKey]
  local path = CharacterIndex[selected]

  local scrapActual = _G["Scrap_Junk"] or (Scrap_CharSets and Scrap_CharSets.list)

  local found, added, skipped = 0, 0, 0
  for id, val in pairs(source.List) do
    found = found + 1
    if destEntry.List[id] == nil then
      destEntry.List[id] = val
      if scrapActual then scrapActual[id] = val end
      added = added + 1
    else
      skipped = skipped + 1
    end
  end

  print(L["CopyReportHeader"]:format(path.char, path.realm))
  print(L["CopyReportFound"]..": "..found)
  print(L["CopyReportAdded"]..": "..added)
  print(L["CopyReportSkipped"]..": "..skipped)
end

-- Сброс
function ScrapSync:ResetCurrent()
  local _, _, curKey = CurrentIDs()
  if Scrap_SyncDB["Characters"][curKey] then Scrap_SyncDB["Characters"][curKey].List = {} end
  local scrapActual = _G["Scrap_Junk"] or (Scrap_CharSets and Scrap_CharSets.list)
  if scrapActual then for k in pairs(scrapActual) do scrapActual[k] = nil end end
  self:Print(L["ResetDone"])
end

-- Иконка миникарты
function ScrapSync:SetupLDB()
  local LDB = LibStub("LibDataBroker-1.1", true)
  local LDBIcon = LibStub("LibDBIcon-1.0", true)
  if not LDB then return end

  local dataobj = LDB:NewDataObject("Scrap_Sync", {
    type = "launcher",
    text = "Scrap Sync",
    icon = "Interface\\Icons\\INV_Misc_Gear_01",
    OnClick = function(_, button)
      if button == "LeftButton" then
        InterfaceOptionsFrame_OpenToCategory("Scrap Sync")
        InterfaceOptionsFrame_OpenToCategory("Scrap Sync")
      elseif button == "RightButton" then
        self:ResetCurrent()
      end
    end,
    OnTooltipShow = function(tt)
      tt:AddLine("Scrap Sync")
      tt:AddLine(L["LMBTooltip"])
      tt:AddLine(L["RMBTooltip"])
    end,
  })
  if LDBIcon then LDBIcon:Register("Scrap_Sync", dataobj, self.db.profile.minimap) end
end

-- Опции интерфейса
local options = {
  type = "group",
  name = "Scrap Sync",
  args = {
    src = {
      type = "select", name = L["Character"], desc = L["SelectCharacterDesc"], order = 1, width = "double",
      values = BuildCharacterList,
      get = function() return ScrapSync.db.profile.selected end,
      set = function(_, v) ScrapSync.db.profile.selected = v end,
    },
    stats = {
      type = "description", order = 2, width = "full",
      name = function()
        local sel = ScrapSync.db.profile.selected
        if not sel or not Scrap_SyncDB["Characters"][sel] then return "" end
        return "\n" .. StatsToText(BuildStats(Scrap_SyncDB["Characters"][sel]))
      end,
    },
    actions = {
      type = "group", inline = true, name = "", order = 3,
      args = {
        copy = { type = "execute", name = L["CopyScrap"], desc = L["CopyScrapDesc"], order = 1, confirm = function() return L["ConfirmCopy"] end, func = function() ScrapSync:CopyFromSelected() end },
        reset = { type = "execute", name = L["Reset"], desc = L["ResetDesc"], order = 2, confirm = function() return L["ResetConfirm"] end, func = function() ScrapSync:ResetCurrent() end },
        update = { type = "execute", name = L["Refresh"], desc = L["RefreshDesc"], order = 3, func = function() SaveCurrentCharToDB(); print(L["ListRefreshed"]) end },
      },
    },
    showicon = {
      type = "toggle",
      name = L["Minimap"],
      desc = L["ShowIcon"],
      order = 4,
      get = function() return not ScrapSync.db.profile.minimap.hide end,
      set = function(_, v)
        ScrapSync.db.profile.minimap.hide = not v
        local i = LibStub("LibDBIcon-1.0", true)
        if i then if v then i:Show("Scrap_Sync") else i:Hide("Scrap_Sync") end end
      end,
    },
    debugtoggle = {
      type = "toggle",
      name = L["DebugMode"],
      desc = L["DebugModeDesc"],
      order = 5,
      get = function() return ScrapSync_DebugEnabled end,
      set = function(_, v)
        ScrapSync_DebugEnabled = v
        ScrapSync.db.profile.debug = v
        if v then
          print("|cff00ff00Scrap Sync:|r " .. L["DebugEnabled"])
        else
          print("|cff00ff00Scrap Sync:|r " .. L["DebugDisabled"])
          ScrapSync_AltClickEnabled = false
        end
      end,
    },
    altclick = {
      type = "toggle",
      name = L["AltClickTest"],
      desc = L["AltClickTestDesc"],
      order = 6,
      hidden = function() return not ScrapSync_DebugEnabled end,
      get = function() return ScrapSync_AltClickEnabled end,
      set = function(_, v)
        ScrapSync_AltClickEnabled = v
        if v then
          print("|cff00ff00Scrap Sync:|r " .. L["AltClickEnabled"])
        else
          print("|cff00ff00Scrap Sync:|r " .. L["AltClickDisabled"])
        end
      end,
    },
  },
}

-- Инициализация
function ScrapSync:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("Scrap_SyncDB", DEFAULTS, true)
  ScrapSync_DebugEnabled = self.db.profile.debug
  SaveCurrentCharToDB()
  LibStub("AceConfig-3.0"):RegisterOptionsTable("Scrap_Sync", options)
  LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Scrap_Sync", "Scrap Sync")
  self:SetupLDB()
  print("|cff00ff00Scrap Sync:|r " .. (L["Ready"] or "Ready"))
end

function ScrapSync:OnEnable()
  self:RegisterEvent("PLAYER_LOGOUT", SaveCurrentCharToDB)
end
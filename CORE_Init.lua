----------------------------------------------------
-- WeakAuras Radar CORE module
--
-- All variables in this file, either local or part of the core module starting with an underscore (_)
-- are supposed to be private variables,
-- editing these variables without internal knownledge might cause the radar to malfunction!
--
-- Just like variables, all functions starting with an underscore (_) are ment as private functions
-- They're used by the internal API and display only,
-- Do not change or invoke these functions without having internal knownledge!
----------------------------------------------------

local core = WA_RADAR_CORE or CreateFrame("Frame", "WA_RADAR_CORE", UIParent)
core:Hide()

----------------------------------------------------
-- CONFIGURATION, Edit values with care
----------------------------------------------------
core.config = {
      -- The maximum range you will see on the radar, anything further then this won't be visible.
      -- This can be seen as "zoom", measured in in-game yards.
      -- Edit this value to see either more or less on the radar.
      -- MUST BE GREATER THEN 0, ELSE BAD THINGS WILL HAPPEN!
      maxRange = 60,
}

----------------------------------------------------
-- CONSTANTS
----------------------------------------------------
core.constants = {
      lines = {
            extend = {
                  SEGMENT = 0,
                  HALF = 1,
                  EXTEND = 2
            },
            danger = {
                  DANGER = 0,
                  NEUTRAL = 1,
                  FRIENDLY = 2
            }
      },
      disks = {
            danger = {
                  DANGER = 0,
                  NEUTRAL = 1,
                  FRIENDLY = 2
            }
      }
}

----------------------------------------------------
-- GetUnitPosition function fix
-- Fixing the blizzard API function to return with X, Y, instanceID
----------------------------------------------------
local function GetUnitPosition(unitID)
      local posY, posX, _, instanceID = UnitPosition(unitID)

      return posX, posY, instanceID
end

----------------------------------------------------
-- INITIAL SETUP
----------------------------------------------------
core._defaultWidth = 480
core._range = core._defaultWidth / 2
core._range2 = core._range * core._range
core._scale = core._range / core.config.maxRange

core._tCoeff = 256/254
core._lineCoeff = core._tCoeff/2

core._facing = 0
core._sin = math.sin(core._facing)
core._cos = math.cos(core._facing)

core._playerName = GetUnitName("player", true)

core._positions = {}
core._positions.player = GetUnitPosition("player")

core._radarPositions = {}
core._radarPositions.player = { 0, 0, true }

core._displayedUnits = {}
core._roster = {}
core._staticPoints = {}
core._lines = {}
core._disks = {}
core._enabled = false
core._frame = CreateFrame("Frame", nil, UIParent)

----------------------------------------------------
-- SCALING
----------------------------------------------------
function core:_updateScale(width)
      core._range = width / 2
      core._range2 = core._range * core._range
      core._scale = core._range / core.config.maxRange
end

----------------------------------------------------
-- BLIPS, aka the dots on the radar!
----------------------------------------------------
local BLIP_TEX_COORDS = {
      ["WARRIOR"] = { 0, 0.125, 0, 0.25 },
      ["PALADIN"] = { 0.125, 0.25, 0, 0.25 },
      ["HUNTER"] = { 0.25, 0.375, 0, 0.25 },
      ["ROGUE"] = { 0.375, 0.5, 0, 0.25 },
      ["PRIEST"] = { 0.5, 0.625, 0, 0.25 },
      ["DEATHKNIGHT"] = { 0.625, 0.75, 0, 0.25 },
      ["SHAMAN"] = { 0.75, 0.875, 0, 0.25 },
      ["MAGE"] = { 0.875, 1, 0, 0.25 },
      ["WARLOCK"] = { 0, 0.125, 0.25, 0.5 },
      ["DRUID"] = { 0.25, 0.375, 0.25, 0.5 },
      ["MONK"] = { 0.125, 0.25, 0.25, 0.5 }
}

core._newBlip = {
      __index = function(t, k)
            if k == "player" then return end

            local blip = CreateFrame("Frame", nil, core._frame)
            t[k] = blip
            blip:SetPoint("CENTER")
            blip:SetFrameStrata("HIGH")
            blip:SetFrameLevel(1)
            blip:SetSize(22,22)
            blip.t = blip:CreateTexture(nil, "BORDER", nil, 4)
            blip.t:SetAllPoints()
            blip.t:SetTexture([[Interface\MINIMAP\PartyRaidBlips]])
            blip.t:SetTexCoord(.5, .625, .5, .75)

            return blip
      end
}
core._blips = setmetatable({}, core._newBlip)

function core:_initBlip(unit)
      if UnitIsUnit(unit, "player") then
            return
      end

      local blip = core._blips[unit]
      local _, class = UnitClass(unit)

      if BLIP_TEX_COORDS[class] then
            blip.t:SetTexCoord(unpack(BLIP_TEX_COORDS[class]))
      else
            blip.t:SetTexCoord(.5, .625, .5, .75)
      end
end

function core:_updateBlip(unit)
      local blip = core._blips[unit]
      local p = core._positions[unit]

      local x, y, inRange = core:GetRadarPosition(p[1], p[2], p[3])

      core._radarPositions[unit] = core._radarPositions[unit] or {}
      core._radarPositions[unit][1] = x
      core._radarPositions[unit][2] = y
      core._radarPositions[unit][3] = inRange

      if inRange then
            core._displayedUnits[unit] = true
            blip:SetPoint("CENTER", x, y)
            blip:Show()
      else
            core._displayedUnits[unit] = false
            blip:Hide()
      end
end

----------------------------------------------------
-- POSITIONING AND ROSTER
----------------------------------------------------

--[[
  Calculates the relative position on the radar based on true in-game coordinates.
]]
function core:GetRadarPosition(x, y, instanceID)
      local posX, posY, instanceID = x, y, instanceID

      local playerX = core._positions.player[1]
      local playerY = core._positions.player[2]
      local playerInstanceID = core._positions.player[3]

      if playerInstanceID == instanceID then
            local offx, offy = (playerX - posX) * core._scale, (posY - playerY) * core._scale
            local x = core._cos * offx + core._sin * offy
            local y = -core._sin * offx + core._cos * offy
            local inRange = offx*offx + offy*offy <= core._range2

            return x, y, inRange
      end
end

function core:_updatePositions()
      core._positions.player = core._positions.player or {}
      core._positions.player[1], core._positions.player[2], core._positions.player[3] = GetUnitPosition("player")

      for unit in pairs(core._displayedUnits) do
            core._positions[unit] = core._positions[unit] or {}

            local x, y, instanceID = GetUnitPosition(unit)

            -- TODO: Clean this up and do more checks before assuming it's a static point.
            if not x then
                  x, y, instanceID = core._staticPoints[unit][1], core._staticPoints[unit][2], core._positions.player[3]
            end

            core._positions[unit][1] = x
            core._positions[unit][2] = y
            core._positions[unit][3] = instanceID
      end
end

function core:_updateRoster()
    wipe(core._roster)
    wipe(core._positions)
    wipe(core._displayedUnits)

    -- Load player into the roster
    local playerGUID = UnitGUID("player")
    core._roster[playerGUID] = "player"

    -- Load raid into the roster
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = WeakAuras.raidUnits[i]

            if UnitIsUnit(unit, "player") then
                unit = "player"
            elseif ( UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) ) then
                core._displayedUnits[unit] = false
                core:_initBlip(unit)
            end

            local unitGUID = UnitGUID(unit)
            core._roster[unitGUID] = unit
        end
    end

    -- Load static points into the roster
    for name, coords in pairs(core._staticPoints) do
        core._displayedUnits[name] = false
        core:_initBlip(name)
        core._roster[name] = name
    end

    -- Hide all blips if they shouldn't be displayed
    for unit, blip in pairs(core._blips) do
        if core._displayedUnits[unit] == nil then
            blip:Hide()
        end
    end
end

----------------------------------------------------
-- LINES
----------------------------------------------------
local linePrototypeDummyFrame = CreateFrame("Frame")
local lineMT = { __index = linePrototypeDummyFrame }

local linePrototype = {
      Draw = function(this, source, destination, width, extend, danger)
            this:_initialize(source, destination, width, extend, danger)
            this:Show()
      end,

      Destroy = function(this)
            this:Hide()
      end,

      Color = function(this, r, g, b, a)
            this.texture:SetVertexColor(r, g, b, a)
      end,

      BelongsTo = function(this, sourceX, sourceY, targetX, targetY)
            local pX, pY = core._positions.player[1], core._positions.player[2]

            local VECTOR_LENGTH = 300
            local VECTOR_DEPTH = (4/core._scale) * 0.125 * this.width + 1

            local dX = (sourceX - targetX)
            local dY = (sourceY - targetY)
            local dist = math.sqrt(dX * dX + dY * dY)

            local t_cos = (targetX-sourceX) / dist
            local newX = VECTOR_LENGTH * t_cos  +  targetX

            local t_sin = (targetY-sourceY) / dist
            local newY = VECTOR_LENGTH * t_sin  +  targetY

            local radiusX,radiusY = VECTOR_DEPTH * t_sin, VECTOR_DEPTH * t_cos

            local point1x = sourceX + radiusX
            local point1y = sourceY - radiusY

            local point2x = sourceX - radiusX
            local point2y = sourceY + radiusY

            local point3x = newX + radiusX
            local point3y = newY - radiusY

            local point4x = newX - radiusX
            local point4y = newY + radiusY

            return this._belongsTo(pX,pY,point1x,point2x,point4x,point3x,point1y,point2y,point4y,point3y)
      end,

      _belongsTo = function(pX,pY,point1x,point2x,point3x,point4x,point1y,point2y,point3y,point4y)
		local D1 = (pX - point1x) * (point2y - point1y) - (pY - point1y) * (point2x - point1x)
		local D2 = (pX - point2x) * (point3y - point2y) - (pY - point2y) * (point3x - point2x)
		local D3 = (pX - point3x) * (point4y - point3y) - (pY - point3y) * (point4x - point3x)
		local D4 = (pX - point4x) * (point1y - point4y) - (pY - point4y) * (point1x - point4x)

		return (D1 < 0 and D2 < 0 and D3 < 0 and D4 < 0) or (D1 > 0 and D2 > 0 and D3 > 0 and D4 > 0)
      end,

      _getDangerColor = function(this, danger)
            danger = danger or core.constants.lines.danger.danger
            if danger == core.constants.lines.danger.DANGER then
                  return 1, 0, 0, 1
            elseif danger == core.constants.lines.danger.NEUTRAL then
                  return 0, 0, 1, 1
            else
                  return 0, 1, 0, 1
            end
      end,

      _updateColor = function(this)
            local src = this.source
            local dest = this.destination

            local srcUnit = core._roster[src]
            local destUnit = core._roster[dest]

            if srcUnit == "player" or destUnit == "player" then
                  return
            end

            if (not core._positions[srcUnit]) or (not core._positions[destUnit]) then
                  return
            end

            local srcX, srcY = core._positions[srcUnit][1], core._positions[srcUnit][2]
            local destX, destY = core._positions[destUnit][1], core._positions[destUnit][2]

            if (not srcX) or (not destX) then
                  return
            end

            local belongsToOne = this:BelongsTo(srcX, srcY, destX, destY)
            local belongsToTwo = this:BelongsTo(destX, destY, srcX, srcY)

            local danger = this.danger
            local danger2 = core.constants.lines.danger.FRIENDLY

            if this.danger == core.constants.lines.danger.FRIENDLY then
                  danger2 = core.constants.lines.danger.DANGER
            end

            local r1, g1, b1, a1 = this:_getDangerColor(danger)
            local r2, g2, b2, a2 = this:_getDangerColor(danger2)

            if this.extend == core.constants.lines.extend.SEGMENT then
                  if belongsToOne and belongsToTwo then
                        this:Color(r1,g1,b1,a1)
                  else
                        this:Color(r2,g2,b2,a2)
                  end
            elseif this.extend == core.constants.lines.extend.HALF then
                  if belongsToOne then
                        this:Color(r1,g1,b1,a1)
                  else
                        this:Color(r2,g2,b2,a2)
                  end
            else
                  if belongsToOne or belongsToTwo then
                        this:Color(r1,g1,b1,a1)
                  else
                        this:Color(r2,g2,b2,a2)
                  end
            end
      end,

      _initialize = function(this, source, destination, width, extend, danger)
            extend = extend or core.constants.lines.extend.SEGMENT
            danger = danger or core.constants.lines.danger.DANGER

            this.source = source
            this.destination = destination
            this.width = width
            this.extend = extend
            this.danger = danger

            this:SetScript("OnUpdate", this._draw)
      end,

      _destroy = function(this)
            this:SetScript("OnUpdate", nil)
            this:ClearAllPoints()
            this:SetParent(core._frame)
            this:SetPoint("CENTER")
            this:Hide()

            core._lines = core._lines or {}
            core._lines[this.key] = nil
      end,

      _draw = function(this)
            local src = this.source
            local dest = this.destination

            if not src then return end
            if not dest then return end

            local srcUnit = core._roster[src]
            local destUnit = core._roster[dest]

            if not srcUnit then return end
            if not destUnit then return end

            -- TODO: Handle errors better
            local sx, sy = core._radarPositions[srcUnit][1], core._radarPositions[srcUnit][2]
            local ex, ey = core._radarPositions[destUnit][1], core._radarPositions[destUnit][2]

            if not sx then return end
            if not ex then return end

            local inRange1, inRange2 = sx * sx + sy * sy <= core._range2, ex * ex + ey * ey <= core._range2
            local w = this.width
            local extend = this.extend

            if (not inRange1) or (not inRange2) or (extend ~= 0) then
                  local x3, y3, x4, y4 = core:_intersection(sx, sy, ex, ey, core._range2)

                  if x3 then
                        local dx, dy = ex - sx, ey - sy
                        local p3Same = dx * (x3 - sx) + dy * (y3 - sy) > 0

                        if extend == core.constants.lines.extend.SEGMENT then -- line segment
                              if inRange1 then
                                    if p3Same then
                                          ex, ey = x3, y3
                                    else
                                          ex, ey = x4, y4
                                    end
                              elseif inRange2 then
                                    if -dx*(x3-ex)-dy*(y3-ey) > 0 then
                                          sx, sy = x3, y3
                                    else
                                          sx, sy = x4, y4
                                    end
                              else
                                    ex, ey = sx, sy
                              end
                        elseif extend == core.constants.lines.extend.HALF then -- half-line
                              if inRange1 then
                                    if p3Same then
                                          ex, ey = x3, y3
                                    else
                                          ex, ey = x4, y4
                                    end
                              else
                                    if p3Same then
                                          sx, sy, ex, ey = x3, y3, x4, y4
                                    else
                                          ex, ey = sx, sy
                                    end
                              end
                        else -- line
                              sx, sy, ex, ey = x3, y3, x4, y4
                        end
                  else
                        ex, ey = sx, sy
                  end
            end

            local dx, dy, cx, cy = ex - sx, ey - sy, (sx + ex) / 2, (sy + ey) / 2

            core._dx = dx
            core._dy = dy

            core._cx = cx
            core._cy = cy

            if dx < 0 then
                  dx, dy = -dx, -dy
            end

            local l = math.sqrt((dx * dx) + (dy * dy))
            if l == 0 then
                  this.texture:SetTexCoord(0,0,0,0,0,0,0,0)
                  this:ClearAllPoints()
                  this:SetPoint("BOTTOMLEFT", core._frame, "CENTER", cx, cy)
                  this:SetPoint("TOPRIGHT", core._frame, "CENTER", cx, cy)
            else
                  local s, c = -dy / l, dx / l
                  local sc = s * c

                  local Bwid, Bhgt, BLx, BLy, TLx, TLy, TRx, TRy, BRx, BRy;

                  if (dy >= 0) then
                        Bwid = ((l * c) - (w * s)) * core._lineCoeff
                        Bhgt = ((w * c) - (l * s)) * core._lineCoeff
                        BLx, BLy, BRy = (w / l) * sc, s * s, (l / w) * sc;
                        BRx, TLx, TLy, TRx = 1 - BLy, BLy, 1 - BRy, 1 - BLx;
                        TRy = BRx;
                  else
                        Bwid = ((l * c) + (w * s)) * core._lineCoeff
                        Bhgt = ((w * c) + (l * s)) * core._lineCoeff
                        BLx, BLy, BRx = s * s, -(l / w) * sc, 1 + (w / l) * sc;
                        BRy, TLx, TLy, TRy = BLx, 1 - BRx, 1 - BLx, 1 - BLy;
                        TRx = TLy;
                  end

                  this.texture:SetTexCoord(TLx, TLy, BLx, BLy, TRx, TRy, BRx, BRy)
                  this:ClearAllPoints()

                  this:SetPoint("BOTTOMLEFT", core._frame, "CENTER", cx - Bwid, cy - Bhgt)
                  this:SetPoint("TOPRIGHT", core._frame, "CENTER", cx + Bwid, cy + Bhgt)
            end

            this:_updateColor()
      end,
}

setmetatable(linePrototype, lineMT)
local linePrototypeMT = { __index = linePrototype }
function core:_createLine(key)
      core._lines = core._lines or {}
      local line

      if core._lines[key] then
            line = core._lines[key]
      else
            line = CreateFrame("Frame", nil, core._frame)
            setmetatable(line, linePrototypeMT)

            line.key = key
            line:SetFrameStrata("BACKGROUND")
            line.texture = line:CreateTexture(nil, "BACKGROUND", nil, 1)
            line.texture:SetAllPoints()
            line.texture:SetTexture("Interface\\AddOns\\WeakAuras\\Media\\Textures\\Square_White")
            line:SetSize(20, 20)

            core._lines[key] = line
      end

      line.texture:SetVertexColor(0,1,0,1)
      line.texture:SetBlendMode("BLEND")
      line:Hide()

      return line
end

function core:_genKey(source, destination)
      return source .. "||".. destination
end

function core:_intersection(x1, y1, x2, y2, r2)
      local dx, dy = x2 - x1, y2 - y1
      local dr2 = dx * dx + dy * dy
      local D = x1 * y2 - x2 * y1
      local Det = r2 * dr2 - D * D

      if Det > 0 then
            local det = dy < 0 and -math.sqrt(Det) or math.sqrt(Det)
            return (D * dy + dx * det)/dr2, (-D * dx + dy * det)/dr2, (D * dy - dx * det)/dr2, (-D * dx - dy * det)/dr2
      end
end

----------------------------------------------------
-- DISKS
----------------------------------------------------
function core:_diskUpdater(disk)
      if not disk then return end
      if not disk.shown then
            disk:Hide()
            return
      end

      local src = disk.source
      local srcUnit = core._roster[src]

      if not srcUnit then return end

      -- TODO: Handle errors better
      local sx, sy, inRange = core._radarPositions[srcUnit][1], core._radarPositions[srcUnit][2], core._radarPositions[srcUnit][3]
      disk:SetPoint("CENTER", core._frame, "CENTER", sx, sy)

      if inRange then
            disk:Show()
      else
            disk:Hide()
      end
end

local diskDummyFrame = CreateFrame("Frame")
local diskMT = { __index = diskDummyFrame }

local diskPrototype = {

      Draw = function(this, radius, source, danger)
            danger = danger or core.constants.disks.danger.DANGER

            this:_initialize(radius, source, danger)
            this.shown = true
            this:Show()
      end,

      Color = function(this, r, g, b, a)
            this.texture:SetVertexColor(r, g, b, a)
      end,

      Destroy = function(this)
            this.shown = false
            this:Hide()
      end,

      _initialize = function(this, radius, source, danger)
            this.radius = radius
            this.danger = danger
            this.source = source
            this:SetScript("OnUpdate", this._draw)
      end,

      _getDangerColor = function(this, danger)
            danger = danger or core.constants.lines.danger.danger
            if danger == core.constants.lines.danger.DANGER then
                  return 1, 0, 0, 0.3
            elseif danger == core.constants.lines.danger.NEUTRAL then
                  return 0, 0, 1, 0.3
            else
                  return 0, 1, 0, 0.3
            end
      end,

      _draw = function(this)
            local radiusScaled = core._scale * this.radius
            local R2 = radiusScaled * core._tCoeff * 2

            this.radiusScaled = radiusScaled
            this:SetSize(R2, R2)

            this:_updateColor()
      end,

      _updateColor = function(this)
            local danger = this.danger
            local danger2 = core.constants.disks.danger.FRIENDLY

            if this.danger == core.constants.disks.danger.FRIENDLY then
                  danger2 = core.constants.disks.danger.DANGER
            end

            local r1, g1, b1, a1 = this:_getDangerColor(danger)
            local r2, g2, b2, a2 = this:_getDangerColor(danger2)

            local pX, pY = core._positions.player[1], core._positions.player[2]

            local src = this.source
            local srcUnit = core._roster[src]

            if not srcUnit then return end

            -- TODO: Handle errors better
            local srcX, srcY = core._positions[srcUnit][1], core._positions[srcUnit][2]

            local distance = ((pY-srcY)^2+(pX-srcX)^2)^(1/2)

            if distance < this.radius then
                  this:Color(r1,g1,b1,a1)
            else
                  this:Color(r2,g2,b2,a2)
            end
      end,
}

setmetatable(diskPrototype, diskMT)
local diskPrototypeMT = { __index = diskPrototype }

function core:NewDisk(key, radius, source)
    core._disks = core._disks or {}

    local disk

    if core._disks[key] then
        disk = core._disks[key]
    else
        disk = CreateFrame("Frame", nil, core._frame)
        disk.key = key
        setmetatable(disk, diskPrototypeMT)

        disk:SetPoint("CENTER")
        disk:SetFrameStrata("BACKGROUND")

        disk.texture = disk:CreateTexture(nil, "BACKGROUND", nil, 1)
        disk.texture:SetAllPoints()
        disk.texture:SetTexture("Interface\\AddOns\\WeakAuras\\Media\\Textures\\Circle_White")
        disk.texture:SetVertexColor(1, 0, 0, 0.3)

        core._disks[key] = disk
    end

    disk:Hide()
    return disk
end

----------------------------------------------------
-- DISPLAY UPDATER
----------------------------------------------------
function core:_updater()
      core._facing = GetPlayerFacing()
      core._sin = math.sin(core._facing)
      core._cos = math.cos(core._facing)

      core:_updateRoster()
      core:_updatePositions()

      for unit in pairs(core._displayedUnits) do
            core:_updateBlip(unit)
      end

      for key, disk in pairs(core._disks) do
          core:_diskUpdater(disk)
      end
end

----------------------------------------------------
-- PUBLIC API
----------------------------------------------------
function core:Enable()
      if core._enabled then return end

      -- before we enable, run the updater once,
      -- make sure everything has an initial value
      core:_updater()

      core._enabled = true
end

function core:Disable()
      if core._enabled then
            core:DisconnectAll()
            core:DestroyAllDisks()
            core._enabled = false
      end
end

function core:IsEnabled()
      return core._enabled
end

function core:AddStatic(name, x, y)
      core._staticPoints = core._staticPoints or {}
      core._staticPoints[name] = core._staticPoints[name] or {}
      core._staticPoints[name][1] = x
      core._staticPoints[name][2] = y
end

function core:Connect(source, destination, width, extend, danger)
      local key = core:_genKey(source, destination)
      local line = core:_createLine(key)

      line:Draw(source, destination, width, extend, danger)
      return line
end

function core:Disconnect(source, destination)
      local key = core:_genKey(source, destination)
      local line = core:_createLine(key)

      if not line then return end

      line:Hide()
      return line
end

function core:DisconnectAll()
      for key, line in pairs(core._lines) do
            core:Disconnect(line.source, line.destination)
      end
end

function core:Disk(source, radius, danger)
    local key = source
    local disk = core:NewDisk(key)

    disk:Draw(radius, source, danger)
    return disk
end

function core:DestroyAllDisks()
    for key, disk in pairs(core._disks) do
        disk:Destroy()
    end
end

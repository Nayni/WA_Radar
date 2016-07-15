local WA_DISPLAY = function()

      local core = WA_RADAR_CORE
      if not core then return end

      local frame = WeakAuras["regions"][aura_env.id]["region"]
      core._frame = frame

      local width = max(frame:GetWidth(), frame:GetHeight())
      frame:SetWidth(width)
      frame:SetHeight(width)

      core._range = width / 2
      core._range2 = core._range * core._range
      core._scale = core._range / core.config.maxRange

      frame.background = frame.background or frame:CreateTexture(nil, "BACKGROUND")
      frame.background:SetTexture("Interface\\AddOns\\WeakAuras\\Media\\Textures\\Circle_White_Border")
      frame.background:SetAllPoints(frame)
      frame.background:SetVertexColor(.3, .3, .3, 0.7)

      frame.arrow = frame.arrow or CreateFrame("Frame", nil, frame)
      frame.arrow:SetFrameStrata("HIGH")
      frame.arrow:SetPoint("CENTER")
      frame.arrow:SetSize(24, 24)
      frame.arrow.t = frame.arrow.t or frame.arrow:CreateTexture(nil, "BORDER")
      frame.arrow.t:SetAllPoints()
      frame.arrow.t:SetTexture([[Interface\MINIMAP\MiniMap-DeadArrow]])

      core._updater()
end

-- lua/ge/extensions/CareerMoney.lua
-- Simple wallet-only access helper for Career mode money

local M = {}

local function getMoneySafe()
  if not career_modules_playerAttributes or not career_modules_playerAttributes.getAttributeValue then
    return nil
  end

  local ok, value = pcall(career_modules_playerAttributes.getAttributeValue, "money")
  if not ok then
    return nil
  end

  return value
end

local function setMoneySafe(amount)
  if not career_modules_playerAttributes or not career_modules_playerAttributes.setAttributes then
    return false
  end

  local ok = pcall(career_modules_playerAttributes.setAttributes, { money = amount })
  return ok
end

local function addMoneySafe(delta)
  if not career_modules_playerAttributes or not career_modules_playerAttributes.addAttributes then
    return false
  end

  local ok = pcall(career_modules_playerAttributes.addAttributes, { money = delta })
  return ok
end

function M.get()
  local value = getMoneySafe()
  return tonumber(value) or 0
end

function M.set(amount)
  amount = tonumber(amount) or 0
  if setMoneySafe(amount) then
    return true
  end

  local current = getMoneySafe()
  if current == nil then
    return false
  end

  local delta = amount - current
  if delta == 0 then
    return true
  end

  return addMoneySafe(delta)
end

function M.add(delta)
  delta = tonumber(delta) or 0
  if addMoneySafe(delta) then
    return true
  end

  local current = getMoneySafe()
  if current == nil then
    return false
  end

  return setMoneySafe(current + delta)
end

function M.isCareerActive()
  local ok, active = pcall(function()
    if careerActive == true then
      return true
    end

    if career_career and career_career.isActive then
      return career_career.isActive()
    end

    if career_modules_playerAttributes then
      return true
    end

    if career_career then
      return true
    end

    return false
  end)

  return ok and active or false
end

function M.fmt(amount)
  return string.format("%.2f", tonumber(amount) or 0)
end

function M.draw(imgui)
  if not imgui then return end

  if M.isCareerActive() then
    local money = M.get()
    imgui.Text(string.format("Wallet: $%s", M.fmt(money)))
  else
    imgui.Text("Career not active")
  end
end

return M

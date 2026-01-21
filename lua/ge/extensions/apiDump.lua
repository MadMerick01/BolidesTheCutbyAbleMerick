-- lua/ge/extensions/apiDump.lua
-- BeamNG API dump helper

local M = {}

local DEFAULT_MAX_DEPTH = 5
local DEFAULT_ROOTS = {
  _G = _G,
  extensions = extensions,
  be = be,
  scenetree = scenetree,
  core_vehicle_manager = core_vehicle_manager,
}

local function safeType(value)
  local ok, t = pcall(type, value)
  if ok then return t end
  return "unknown"
end

local function addFunctionEntry(target, key)
  target[#target + 1] = tostring(key)
end

local function addFieldEntry(target, key, value)
  target[tostring(key)] = safeType(value)
end

local function scanValue(value, depth, visited)
  local valueType = safeType(value)
  if valueType ~= "table" then
    return { type = valueType }
  end

  if visited[value] then
    return { type = "table", visited = true }
  end

  visited[value] = true

  local node = {
    type = "table",
    functions = {},
    fields = {},
    children = {},
  }

  if depth <= 0 then
    node.truncated = true
    return node
  end

  for k, v in pairs(value) do
    local entryType = safeType(v)
    if entryType == "function" then
      addFunctionEntry(node.functions, k)
    else
      addFieldEntry(node.fields, k, v)
      if entryType == "table" then
        node.children[tostring(k)] = scanValue(v, depth - 1, visited)
      end
    end
  end

  return node
end

local function dumpRoots(roots, maxDepth)
  local visited = {}
  local result = {
    maxDepth = maxDepth,
    roots = {},
  }

  for name, value in pairs(roots) do
    result.roots[name] = scanValue(value, maxDepth, visited)
  end

  return result
end

local function appendLine(lines, indent, text)
  lines[#lines + 1] = string.rep("  ", indent) .. text
end

local function renderTextNode(lines, name, node, indent)
  appendLine(lines, indent, string.format("%s: %s", name, node.type or "unknown"))

  if node.visited then
    appendLine(lines, indent + 1, "(visited)")
    return
  end

  if node.truncated then
    appendLine(lines, indent + 1, "(truncated)")
    return
  end

  if node.functions and #node.functions > 0 then
    appendLine(lines, indent + 1, "functions:")
    for _, fnName in ipairs(node.functions) do
      appendLine(lines, indent + 2, fnName)
    end
  end

  if node.fields then
    local hasFields = false
    for _ in pairs(node.fields) do
      hasFields = true
      break
    end
    if hasFields then
      appendLine(lines, indent + 1, "fields:")
      for key, valueType in pairs(node.fields) do
        appendLine(lines, indent + 2, string.format("%s: %s", key, valueType))
      end
    end
  end

  if node.children then
    local hasChildren = false
    for _ in pairs(node.children) do
      hasChildren = true
      break
    end
    if hasChildren then
      appendLine(lines, indent + 1, "children:")
      for childKey, childNode in pairs(node.children) do
        renderTextNode(lines, childKey, childNode, indent + 2)
      end
    end
  end
end

local function renderText(data)
  local lines = {}
  appendLine(lines, 0, "BeamNG API Dump")
  appendLine(lines, 0, string.format("Max depth: %s", tostring(data.maxDepth)))
  appendLine(lines, 0, "")

  for name, node in pairs(data.roots or {}) do
    renderTextNode(lines, name, node, 0)
    appendLine(lines, 0, "")
  end

  return table.concat(lines, "\n")
end

function M.dump(opts)
  opts = opts or {}

  local roots = opts.roots or DEFAULT_ROOTS
  local maxDepth = tonumber(opts.maxDepth or opts.depth or DEFAULT_MAX_DEPTH) or DEFAULT_MAX_DEPTH

  local data = dumpRoots(roots, maxDepth)

  local outputDir = opts.outputDir
  if outputDir == "" then
    outputDir = nil
  end
  local baseDir = outputDir or "user:/"
  local sep = baseDir:match("[/\\]$") and "" or "/"
  local jsonPath = string.format("%s%sapi_dump_0.38.json", baseDir, sep)
  local textPath = string.format("%s%sapi_dump_0.38.txt", baseDir, sep)

  local function fileExists(path)
    if FS and FS.fileExists then
      return FS:fileExists(path)
    end
    if _G.fileExists then
      return _G.fileExists(path)
    end
    return nil
  end

  local function safeJsonWrite(path, payload)
    if not jsonWriteFile then
      return false, "jsonWriteFile missing"
    end
    local ok, err = pcall(jsonWriteFile, path, payload, true)
    if not ok then
      return false, tostring(err)
    end
    local exists = fileExists(path)
    if exists == false then
      return false, "file not created"
    end
    return true
  end

  local function safeTextWrite(path, payload)
    if writeFile then
      local ok, err = pcall(writeFile, path, payload)
      if not ok then
        return false, tostring(err)
      end
    else
      local ok, err = pcall(jsonWriteFile, path, { text = payload }, true)
      if not ok then
        return false, tostring(err)
      end
    end
    local exists = fileExists(path)
    if exists == false then
      return false, "file not created"
    end
    return true
  end

  local okJson, jsonErr = safeJsonWrite(jsonPath, data)
  if not okJson then
    local msg = string.format("Failed to write API dump JSON (%s): %s", jsonPath, jsonErr or "unknown error")
    log("E", "apiDump", msg)
    return false, msg, jsonPath, textPath
  end

  local text = renderText(data)
  local okText, textErr = safeTextWrite(textPath, text)
  if not okText then
    local msg = string.format("Failed to write API dump text (%s): %s", textPath, textErr or "unknown error")
    log("E", "apiDump", msg)
    return false, msg, jsonPath, textPath
  end

  log("I", "apiDump", string.format("Wrote API dump to %s and %s", jsonPath, textPath))
  return true, nil, jsonPath, textPath
end

return M

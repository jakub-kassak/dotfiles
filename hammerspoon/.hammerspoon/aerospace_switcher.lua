-- AeroSpace Fullscreen Mouse Gesture Switcher for Hammerspoon
-- Trigger: Double Middle Click (within 380ms)
-- Features:
--   * Fullscreen glass overlay on the active monitor
--   * 3 Visual Layouts: Grid, Radial (angle-based pie), and List
--   * Individual App / Window Focus & Zoom:
--       - Hover or angle-select any workspace OR individual app/window to zoom & preview its title
--       - Click an individual app icon / window chip to switch to that workspace AND focus that exact window
--       - In Radial mode, each window in a workspace gets its own sub-angle slice so moving the mouse slightly
--         within a workspace's sector highlights & zooms each individual app/window (and clicking focuses it!)
--   * Drag & Drop Windows:
--       - Left-click & drag any app/window -> Move window to target workspace (stays open & updates live)
--       - Right-click & drag any app/window -> Move window to target workspace & switch view immediately
--   * Empty workspaces sorted inline in their natural order as compact number badges.

local M = {}

local AEROSPACE = "/opt/homebrew/bin/aerospace"
local SETTINGS_KEY_LAYOUT = "aerospace_switcher.layout"
local SETTINGS_KEY_SHOW_EMPTY = "aerospace_switcher.show_empty"
local SETTINGS_KEY_CUSTOM_LABELS = "aerospace_switcher.custom_labels"

-- Configurable workspace ordering & display metadata
local ALL_WORKSPACES_ORDER = {
  "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12",
  "c", "g", "i", "m", "o", "."
}

local WORKSPACE_META = {
  ["1"]  = { key = "1",  hint = "1", label = "Desktop 1" },
  ["2"]  = { key = "2",  hint = "2", label = "Desktop 2" },
  ["3"]  = { key = "3",  hint = "3", label = "PDF / Docs" },
  ["4"]  = { key = "4",  hint = "4", label = "Code" },
  ["5"]  = { key = "5",  hint = "5", label = "Anki / Study" },
  ["6"]  = { key = "6",  hint = "6", label = "Desktop 6" },
  ["7"]  = { key = "7",  hint = "7", label = "Finance" },
  ["8"]  = { key = "8",  hint = "8", label = "Desktop 8" },
  ["9"]  = { key = "9",  hint = "9", label = "Desktop 9" },
  ["10"] = { key = "0",  hint = "0", label = "Files / Web" },
  ["11"] = { key = "-",  hint = "-", label = "Desktop 11" },
  ["12"] = { key = "=",  hint = "=", label = "Desktop 12" },
  ["c"]  = { key = "c",  hint = "C", label = "Calendar" },
  ["g"]  = { key = "g",  hint = "G", label = "AI (Gemini/GPT)" },
  ["i"]  = { key = "i",  hint = "I", label = "Linguee / Dict" },
  ["m"]  = { key = "m",  hint = "M", label = "Messages & Mail" },
  ["o"]  = { key = "o",  hint = "O", label = "Obsidian" },
  ["."]  = { key = "n",  hint = ". (N)", label = "Notes / Scratch" },
}

-- State
M.webview = nil
M.userContent = nil
M.isOpen = false
M.iconCache = {}
M.cachedState = nil
M.refreshTask = nil

local lastMiddleClickTime = 0
local lastMiddleClickPos = { x = 0, y = 0 }
local DOUBLE_CLICK_THRESHOLD = 0.38 -- seconds
local DOUBLE_CLICK_MAX_DIST = 35    -- pixels

local function getSavedLayout()
  return hs.settings.get(SETTINGS_KEY_LAYOUT) or "radial"
end

local function setSavedLayout(layout)
  hs.settings.set(SETTINGS_KEY_LAYOUT, layout)
end

local function getSavedShowEmpty()
  local val = hs.settings.get(SETTINGS_KEY_SHOW_EMPTY)
  if val == nil then return false end
  return val
end

local function setSavedShowEmpty(val)
  hs.settings.set(SETTINGS_KEY_SHOW_EMPTY, not not val)
end

local function getCustomLabels()
  return hs.settings.get(SETTINGS_KEY_CUSTOM_LABELS) or {}
end

local function setCustomLabel(wsName, newLabel)
  if not wsName or wsName == "" then return end
  local labels = getCustomLabels()
  local trimmed = (newLabel or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if trimmed == "" then
    labels[tostring(wsName)] = nil
  else
    labels[tostring(wsName)] = trimmed
  end
  hs.settings.set(SETTINGS_KEY_CUSTOM_LABELS, labels)
  if M.cachedState and M.cachedState.workspaces then
    for _, ws in ipairs(M.cachedState.workspaces) do
      if ws.name == wsName then
        local defaultMeta = WORKSPACE_META[wsName] or { label = "Workspace " .. wsName }
        ws.label = labels[tostring(wsName)] or defaultMeta.label
      end
    end
  end
end

-- Get base64 PNG data URL for an app bundle ID
local function getAppIconDataUrl(bundleId)
  if not bundleId or bundleId == "" then return "" end
  if M.iconCache[bundleId] then
    return M.iconCache[bundleId]
  end

  local img = hs.image.imageFromAppBundle(bundleId)
  if not img then
    local apps = hs.application.applicationsForBundleID(bundleId)
    if apps and apps[1] and apps[1]:path() then
      img = hs.image.iconForFile(apps[1]:path())
    end
  end

  if img then
    local sized = img:size({ w = 64, h = 64 })
    local url = (sized or img):encodeAsURLString()
    if url then
      M.iconCache[bundleId] = url
      return url
    end
  end

  M.iconCache[bundleId] = ""
  return ""
end

-- Parse output of our combined shell script into structured state
local function parseAerospaceOutput(output)
  local focusedWorkspace = "1"
  local focusedWindow = nil
  local windowsByWs = {}
  local seenWorkspaces = {}

  for line in (output or ""):gmatch("[^\r\n]+") do
    local prefix, rest = line:match("^([A-Z_]+)\t(.*)$")
    if prefix == "FOCUSED_WS" then
      local ws = rest:gsub("^%s+", ""):gsub("%s+$", "")
      if ws ~= "" then focusedWorkspace = ws end
    elseif prefix == "FOCUSED_WIN" then
      local wid, ws, bid, appName, title = rest:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
      if wid and wid ~= "" then
        focusedWindow = {
          id = wid,
          workspace = ws,
          bundleId = bid,
          appName = appName,
          title = title,
          icon = getAppIconDataUrl(bid),
        }
      end
    elseif prefix == "WIN" then
      local wid, ws, bid, appName, title = rest:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
      if wid and ws and ws ~= "" then
        if not windowsByWs[ws] then windowsByWs[ws] = {} end
        seenWorkspaces[ws] = true
        table.insert(windowsByWs[ws], {
          id = wid,
          workspace = ws,
          bundleId = bid,
          appName = appName,
          title = title,
          icon = getAppIconDataUrl(bid),
        })
      end
    end
  end

  seenWorkspaces[focusedWorkspace] = true
  for _, ws in ipairs(ALL_WORKSPACES_ORDER) do
    seenWorkspaces[ws] = true
  end

  -- Build ordered list
  local orderedNames = {}
  local added = {}
  for _, ws in ipairs(ALL_WORKSPACES_ORDER) do
    table.insert(orderedNames, ws)
    added[ws] = true
  end
  for ws, _ in pairs(seenWorkspaces) do
    if not added[ws] then
      table.insert(orderedNames, ws)
      added[ws] = true
    end
  end

  local focusedWinId = focusedWindow and focusedWindow.id or ""
  local customLabels = getCustomLabels()

  local workspaces = {}
  for _, ws in ipairs(orderedNames) do
    local wins = windowsByWs[ws] or {}
    for _, w in ipairs(wins) do
      w.isFocusedWindow = (w.id == focusedWinId)
    end

    local meta = WORKSPACE_META[ws] or { key = ws:lower(), hint = ws:upper(), label = "Workspace " .. ws }
    local customLabel = customLabels[tostring(ws)]
    table.insert(workspaces, {
      name = ws,
      key = meta.key,
      hint = meta.hint,
      label = (customLabel and customLabel ~= "") and customLabel or meta.label,
      defaultLabel = meta.label,
      isFocused = (ws == focusedWorkspace),
      windowCount = #wins,
      windows = wins,
    })
  end

  return {
    focusedWorkspace = focusedWorkspace,
    focusedWindow = focusedWindow,
    workspaces = workspaces,
    layout = getSavedLayout(),
    showEmpty = getSavedShowEmpty(),
  }
end

local FETCH_CMD = string.format([[
(%s list-workspaces --focused | awk '{print "FOCUSED_WS\t"$0}') &
(%s list-windows --focused --format 'FOCUSED_WIN	%%{window-id}	%%{workspace}	%%{app-bundle-id}	%%{app-name}	%%{window-title}' 2>/dev/null) &
(%s list-windows --all --format 'WIN	%%{window-id}	%%{workspace}	%%{app-bundle-id}	%%{app-name}	%%{window-title}' 2>/dev/null) &
wait
]], AEROSPACE, AEROSPACE, AEROSPACE)

local function pushStateToWebview(state)
  if not M.webview then return end
  local json = hs.json.encode(state)
  M.webview:evaluateJavaScript(string.format("window.updateSwitcherState && window.updateSwitcherState(%s);", json))
end

-- Refresh cached state asynchronously
function M.refreshStateAsync(callback)
  if M.refreshTask and M.refreshTask:isRunning() then
    return
  end
  M.refreshTask = hs.task.new("/bin/sh", function(exitCode, stdOut, stdErr)
    M.refreshTask = nil
    if exitCode == 0 and stdOut then
      M.cachedState = parseAerospaceOutput(stdOut)
      if callback then callback(M.cachedState) end
    end
  end, { "-c", FETCH_CMD })
  M.refreshTask:start()
end

-- Execute an AeroSpace workspace or window action
-- mode:
--   "switch"       -> switch to workspace (and if targetFocusWinId is provided, focus that exact window!)
--   "focus_window" -> focus that exact window directly (`aerospace focus --window-id <id>`)
--   "move"         -> move windowId to workspace (stay on current workspace; if keepOpen, refresh UI live)
--   "follow"       -> move windowId to workspace, switch to workspace, and focus that window
function M.performAction(workspace, mode, windowId, keepOpen, focusWindowId)
  if (not workspace or workspace == "") and (not focusWindowId or focusWindowId == "") then return end

  local targetMoveWinId = windowId
  if not targetMoveWinId or targetMoveWinId == "" then
    if M.cachedState and M.cachedState.focusedWindow then
      targetMoveWinId = M.cachedState.focusedWindow.id
    end
  end

  if mode == "move" then
    if not keepOpen then
      M.close()
    end
    local cmd
    if targetMoveWinId and targetMoveWinId ~= "" then
      cmd = string.format("%s move-node-to-workspace --window-id %s %q", AEROSPACE, tostring(targetMoveWinId), tostring(workspace))
    else
      cmd = string.format("%s move-node-to-workspace %q", AEROSPACE, tostring(workspace))
    end
    hs.task.new("/bin/sh", function()
      M.refreshStateAsync(function(freshState)
        if M.isOpen then
          pushStateToWebview(freshState)
        end
      end)
    end, { "-c", cmd }):start()
    if not keepOpen then
      hs.alert.show(string.format("Moved window → Workspace %s", workspace), 0.8)
    end
  elseif mode == "follow" then
    M.close()
    local cmd
    if targetMoveWinId and targetMoveWinId ~= "" then
      cmd = string.format("%s move-node-to-workspace --window-id %s %q && %s workspace %q && %s focus --window-id %s",
        AEROSPACE, tostring(targetMoveWinId), tostring(workspace),
        AEROSPACE, tostring(workspace),
        AEROSPACE, tostring(targetMoveWinId))
    else
      cmd = string.format("%s move-node-to-workspace %q && %s workspace %q",
        AEROSPACE, tostring(workspace), AEROSPACE, tostring(workspace))
    end
    hs.task.new("/bin/sh", function()
      M.refreshStateAsync()
    end, { "-c", cmd }):start()
  elseif mode == "focus_window" and focusWindowId and focusWindowId ~= "" then
    M.close()
    local cmd
    if workspace and workspace ~= "" then
      cmd = string.format("%s workspace %q && %s focus --window-id %s",
        AEROSPACE, tostring(workspace), AEROSPACE, tostring(focusWindowId))
    else
      cmd = string.format("%s focus --window-id %s", AEROSPACE, tostring(focusWindowId))
    end
    hs.task.new("/bin/sh", function()
      M.refreshStateAsync()
    end, { "-c", cmd }):start()
  else
    -- Default: switch workspace (and optionally focus a specific window on it)
    M.close()
    local cmd
    if focusWindowId and focusWindowId ~= "" then
      cmd = string.format("%s workspace %q && %s focus --window-id %s",
        AEROSPACE, tostring(workspace), AEROSPACE, tostring(focusWindowId))
    else
      cmd = string.format("%s workspace %q", AEROSPACE, tostring(workspace))
    end
    hs.task.new("/bin/sh", function()
      M.refreshStateAsync()
    end, { "-c", cmd }):start()
  end
end

-- HTML/CSS/JS Fullscreen UI
local HTML_TEMPLATE = [=[
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  :root {
    --bg-overlay: rgba(12, 13, 18, 0.78);
    --bg-card: rgba(30, 32, 42, 0.78);
    --bg-card-hover: rgba(48, 52, 68, 0.92);
    --bg-card-active: rgba(59, 130, 246, 0.24);
    --border-subtle: rgba(255, 255, 255, 0.11);
    --border-hover: rgba(255, 255, 255, 0.35);
    --accent-switch: #4f8cff;
    --accent-app: #a855f7;
    --accent-move: #f59e0b;
    --accent-follow: #10b981;
    --text-main: #f8fafc;
    --text-muted: #94a3b8;
    --text-dim: #64748b;
  }

  * {
    box-sizing: border-box;
    user-select: none;
    -webkit-user-select: none;
    -webkit-user-drag: none;
  }

  html, body {
    margin: 0;
    padding: 0;
    width: 100%;
    height: 100%;
    background: transparent;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", sans-serif;
    color: var(--text-main);
    overflow: hidden;
  }

  .fullscreen-backdrop {
    width: 100vw;
    height: 100vh;
    background: var(--bg-overlay);
    backdrop-filter: blur(26px) saturate(170%);
    -webkit-backdrop-filter: blur(26px) saturate(170%);
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    position: relative;
    overflow: hidden;
  }

  /* Top Floating HUD Bar */
  .top-hud {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 14px 28px;
    background: rgba(15, 16, 22, 0.72);
    border-bottom: 1px solid rgba(255, 255, 255, 0.09);
    gap: 16px;
    z-index: 30;
    flex-shrink: 0;
  }

  .hud-left, .hud-center, .hud-right {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .mode-group {
    display: flex;
    align-items: center;
    gap: 4px;
    background: rgba(0, 0, 0, 0.42);
    padding: 4px;
    border-radius: 11px;
    border: 1px solid rgba(255, 255, 255, 0.08);
  }

  .pill-btn {
    border: none;
    background: transparent;
    color: var(--text-muted);
    font-size: 12.5px;
    font-weight: 500;
    padding: 6px 13px;
    border-radius: 8px;
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 6px;
    transition: all 0.12s ease;
    white-space: nowrap;
  }

  .pill-btn:hover {
    color: var(--text-main);
    background: rgba(255, 255, 255, 0.08);
  }

  .pill-btn.active-switch {
    background: var(--accent-switch);
    color: #fff;
    font-weight: 600;
    box-shadow: 0 2px 10px rgba(79, 140, 255, 0.4);
  }

  .pill-btn.active-move {
    background: var(--accent-move);
    color: #111;
    font-weight: 600;
    box-shadow: 0 2px 10px rgba(245, 158, 11, 0.4);
  }

  .pill-btn.active-follow {
    background: var(--accent-follow);
    color: #052e16;
    font-weight: 600;
    box-shadow: 0 2px 10px rgba(16, 185, 129, 0.4);
  }

  .pill-btn.active-layout {
    background: rgba(255, 255, 255, 0.18);
    color: #fff;
    font-weight: 600;
  }

  /* Draggable Active Window Chip in HUD */
  .draggable-active-win {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 5px 12px 5px 8px;
    border-radius: 9px;
    background: rgba(255, 255, 255, 0.08);
    border: 1px solid rgba(255, 255, 255, 0.14);
    cursor: grab;
    max-width: 420px;
    transition: all 0.14s ease;
  }

  .draggable-active-win:hover {
    background: rgba(255, 255, 255, 0.15);
    border-color: rgba(255, 255, 255, 0.32);
    transform: scale(1.03);
  }

  .window-bar-icon {
    width: 18px;
    height: 18px;
    border-radius: 4px;
    flex-shrink: 0;
  }

  .window-bar-title {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    color: #f1f5f9;
    font-size: 12.5px;
    font-weight: 500;
  }

  /* Live Target Preview Banner */
  .preview-pill {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 5px 14px;
    border-radius: 99px;
    background: rgba(79, 140, 255, 0.16);
    border: 1px solid rgba(79, 140, 255, 0.35);
    color: #dbeafe;
    font-size: 12.5px;
    font-weight: 600;
    max-width: 480px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  /* Main Stage Area */
  .content {
    flex: 1;
    width: 100%;
    height: 100%;
    overflow-y: auto;
    overflow-x: hidden;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 28px 44px;
    position: relative;
  }

  /* Drop target highlights during Drag & Drop */
  .drop-target-move {
    border-color: var(--accent-move) !important;
    background: rgba(245, 158, 11, 0.26) !important;
    box-shadow: 0 0 0 3px rgba(245, 158, 11, 0.65), 0 14px 34px rgba(0, 0, 0, 0.55) !important;
    transform: scale(1.08) !important;
  }

  .drop-target-follow {
    border-color: var(--accent-follow) !important;
    background: rgba(16, 185, 129, 0.26) !important;
    box-shadow: 0 0 0 3px rgba(16, 185, 129, 0.7), 0 14px 34px rgba(0, 0, 0, 0.55) !important;
    transform: scale(1.08) !important;
  }

  .radial-node.drop-target-move,
  .radial-node.drop-target-follow,
  .radial-empty-node.drop-target-move,
  .radial-empty-node.drop-target-follow {
    transform: translate(-50%, -50%) scale(1.26) !important;
    z-index: 25 !important;
  }

  /* ================= APP / WINDOW ICON ITEM (WITH INDIVIDUAL FOCUS & ZOOM) ================= */
  .app-icon-wrap {
    position: relative;
    width: 42px;
    height: 42px;
    border-radius: 10px;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid rgba(255, 255, 255, 0.07);
    transition: transform 0.14s cubic-bezier(0.2, 0.9, 0.3, 1.25), background 0.12s ease, border-color 0.12s ease, box-shadow 0.12s ease;
  }

  .app-icon-wrap:hover,
  .app-icon-wrap.app-selected {
    transform: scale(1.34) translateY(-3px);
    background: rgba(168, 85, 247, 0.28);
    border-color: #c084fc;
    box-shadow: 0 8px 20px rgba(0, 0, 0, 0.55), 0 0 0 2px rgba(192, 132, 252, 0.55);
    z-index: 20;
  }

  .app-icon-wrap.is-focused-win {
    border-color: rgba(79, 140, 255, 0.75);
    background: rgba(79, 140, 255, 0.18);
  }

  .app-icon {
    width: 34px;
    height: 34px;
    border-radius: 8px;
    object-fit: contain;
    filter: drop-shadow(0 2px 5px rgba(0,0,0,0.4));
    pointer-events: none;
  }

  .app-fallback {
    width: 34px;
    height: 34px;
    border-radius: 8px;
    background: rgba(255, 255, 255, 0.16);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 13px;
    font-weight: 700;
    color: #fff;
    pointer-events: none;
  }

  /* Floating label tooltip when an individual app/window is zoomed */
  .app-zoom-label {
    position: absolute;
    bottom: -24px;
    left: 50%;
    transform: translateX(-50%);
    background: rgba(15, 16, 23, 0.96);
    border: 1px solid rgba(192, 132, 252, 0.6);
    color: #f8fafc;
    font-size: 10px;
    font-weight: 600;
    padding: 2px 7px;
    border-radius: 5px;
    white-space: nowrap;
    max-width: 190px;
    overflow: hidden;
    text-overflow: ellipsis;
    pointer-events: none;
    opacity: 0;
    transition: opacity 0.12s ease;
    box-shadow: 0 4px 12px rgba(0,0,0,0.5);
    z-index: 30;
  }

  .app-icon-wrap:hover .app-zoom-label,
  .app-icon-wrap.app-selected .app-zoom-label {
    opacity: 1;
  }

  /* ================= LAYOUT 1: GRID (IN-PLACE SORTED) ================= */
  .grid-container {
    width: 100%;
    max-width: 1520px;
    display: flex;
    flex-wrap: wrap;
    align-items: stretch;
    justify-content: center;
    gap: 14px;
  }

  .ws-card {
    flex: 1 1 215px;
    max-width: 290px;
    min-height: 132px;
    background: var(--bg-card);
    border: 1.5px solid var(--border-subtle);
    border-radius: 16px;
    padding: 14px 16px;
    cursor: pointer;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    transition: transform 0.14s cubic-bezier(0.2, 0.9, 0.3, 1.2), background 0.12s ease, border-color 0.12s ease, box-shadow 0.12s ease;
    position: relative;
  }

  .ws-card:hover {
    background: var(--bg-card-hover);
    border-color: var(--border-hover);
    transform: translateY(-4px) scale(1.06);
    box-shadow: 0 16px 36px rgba(0, 0, 0, 0.48);
    z-index: 10;
  }

  .ws-card.focused {
    background: var(--bg-card-active);
    border-color: rgba(79, 140, 255, 0.75);
    box-shadow: 0 0 0 1px rgba(79, 140, 255, 0.4);
  }

  /* Compact inline empty workspace tile sorted right alongside used cards */
  .ws-card-empty-compact {
    flex: 0 0 54px;
    width: 54px;
    min-height: 132px;
    border-radius: 14px;
    background: rgba(255, 255, 255, 0.03);
    border: 1.5px dashed rgba(255, 255, 255, 0.13);
    color: var(--text-dim);
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 5px;
    cursor: pointer;
    transition: all 0.14s cubic-bezier(0.2, 0.9, 0.3, 1.2);
    position: relative;
  }

  .ws-card-empty-compact:hover {
    background: rgba(79, 140, 255, 0.20);
    border-style: solid;
    border-color: rgba(79, 140, 255, 0.75);
    color: #fff;
    transform: translateY(-4px) scale(1.14);
    box-shadow: 0 12px 26px rgba(0, 0, 0, 0.45);
    z-index: 10;
  }

  .ws-card-empty-num {
    font-size: 15px;
    font-weight: 700;
    color: var(--text-muted);
  }

  .ws-card-empty-compact:hover .ws-card-empty-num {
    color: #fff;
  }

  .ws-card-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    margin-bottom: 10px;
  }

  .ws-badge-wrap {
    display: flex;
    align-items: center;
    gap: 9px;
    min-width: 0;
  }

  .ws-badge {
    min-width: 32px;
    height: 32px;
    padding: 0 8px;
    border-radius: 9px;
    background: rgba(255, 255, 255, 0.14);
    color: #fff;
    font-size: 15px;
    font-weight: 800;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  .ws-card.focused .ws-badge,
  .list-row.focused .ws-badge {
    background: var(--accent-switch);
    color: #fff;
  }

  .ws-label {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-muted);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .rename-btn {
    border: none;
    background: rgba(255, 255, 255, 0.07);
    color: var(--text-muted);
    font-size: 11px;
    padding: 2px 6px;
    border-radius: 5px;
    cursor: pointer;
    opacity: 0;
    transition: opacity 0.12s ease, background 0.12s ease, color 0.12s ease;
    flex-shrink: 0;
  }

  .ws-card:hover .rename-btn,
  .radial-node:hover .rename-btn,
  .radial-node.sector-selected .rename-btn,
  .list-row:hover .rename-btn {
    opacity: 1;
  }

  .rename-btn:hover {
    background: var(--accent-switch);
    color: #fff;
  }

  /* Rename Modal Overlay */
  .rename-modal-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.65);
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
    z-index: 9500;
    display: none;
    align-items: center;
    justify-content: center;
  }

  .rename-modal {
    width: 380px;
    background: rgba(24, 26, 36, 0.98);
    border: 1.5px solid rgba(79, 140, 255, 0.6);
    border-radius: 16px;
    padding: 20px 22px;
    box-shadow: 0 24px 60px rgba(0, 0, 0, 0.75);
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .rename-modal-title {
    font-size: 15px;
    font-weight: 700;
    color: #fff;
  }

  .rename-input {
    width: 100%;
    padding: 9px 12px;
    border-radius: 9px;
    border: 1px solid rgba(255, 255, 255, 0.22);
    background: rgba(0, 0, 0, 0.45);
    color: #fff;
    font-size: 14px;
    outline: none;
    user-select: text;
    -webkit-user-select: text;
  }

  .rename-input:focus {
    border-color: var(--accent-switch);
    box-shadow: 0 0 0 2px rgba(79, 140, 255, 0.35);
  }

  .rename-modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }

  .key-hint {
    font-size: 11px;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    color: var(--text-dim);
    background: rgba(0, 0, 0, 0.4);
    border: 1px solid rgba(255, 255, 255, 0.10);
    padding: 2px 6px;
    border-radius: 5px;
    flex-shrink: 0;
  }

  .ws-icons {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 8px;
    min-height: 44px;
  }

  /* ================= LAYOUT 2: RADIAL / PIE (FULLSCREEN, ANGLE + SUB-ANGLE APP SELECTION) ================= */
  .radial-stage {
    position: relative;
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: visible;
  }

  .radial-svg {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
    z-index: 12;
  }

  .radial-center {
    position: absolute;
    width: 170px;
    height: 170px;
    border-radius: 50%;
    background: rgba(24, 26, 36, 0.85);
    border: 2px dashed rgba(255, 255, 255, 0.24);
    box-shadow: 0 12px 40px rgba(0, 0, 0, 0.55);
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    text-align: center;
    padding: 14px;
    z-index: 15;
    cursor: pointer;
    transform: translate(-50%, -50%);
    transition: background 0.15s ease, border-color 0.15s ease, transform 0.15s ease;
  }

  .radial-center:hover {
    background: rgba(40, 44, 60, 0.92);
    border-color: rgba(255, 255, 255, 0.45);
  }

  .radial-center-icon {
    width: 34px;
    height: 34px;
    border-radius: 8px;
    margin-bottom: 5px;
    display: none;
    filter: drop-shadow(0 4px 8px rgba(0,0,0,0.45));
  }

  .radial-center-ws {
    font-size: 24px;
    font-weight: 800;
    color: #fff;
    line-height: 1.1;
  }

  .radial-center-sub {
    font-size: 11.5px;
    color: var(--text-muted);
    margin-top: 4px;
    line-height: 1.3;
    max-width: 145px;
    overflow: hidden;
    text-overflow: ellipsis;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
  }

  .radial-node {
    position: absolute;
    min-width: 135px;
    max-width: 230px;
    padding: 10px 12px;
    border-radius: 16px;
    background: var(--bg-card);
    border: 1.5px solid var(--border-subtle);
    cursor: pointer;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 7px;
    transform: translate(-50%, -50%) scale(1);
    transition: transform 0.15s cubic-bezier(0.2, 0.9, 0.3, 1.25), background 0.12s ease, border-color 0.12s ease, box-shadow 0.12s ease;
    z-index: 6;
  }

  .radial-node:hover,
  .radial-node.sector-selected {
    background: var(--bg-card-hover);
    border-color: rgba(79, 140, 255, 0.9);
    transform: translate(-50%, -50%) scale(1.20);
    box-shadow: 0 18px 42px rgba(0, 0, 0, 0.65), 0 0 0 2px rgba(79, 140, 255, 0.5);
    z-index: 20;
  }

  .radial-node.focused {
    background: var(--bg-card-active);
    border-color: rgba(79, 140, 255, 0.7);
  }

  /* Compact empty radial node */
  .radial-empty-node {
    position: absolute;
    min-width: 36px;
    height: 36px;
    padding: 0 10px;
    border-radius: 99px;
    background: rgba(30, 32, 42, 0.75);
    border: 1.5px solid rgba(255, 255, 255, 0.15);
    color: var(--text-muted);
    font-size: 13px;
    font-weight: 700;
    display: flex;
    align-items: center;
    justify-content: center;
    transform: translate(-50%, -50%) scale(1);
    cursor: pointer;
    transition: transform 0.15s cubic-bezier(0.2, 0.9, 0.3, 1.25), background 0.12s ease, border-color 0.12s ease, box-shadow 0.12s ease, color 0.12s ease;
    z-index: 5;
  }

  .radial-empty-node:hover,
  .radial-empty-node.sector-selected {
    background: rgba(79, 140, 255, 0.32);
    border-color: rgba(79, 140, 255, 0.95);
    color: #fff;
    transform: translate(-50%, -50%) scale(1.42) !important;
    box-shadow: 0 12px 28px rgba(0, 0, 0, 0.55), 0 0 0 2px rgba(79, 140, 255, 0.5);
    z-index: 20;
  }

  .radial-node-top {
    display: flex;
    align-items: center;
    gap: 7px;
  }

  .radial-node-badge {
    min-width: 26px;
    height: 26px;
    padding: 0 7px;
    border-radius: 7px;
    background: rgba(255, 255, 255, 0.15);
    font-size: 13.5px;
    font-weight: 800;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .radial-node.focused .radial-node-badge {
    background: var(--accent-switch);
  }

  .radial-node-label {
    font-size: 11.5px;
    font-weight: 600;
    color: #cbd5e1;
    max-width: 110px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .radial-icons {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 7px;
    flex-wrap: wrap;
    min-height: 38px;
  }

  .radial-icons .app-icon-wrap {
    width: 38px;
    height: 38px;
  }

  .radial-icons .app-icon,
  .radial-icons .app-fallback {
    width: 30px;
    height: 30px;
    border-radius: 7px;
    font-size: 11px;
  }

  /* ================= LAYOUT 3: LIST (IN-PLACE SORTED) ================= */
  .list-container {
    width: 100%;
    max-width: 1180px;
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 9px;
  }

  .list-row {
    width: 100%;
    position: relative;
    background: var(--bg-card);
    border: 1.5px solid var(--border-subtle);
    border-radius: 13px;
    padding: 10px 16px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 14px;
    cursor: pointer;
    transition: transform 0.12s ease, background 0.12s ease, border-color 0.12s ease, box-shadow 0.12s ease;
  }

  .list-row:hover {
    background: var(--bg-card-hover);
    border-color: var(--border-hover);
    transform: scale(1.02);
    box-shadow: 0 10px 26px rgba(0, 0, 0, 0.4);
    z-index: 5;
  }

  .list-row.focused {
    background: var(--bg-card-active);
    border-color: rgba(79, 140, 255, 0.7);
  }

  .list-empty-inline {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 5px;
    height: 32px;
    padding: 0 12px;
    border-radius: 8px;
    background: rgba(255, 255, 255, 0.035);
    border: 1.5px dashed rgba(255, 255, 255, 0.13);
    color: var(--text-dim);
    font-size: 12.5px;
    font-weight: 700;
    cursor: pointer;
    transition: all 0.12s ease;
  }

  .list-empty-inline:hover {
    background: rgba(79, 140, 255, 0.22);
    border-style: solid;
    border-color: rgba(79, 140, 255, 0.8);
    color: #fff;
    transform: scale(1.12);
  }

  .list-left {
    display: flex;
    align-items: center;
    gap: 12px;
    min-width: 150px;
    flex-shrink: 0;
  }

  .list-windows {
    flex: 1;
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 9px;
    min-width: 0;
  }

  .list-win-chip {
    display: flex;
    align-items: center;
    gap: 8px;
    background: rgba(0, 0, 0, 0.32);
    border: 1px solid rgba(255, 255, 255, 0.10);
    padding: 5px 11px 5px 7px;
    border-radius: 9px;
    max-width: 290px;
    cursor: pointer;
    transition: transform 0.14s cubic-bezier(0.2, 0.9, 0.3, 1.25), background 0.12s ease, border-color 0.12s ease, box-shadow 0.12s ease;
  }

  .list-win-chip:hover {
    background: rgba(168, 85, 247, 0.26);
    border-color: #c084fc;
    transform: scale(1.10) translateY(-2px);
    box-shadow: 0 8px 20px rgba(0, 0, 0, 0.45);
    z-index: 10;
  }

  .list-win-chip.is-focused-win {
    border-color: rgba(79, 140, 255, 0.75);
    background: rgba(79, 140, 255, 0.18);
  }

  .list-win-chip img {
    width: 22px;
    height: 22px;
    border-radius: 5px;
    flex-shrink: 0;
    pointer-events: none;
  }

  .list-win-text {
    font-size: 12.5px;
    color: #f1f5f9;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    pointer-events: none;
  }

  /* Floating Drag Ghost */
  .drag-ghost {
    position: fixed;
    top: 0;
    left: 0;
    pointer-events: none;
    z-index: 9999;
    display: none;
    align-items: center;
    gap: 9px;
    padding: 7px 13px 7px 9px;
    border-radius: 12px;
    background: rgba(18, 19, 26, 0.96);
    border: 2px solid var(--accent-move);
    box-shadow: 0 16px 36px rgba(0, 0, 0, 0.65);
    transform: translate(-50%, -50%);
    white-space: nowrap;
  }

  .drag-ghost.ghost-follow {
    border-color: var(--accent-follow);
  }

  .drag-ghost img {
    width: 26px;
    height: 26px;
    border-radius: 6px;
  }

  .drag-ghost-text {
    font-size: 12.5px;
    font-weight: 600;
    color: #fff;
    max-width: 220px;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .drag-ghost-badge {
    font-size: 10.5px;
    font-weight: 700;
    padding: 2px 7px;
    border-radius: 6px;
    background: var(--accent-move);
    color: #111;
  }

  .drag-ghost.ghost-follow .drag-ghost-badge {
    background: var(--accent-follow);
    color: #052e16;
  }

  /* Footer */
  .footer {
    padding: 10px 28px;
    border-top: 1px solid rgba(255, 255, 255, 0.08);
    background: rgba(12, 13, 18, 0.72);
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: 12px;
    color: var(--text-muted);
    z-index: 30;
    flex-shrink: 0;
  }

  .kbd {
    display: inline-block;
    padding: 2px 6px;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 11px;
    color: #e2e8f0;
    background: rgba(255, 255, 255, 0.10);
    border: 1px solid rgba(255, 255, 255, 0.14);
    border-radius: 5px;
    margin: 0 2px;
  }
</style>
</head>
<body>
<div class="fullscreen-backdrop" id="backdrop">
  <!-- Top HUD Bar -->
  <div class="top-hud">
    <div class="hud-left">
      <div id="window-bar-left"></div>
    </div>

    <div class="hud-center">
      <div class="preview-pill" id="preview-pill">
        Point to focus &nbsp;&middot;&nbsp; Drag in any direction: L-Drag = Move Win, R-Drag = Move + Go
      </div>
    </div>

    <div class="hud-right">
      <button class="pill-btn" id="rename-current-btn" onclick="openRenameModal(STATE.focusedWorkspace)" title="Rename Desktop (Press R)">
        <span>✎ Rename</span>
      </button>
      <button class="pill-btn" id="toggle-empty" onclick="toggleShowEmpty()" title="Toggle between compact empty numbers vs full empty cards (Tab)">
        <span id="toggle-empty-label">Small Empty #s</span>
      </button>
      <div class="mode-group">
        <button class="pill-btn" id="layout-grid" onclick="setLayout('grid')">Grid</button>
        <button class="pill-btn" id="layout-radial" onclick="setLayout('radial')">Radial</button>
        <button class="pill-btn" id="layout-list" onclick="setLayout('list')">List</button>
      </div>
    </div>
  </div>

  <!-- Main Fullscreen Workspace Canvas -->
  <div class="content" id="content"></div>

  <!-- Shortcut Legend Footer -->
  <div class="footer">
    <div>
      <span class="kbd">L-Click App / Angle</span> Focus App &amp; Desktop &nbsp;&middot;&nbsp;
      <span class="kbd">L-Drag App</span> Move Win &nbsp;&middot;&nbsp;
      <span class="kbd">R-Drag App</span> Move + Follow
    </div>
    <div>
      <span class="kbd">1-9,0,C,G,I,M,O</span> Key Jump &nbsp;&middot;&nbsp;
      <span class="kbd">R</span> Rename Desktop &nbsp;&middot;&nbsp;
      <span class="kbd">Tab</span> Empty Style &nbsp;&middot;&nbsp;
      <span class="kbd">Esc</span> Close
    </div>
  </div>
</div>

<!-- Rename Desktop Modal -->
<div class="rename-modal-backdrop" id="rename-modal-backdrop" onmousedown="if(event.target.id==='rename-modal-backdrop') closeRenameModal()">
  <div class="rename-modal">
    <div class="rename-modal-title" id="rename-modal-title">Rename Desktop</div>
    <input type="text" class="rename-input" id="rename-input" placeholder="Enter custom desktop name (empty to reset)" />
    <div class="rename-modal-actions">
      <button class="pill-btn" onclick="closeRenameModal()">Cancel (Esc)</button>
      <button class="pill-btn active-switch" onclick="saveRenameModal()">Save (Enter)</button>
    </div>
  </div>
</div>

<!-- Floating Drag Ghost -->
<div class="drag-ghost" id="drag-ghost">
  <img id="drag-ghost-img" src="" alt="" style="display:none;">
  <span class="drag-ghost-text" id="drag-ghost-text"></span>
  <span class="drag-ghost-badge" id="drag-ghost-badge">Move</span>
</div>

<script>
  let STATE = {
    focusedWorkspace: "1",
    focusedWindow: null,
    workspaces: [],
    layout: "radial",
    showEmpty: false,
    originX: null,
    originY: null
  };

  let currentMode = "switch"; // "switch" | "move" | "follow"
  let modifierHeldMode = null;

  // Custom Drag & Drop State (supports both Left-Drag and Right-Drag!)
  let dragState = null;
  let suppressClickUntil = 0;

  function postMessage(payload) {
    try {
      window.webkit.messageHandlers.aerospaceSwitcher.postMessage(payload);
    } catch (e) {
      console.error("Failed to post message", e);
    }
  }

  function effectiveMode() {
    return modifierHeldMode || currentMode;
  }

  function setActionMode(mode) {
    currentMode = mode;
    updateModeUI();
  }

  function setPreviewText(html) {
    const el = document.getElementById("preview-pill");
    if (el) el.innerHTML = html;
  }

  function updateModeUI() {
    // Upper mode selector removed; visual cues now live on the focusing ray, wedges, and drag ghost
  }

  function setLayout(layout) {
    STATE.layout = layout;
    postMessage({ action: "saveSettings", layout: layout, showEmpty: STATE.showEmpty });
    render();
  }

  function toggleShowEmpty() {
    STATE.showEmpty = !STATE.showEmpty;
    postMessage({ action: "saveSettings", layout: STATE.layout, showEmpty: STATE.showEmpty });
    render();
  }

  function triggerWorkspace(wsName, explicitMode, ev, customMoveWinId, keepOpen, focusWinId) {
    if (ev) {
      ev.stopPropagation();
      ev.preventDefault();
    }
    let mode = explicitMode || effectiveMode();
    if (!explicitMode && ev) {
      if (ev.shiftKey) mode = "move";
      else if (ev.metaKey || ev.altKey) mode = "follow";
    }
    postMessage({
      action: "workspace",
      workspace: wsName,
      mode: mode,
      windowId: customMoveWinId || (STATE.focusedWindow ? STATE.focusedWindow.id : ""),
      keepOpen: !!keepOpen,
      focusWindowId: focusWinId || ""
    });
  }

  function handleWorkspaceClick(wsName, ev, focusWinId) {
    if (Date.now() < suppressClickUntil) return;
    if (dragState && dragState.active) return;
    ev.stopPropagation();
    ev.preventDefault();

    // Ignore middle button (button === 1) so middle-clicks never act like a click
    if (ev.button === 1) return;

    if (ev.button === 2) {
      triggerWorkspace(wsName, "move", ev, null, false, focusWinId);
    } else if (ev.button === 0) {
      triggerWorkspace(wsName, null, ev, null, false, focusWinId);
    }
  }

  function escapeHtml(str) {
    if (!str) return "";
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  // Render individual window icons so each window can be individually zoomed, focused, or dragged
  function renderWindowIcons(windows, wsName, maxIcons) {
    if (!windows || windows.length === 0) {
      return `<span style="font-size:11px;color:#64748b;font-style:italic;">Empty</span>`;
    }
    const slice = maxIcons ? windows.slice(0, maxIcons) : windows;
    let html = slice.map(w => {
      const displayTitle = (w.title && w.title !== w.appName) ? `${w.appName} — ${w.title}` : w.appName;
      const shortLabel = (w.title && w.title !== w.appName) ? w.title : w.appName;
      const focusedClass = w.isFocusedWindow ? "is-focused-win" : "";
      const winId = escapeHtml(w.id || "");
      const iconSrc = w.icon || "";

      const inner = iconSrc
        ? `<img class="app-icon" src="${iconSrc}" alt="${escapeHtml(w.appName)}">`
        : `<div class="app-fallback">${escapeHtml((w.appName || "?").slice(0, 2))}</div>`;

      return `
        <div class="app-icon-wrap draggable-item ${focusedClass}"
             data-win-id="${winId}"
             data-focus-win-id="${winId}"
             data-source-ws="${escapeHtml(wsName)}"
             data-win-label="${escapeHtml(w.appName)}"
             data-win-title="${escapeHtml(displayTitle)}"
             data-win-icon="${iconSrc}"
             onmouseenter="onWindowHover('${escapeHtml(wsName)}', '${escapeHtml(displayTitle)}')"
             title="${escapeHtml(displayTitle)}\n• Click: Switch & Focus this window\n• L-Drag: Move window\n• R-Drag: Move window & follow">
          ${inner}
          <div class="app-zoom-label">${escapeHtml(shortLabel)}</div>
        </div>
      `;
    }).join("");

    if (maxIcons && windows.length > maxIcons) {
      html += `<span class="key-hint">+${windows.length - maxIcons}</span>`;
    }
    return html;
  }

  let hoveredWsName = null;
  let renamingWsName = null;

  function openRenameModal(wsName, ev) {
    if (ev) {
      ev.stopPropagation();
      ev.preventDefault();
    }
    const targetWs = wsName || (activeRadialSelection && activeRadialSelection.wsName) || hoveredWsName || STATE.focusedWorkspace;
    if (!targetWs) return;
    renamingWsName = targetWs;
    const wsObj = STATE.workspaces.find(w => w.name === targetWs);
    const currentLabel = wsObj ? wsObj.label : "";

    document.getElementById("rename-modal-title").textContent = `Rename Desktop ${targetWs.toUpperCase()}`;
    const inp = document.getElementById("rename-input");
    inp.value = currentLabel;
    document.getElementById("rename-modal-backdrop").style.display = "flex";
    postMessage({ action: "focusWebview" });
    setTimeout(() => {
      inp.focus();
      inp.select();
    }, 30);
  }

  function closeRenameModal() {
    renamingWsName = null;
    document.getElementById("rename-modal-backdrop").style.display = "none";
    postMessage({ action: "closeRename" });
  }

  function saveRenameModal() {
    if (!renamingWsName) return;
    const val = document.getElementById("rename-input").value.trim();
    const wsObj = STATE.workspaces.find(w => w.name === renamingWsName);
    if (wsObj) {
      wsObj.label = val !== "" ? val : (wsObj.defaultLabel || ("Workspace " + renamingWsName));
    }
    postMessage({ action: "renameWorkspace", workspace: renamingWsName, label: val });
    closeRenameModal();
    render();
  }

  function onWindowHover(wsName, displayTitle) {
    hoveredWsName = wsName;
    setPreviewText(`Desktop <b>${escapeHtml(wsName.toUpperCase())}</b> &rarr; Focus <b>${escapeHtml(displayTitle)}</b>`);
  }

  function renderGrid(workspaces, compactEmpty) {
    const cards = workspaces.map(ws => {
      const isEmpty = (ws.windowCount === 0 && !ws.isFocused);
      if (isEmpty && compactEmpty) {
        return `
          <div class="ws-card-empty-compact"
               data-drop-ws="${escapeHtml(ws.name)}"
               onmouseenter="setPreviewText('Empty Desktop <b>${escapeHtml(ws.name.toUpperCase())}</b> (${escapeHtml(ws.label)})')"
               onmouseup="handleWorkspaceClick('${escapeHtml(ws.name)}', event)"
               oncontextmenu="event.preventDefault()">
            <span class="ws-card-empty-num">${escapeHtml(ws.name.toUpperCase())}</span>
          </div>
        `;
      }

      const focusedClass = ws.isFocused ? "focused" : "";
      return `
        <div class="ws-card ${focusedClass}"
             data-drop-ws="${escapeHtml(ws.name)}"
             onmouseenter="hoveredWsName='${escapeHtml(ws.name)}'; setPreviewText('Desktop <b>${escapeHtml(ws.name.toUpperCase())}</b> — ${escapeHtml(ws.label)}')"
             onmouseup="handleWorkspaceClick('${escapeHtml(ws.name)}', event)"
             oncontextmenu="event.preventDefault()">
          <div class="ws-card-top">
            <div class="ws-badge-wrap">
              <div class="ws-badge">${escapeHtml(ws.name.toUpperCase())}</div>
              <div class="ws-label">${escapeHtml(ws.label)}</div>
            </div>
            <div style="display:flex;align-items:center;gap:4px;">
              <button class="rename-btn" title="Rename Desktop" onmousedown="event.stopPropagation()" onmouseup="openRenameModal('${escapeHtml(ws.name)}', event)">✎</button>
              <span class="key-hint">${escapeHtml(ws.hint)}</span>
            </div>
          </div>
          <div class="ws-icons">
            ${renderWindowIcons(ws.windows, ws.name, 8)}
          </div>
        </div>
      `;
    }).join("");

    return `<div class="grid-container">${cards}</div>`;
  }

  // ==================== RADIAL VIEW WITH SUB-ANGLE WINDOW SELECTION ====================
  let radialSectors = [];
  let activeRadialSelection = null; // { wsName, wsLabel, windowObj }

  function renderRadial(workspaces, compactEmpty) {
    // Give workspaces with more windows slightly more angular room so cards & icons never overlap
    const items = workspaces.map(ws => {
      const isEmpty = (ws.windowCount === 0 && !ws.isFocused);
      const isCompact = isEmpty && compactEmpty;
      const winExtra = Math.min(Math.max(ws.windowCount - 1, 0) * 0.22, 0.88);
      return {
        ws: ws,
        isCompact: isCompact,
        weight: isCompact ? 0.34 : (1.15 + winExtra)
      };
    });

    const totalWeight = items.reduce((acc, it) => acc + it.weight, 0) || 1;
    let cumulative = 0;

    radialSectors = [];
    activeRadialSelection = null;

    const nodes = items.map(it => {
      const ws = it.ws;
      const centerWeight = cumulative + (it.weight / 2);
      const startAngle = (cumulative / totalWeight) * (2 * Math.PI) - (Math.PI / 2);
      const endAngle = ((cumulative + it.weight) / totalWeight) * (2 * Math.PI) - (Math.PI / 2);
      const angle = (centerWeight / totalWeight) * (2 * Math.PI) - (Math.PI / 2);
      cumulative += it.weight;

      const rx = it.isCompact ? 38.0 : 39.0;
      const ry = it.isCompact ? 40.0 : 41.0;
      const x = 50 + (Math.cos(angle) * rx);
      const y = 50 + (Math.sin(angle) * ry);

      // Subdivide this workspace's angular sector into sub-slices for each individual window.
      // In the bottom half of the circle (sin(angle) > 0.15), increasing clockwise angle moves RIGHT-to-LEFT on screen,
      // while icons inside the card are laid out LEFT-to-RIGHT. Reversing the sub-slice order in the bottom half
      // ensures moving the mouse left/right always selects the left/right icon naturally!
      const wins = ws.windows || [];
      const subSlices = [];
      if (wins.length > 0) {
        const span = endAngle - startAngle;
        const reverseOrder = Math.sin(angle) > 0.15;
        wins.forEach((w, idx) => {
          const slotIdx = reverseOrder ? (wins.length - 1 - idx) : idx;
          const sA = startAngle + (slotIdx / wins.length) * span;
          const eA = startAngle + ((slotIdx + 1) / wins.length) * span;
          subSlices.push({
            startAngle: sA,
            endAngle: eA,
            midAngle: (sA + eA) / 2,
            window: w
          });
        });
      }

      radialSectors.push({
        name: ws.name,
        label: ws.label,
        angle: angle,
        startAngle: startAngle,
        endAngle: endAngle,
        xPct: x,
        yPct: y,
        isCompact: it.isCompact,
        windows: wins,
        subSlices: subSlices
      });

      if (it.isCompact) {
        return `
          <div class="radial-empty-node"
               data-drop-ws="${escapeHtml(ws.name)}"
               data-radial-ws="${escapeHtml(ws.name)}"
               style="left: ${x.toFixed(2)}%; top: ${y.toFixed(2)}%;"
               title="${escapeHtml(ws.label)} — Empty"
               onmouseup="handleWorkspaceClick('${escapeHtml(ws.name)}', event)"
               oncontextmenu="event.preventDefault()">
            ${escapeHtml(ws.name.toUpperCase())}
          </div>
        `;
      }

      const focusedClass = ws.isFocused ? "focused" : "";
      return `
        <div class="radial-node ${focusedClass}"
             data-drop-ws="${escapeHtml(ws.name)}"
             data-radial-ws="${escapeHtml(ws.name)}"
             style="left: ${x.toFixed(2)}%; top: ${y.toFixed(2)}%;"
             onmouseup="handleWorkspaceClick('${escapeHtml(ws.name)}', event)"
             oncontextmenu="event.preventDefault()">
          <div class="radial-node-top">
            <div class="radial-node-badge">${escapeHtml(ws.name.toUpperCase())}</div>
            <span class="radial-node-label">${escapeHtml(ws.label)}</span>
            <button class="rename-btn" title="Rename Desktop" onmousedown="event.stopPropagation()" onmouseup="openRenameModal('${escapeHtml(ws.name)}', event)">✎</button>
          </div>
          <div class="radial-icons">
            ${renderWindowIcons(ws.windows, ws.name, 6)}
          </div>
        </div>
      `;
    }).join("");

    return `
      <div class="radial-stage" id="radial-stage"
           onmouseup="handleRadialStageMouseUp(event)">
        <svg class="radial-svg" id="radial-svg" viewBox="0 0 100 100" preserveAspectRatio="none">
          <path id="radial-wedge" d="" fill="rgba(79, 140, 255, 0.14)" stroke="rgba(79, 140, 255, 0.45)" stroke-width="0.28" style="display:none;" />
          <path id="radial-sub-wedge" d="" fill="rgba(168, 85, 247, 0.22)" stroke="rgba(192, 132, 252, 0.75)" stroke-width="0.32" style="display:none;" />
          <line id="radial-ray" x1="50" y1="50" x2="50" y2="50" stroke="rgba(96, 165, 250, 0.95)" stroke-width="0.55" stroke-dasharray="1.2 0.7" style="display:none;" />
          <line id="radial-cursor-line" x1="50" y1="50" x2="50" y2="50" stroke="rgba(255, 255, 255, 0.65)" stroke-width="0.32" style="display:none;" />
          <circle id="radial-target-dot" cx="50" cy="50" r="0.9" fill="#60a5fa" style="display:none;" />
        </svg>
        <div class="radial-center" id="radial-center" style="left:50%;top:50%;"
             onmouseup="event.stopPropagation(); postMessage({action:'close'})"
             title="Click center to close">
          <img class="radial-center-icon" id="radial-center-icon" src="" alt="">
          <div class="radial-center-ws" id="radial-center-ws">${escapeHtml(STATE.focusedWorkspace.toUpperCase())}</div>
          <div class="radial-center-sub" id="radial-center-sub">Move mouse slightly<br>to select desktop &amp; app</div>
        </div>
        ${nodes}
      </div>
    `;
  }

  function normalizeAngleDiff(a, b) {
    let d = a - b;
    while (d > Math.PI) d -= 2 * Math.PI;
    while (d < -Math.PI) d += 2 * Math.PI;
    return Math.abs(d);
  }

  function findRadialTargetByAngle(clientX, clientY) {
    const stage = document.getElementById("radial-stage");
    if (!stage || radialSectors.length === 0) return null;
    const rect = stage.getBoundingClientRect();
    const cx = rect.left + rect.width / 2;
    const cy = rect.top + rect.height / 2;
    const dx = clientX - cx;
    const dy = clientY - cy;
    const dist = Math.hypot(dx, dy);

    // Deadzone inside center hub (36px)
    if (dist < 36) return null;

    const ndx = dx / (rect.width / 2);
    const ndy = dy / (rect.height / 2);
    let angle = Math.atan2(ndy, ndx);

    let chosenSector = null;
    let bestDiff = Infinity;
    for (const sec of radialSectors) {
      let a = angle;
      while (a < sec.startAngle) a += 2 * Math.PI;
      while (a >= sec.startAngle + 2 * Math.PI) a -= 2 * Math.PI;
      if (a >= sec.startAngle && a <= sec.endAngle) {
        chosenSector = sec;
        angle = a;
        break;
      }
      const diff = normalizeAngleDiff(angle, sec.angle);
      if (diff < bestDiff) {
        bestDiff = diff;
        chosenSector = sec;
      }
    }

    if (!chosenSector) return null;

    // Determine which individual window sub-slice within this workspace sector the angle points at
    let chosenSub = null;
    if (chosenSector.subSlices && chosenSector.subSlices.length > 0) {
      let a = angle;
      while (a < chosenSector.startAngle) a += 2 * Math.PI;
      while (a >= chosenSector.startAngle + 2 * Math.PI) a -= 2 * Math.PI;
      for (const sub of chosenSector.subSlices) {
        if (a >= sub.startAngle && a <= sub.endAngle) {
          chosenSub = sub;
          break;
        }
      }
      if (!chosenSub) {
        chosenSub = chosenSector.subSlices[0];
      }
    }

    return {
      sector: chosenSector,
      subSlice: chosenSub,
      window: chosenSub ? chosenSub.window : null
    };
  }

  function updateRadialSelectionVisuals(target, directWinEl, clientX, clientY) {
    document.querySelectorAll(".sector-selected").forEach(el => el.classList.remove("sector-selected"));
    document.querySelectorAll(".app-selected").forEach(el => el.classList.remove("app-selected"));

    const stage = document.getElementById("radial-stage");
    const ray = document.getElementById("radial-ray");
    const cursorLine = document.getElementById("radial-cursor-line");
    const targetDot = document.getElementById("radial-target-dot");
    const wedge = document.getElementById("radial-wedge");
    const subWedge = document.getElementById("radial-sub-wedge");
    const cIcon = document.getElementById("radial-center-icon");
    const cWs = document.getElementById("radial-center-ws");
    const cSub = document.getElementById("radial-center-sub");

    if (!target || !target.sector || !stage) {
      activeRadialSelection = null;
      if (ray) ray.style.display = "none";
      if (cursorLine) cursorLine.style.display = "none";
      if (targetDot) targetDot.style.display = "none";
      if (wedge) wedge.style.display = "none";
      if (subWedge) subWedge.style.display = "none";
      if (cIcon) cIcon.style.display = "none";
      if (cWs) cWs.textContent = STATE.focusedWorkspace.toUpperCase();
      if (cSub) cSub.innerHTML = "Move mouse slightly<br>to select desktop &amp; app";
      return;
    }

    const stageRect = stage.getBoundingClientRect();
    const sector = target.sector;
    let win = target.window;

    // If hovering directly over a specific window icon, prefer that exact window and its sub-slice
    let activeSubSlice = target.subSlice;
    if (directWinEl) {
      const wid = directWinEl.getAttribute("data-focus-win-id");
      if (wid && sector.windows) {
        const found = sector.windows.find(w => String(w.id) === String(wid));
        if (found) win = found;
      }
      if (wid && sector.subSlices) {
        const foundSub = sector.subSlices.find(s => s.window && String(s.window.id) === String(wid));
        if (foundSub) activeSubSlice = foundSub;
      }
    }

    activeRadialSelection = {
      wsName: sector.name,
      wsLabel: sector.label,
      window: win
    };

    const node = document.querySelector(`[data-radial-ws="${CSS.escape(sector.name)}"]`);
    let targetIconEl = null;
    if (node) {
      node.classList.add("sector-selected");
      if (win && win.id) {
        targetIconEl = node.querySelector(`[data-focus-win-id="${CSS.escape(String(win.id))}"]`);
        if (targetIconEl) targetIconEl.classList.add("app-selected");
      }
    }

    if (win) {
      const title = (win.title && win.title !== win.appName) ? `${win.appName} — ${win.title}` : win.appName;
      if (cIcon && win.icon) {
        cIcon.src = win.icon;
        cIcon.style.display = "block";
      } else if (cIcon) {
        cIcon.style.display = "none";
      }
      if (cWs) cWs.textContent = sector.name.toUpperCase();
      if (cSub) cSub.textContent = title;
      setPreviewText(`Desktop <b>${escapeHtml(sector.name.toUpperCase())}</b> &rarr; Focus <b>${escapeHtml(title)}</b>`);
    } else {
      if (cIcon) cIcon.style.display = "none";
      if (cWs) cWs.textContent = sector.name.toUpperCase();
      if (cSub) cSub.textContent = sector.label;
      setPreviewText(`Switch to Desktop <b>${escapeHtml(sector.name.toUpperCase())}</b> (${escapeHtml(sector.label)})`);
    }

    const mode = (dragState && dragState.active) ? dragState.mode : effectiveMode();
    const strokeColor = mode === "move"
      ? "rgba(245, 158, 11, 0.95)"
      : (mode === "follow" ? "rgba(16, 185, 129, 0.95)" : (win ? "rgba(192, 132, 252, 0.95)" : "rgba(96, 165, 250, 0.95)"));
    const fillColor = mode === "move"
      ? "rgba(245, 158, 11, 0.13)"
      : (mode === "follow" ? "rgba(16, 185, 129, 0.13)" : "rgba(79, 140, 255, 0.13)");

    // Aim the focusing ray at the center of the active sub-slice (or sector center if 1/0 windows)
    const rayAngle = (activeSubSlice && sector.subSlices && sector.subSlices.length > 1)
      ? activeSubSlice.midAngle
      : sector.angle;
    const rx = sector.isCompact ? 38.0 : 39.0;
    const ry = sector.isCompact ? 40.0 : 41.0;
    const rayX = 50 + (Math.cos(rayAngle) * rx);
    const rayY = 50 + (Math.sin(rayAngle) * ry);

    if (ray) {
      ray.setAttribute("x2", rayX.toFixed(2));
      ray.setAttribute("y2", rayY.toFixed(2));
      ray.setAttribute("stroke", strokeColor);
      ray.style.display = "block";
    }

    if (targetDot) {
      targetDot.setAttribute("cx", rayX.toFixed(2));
      targetDot.setAttribute("cy", rayY.toFixed(2));
      targetDot.setAttribute("fill", strokeColor);
      targetDot.style.display = "block";
    }

    if (cursorLine && typeof clientX === "number" && typeof clientY === "number" && stageRect.width > 0 && stageRect.height > 0) {
      const mx = ((clientX - stageRect.left) / stageRect.width) * 100;
      const my = ((clientY - stageRect.top) / stageRect.height) * 100;
      cursorLine.setAttribute("x2", mx.toFixed(2));
      cursorLine.setAttribute("y2", my.toFixed(2));
      cursorLine.style.display = "block";
    }

    if (wedge) {
      const r = 43;
      const x1 = 50 + Math.cos(sector.startAngle) * r;
      const y1 = 50 + Math.sin(sector.startAngle) * r;
      const x2 = 50 + Math.cos(sector.endAngle) * r;
      const y2 = 50 + Math.sin(sector.endAngle) * r;
      const d = `M 50 50 L ${x1.toFixed(2)} ${y1.toFixed(2)} A ${r} ${r} 0 0 1 ${x2.toFixed(2)} ${y2.toFixed(2)} Z`;
      wedge.setAttribute("d", d);
      wedge.setAttribute("fill", fillColor);
      wedge.setAttribute("stroke", strokeColor);
      wedge.style.display = "block";
    }

    if (subWedge && activeSubSlice && sector.subSlices && sector.subSlices.length > 1) {
      const r = 43;
      const sub = activeSubSlice;
      const x1 = 50 + Math.cos(sub.startAngle) * r;
      const y1 = 50 + Math.sin(sub.startAngle) * r;
      const x2 = 50 + Math.cos(sub.endAngle) * r;
      const y2 = 50 + Math.sin(sub.endAngle) * r;
      const d = `M 50 50 L ${x1.toFixed(2)} ${y1.toFixed(2)} A ${r} ${r} 0 0 1 ${x2.toFixed(2)} ${y2.toFixed(2)} Z`;
      subWedge.setAttribute("d", d);
      subWedge.style.display = "block";
    } else if (subWedge) {
      subWedge.style.display = "none";
    }
  }

  function handleRadialMouseMove(ev) {
    if (STATE.layout !== "radial") return;
    const directWinEl = ev.target ? ev.target.closest("[data-focus-win-id]") : null;
    const target = findRadialTargetByAngle(ev.clientX, ev.clientY);
    updateRadialSelectionVisuals(target, directWinEl, ev.clientX, ev.clientY);
  }

  function handleRadialStageMouseUp(ev) {
    if (STATE.layout !== "radial") return;
    if (Date.now() < suppressClickUntil) return;
    if (dragState && dragState.active) return;
    if (ev.button === 1) return; // Ignore middle mouse button inside radial stage

    const target = findRadialTargetByAngle(ev.clientX, ev.clientY);
    if (target && target.sector) {
      const focusWinId = target.window ? target.window.id : "";
      handleWorkspaceClick(target.sector.name, ev, focusWinId);
    } else if (ev.target.id === "radial-stage") {
      // Clicked outside center deadzone with no sector -> close
      postMessage({ action: "close" });
    }
  }

  function renderList(workspaces, compactEmpty) {
    const rows = workspaces.map(ws => {
      const isEmpty = (ws.windowCount === 0 && !ws.isFocused);
      if (isEmpty && compactEmpty) {
        return `
          <div class="list-empty-inline"
               data-drop-ws="${escapeHtml(ws.name)}"
               onmouseenter="setPreviewText('Empty Desktop <b>${escapeHtml(ws.name.toUpperCase())}</b> (${escapeHtml(ws.label)})')"
               onmouseup="handleWorkspaceClick('${escapeHtml(ws.name)}', event)"
               oncontextmenu="event.preventDefault()">
            <span>${escapeHtml(ws.name.toUpperCase())}</span>
          </div>
        `;
      }

      const focusedClass = ws.isFocused ? "focused" : "";
      let winChips = "";
      if (!ws.windows || ws.windows.length === 0) {
        winChips = `<span style="font-size:11.5px;color:#64748b;font-style:italic;">No open windows</span>`;
      } else {
        winChips = ws.windows.map(w => {
          const iconHtml = w.icon
            ? `<img src="${w.icon}" alt="">`
            : `<span class="key-hint">${escapeHtml((w.appName || "?").slice(0, 1))}</span>`;
          const label = (w.title && w.title !== w.appName)
            ? `${w.appName} — ${w.title}`
            : w.appName;
          const fWinClass = w.isFocusedWindow ? "is-focused-win" : "";
          return `
            <div class="list-win-chip draggable-item ${fWinClass}"
                 data-win-id="${escapeHtml(w.id)}"
                 data-focus-win-id="${escapeHtml(w.id)}"
                 data-source-ws="${escapeHtml(ws.name)}"
                 data-win-label="${escapeHtml(w.appName)}"
                 data-win-title="${escapeHtml(label)}"
                 data-win-icon="${w.icon || ''}"
                 onmouseenter="onWindowHover('${escapeHtml(ws.name)}', '${escapeHtml(label)}')"
                 title="${escapeHtml(label)}\n• Click: Switch & Focus this window\n• L-Drag: Move window\n• R-Drag: Move window & follow">
              ${iconHtml}
              <span class="list-win-text">${escapeHtml(label)}</span>
            </div>
          `;
        }).join("");
      }

      return `
        <div class="list-row ${focusedClass}"
             data-drop-ws="${escapeHtml(ws.name)}"
             onmouseenter="hoveredWsName='${escapeHtml(ws.name)}'; setPreviewText('Desktop <b>${escapeHtml(ws.name.toUpperCase())}</b> — ${escapeHtml(ws.label)}')"
             onmouseup="handleWorkspaceClick('${escapeHtml(ws.name)}', event)"
             oncontextmenu="event.preventDefault()">
          <div class="list-left">
            <div class="ws-badge">${escapeHtml(ws.name.toUpperCase())}</div>
            <div>
              <div style="font-size:13.5px;font-weight:600;color:#f8fafc;display:flex;align-items:center;gap:6px;">
                <span>${escapeHtml(ws.label)}</span>
                <button class="rename-btn" title="Rename Desktop" onmousedown="event.stopPropagation()" onmouseup="openRenameModal('${escapeHtml(ws.name)}', event)">✎</button>
              </div>
              <div style="font-size:10.5px;color:#94a3b8;">Key: ${escapeHtml(ws.hint)}</div>
            </div>
          </div>
          <div class="list-windows">${winChips}</div>
        </div>
      `;
    }).join("");

    return `<div class="list-container">${rows}</div>`;
  }

  function render() {
    updateModeUI();

    document.getElementById("layout-grid").className   = "pill-btn" + (STATE.layout === "grid"   ? " active-layout" : "");
    document.getElementById("layout-radial").className = "pill-btn" + (STATE.layout === "radial" ? " active-layout" : "");
    document.getElementById("layout-list").className   = "pill-btn" + (STATE.layout === "list"   ? " active-layout" : "");

    const emptyBtn = document.getElementById("toggle-empty");
    const emptyLbl = document.getElementById("toggle-empty-label");
    emptyBtn.className = "pill-btn" + (STATE.showEmpty ? " active-layout" : "");
    emptyLbl.textContent = STATE.showEmpty ? "Full Empty Cards" : "Small Empty #s";

    // Focused window bar in top HUD (also draggable!)
    const winLeft = document.getElementById("window-bar-left");
    if (STATE.focusedWindow && STATE.focusedWindow.appName) {
      const fw = STATE.focusedWindow;
      const iconHtml = fw.icon ? `<img class="window-bar-icon" src="${fw.icon}">` : "";
      const titleText = fw.title && fw.title !== fw.appName ? `${fw.appName} — ${fw.title}` : fw.appName;
      winLeft.innerHTML = `
        <div class="draggable-active-win draggable-item"
             data-win-id="${escapeHtml(fw.id)}"
             data-focus-win-id="${escapeHtml(fw.id)}"
             data-source-ws="${escapeHtml(fw.workspace)}"
             data-win-label="${escapeHtml(fw.appName)}"
             data-win-icon="${fw.icon || ''}"
             title="Active Window — Drag onto any desktop (Left-drag = Move · Right-drag = Move & Follow)">
          ${iconHtml}
          <span class="window-bar-title">${escapeHtml(titleText)}</span>
        </div>
      `;
    } else {
      winLeft.innerHTML = `<span style="font-size:12.5px;color:#94a3b8;">Desktop <b>${escapeHtml(STATE.focusedWorkspace.toUpperCase())}</b></span>`;
    }

    const compactEmpty = !STATE.showEmpty;
    const content = document.getElementById("content");
    if (STATE.layout === "radial") {
      content.innerHTML = renderRadial(STATE.workspaces, compactEmpty);
      if (lastMouseClientX !== null && lastMouseClientY !== null) {
        const el = document.elementFromPoint(lastMouseClientX, lastMouseClientY);
        const directWinEl = el ? el.closest("[data-focus-win-id]") : null;
        const target = findRadialTargetByAngle(lastMouseClientX, lastMouseClientY);
        updateRadialSelectionVisuals(target, directWinEl, lastMouseClientX, lastMouseClientY);
      }
    } else if (STATE.layout === "list") {
      content.innerHTML = renderList(STATE.workspaces, compactEmpty);
    } else {
      content.innerHTML = renderGrid(STATE.workspaces, compactEmpty);
    }
  }

  // ==================== DRAG & DROP + INDIVIDUAL WINDOW CLICK ENGINE ====================
  function clearDropHighlights() {
    document.querySelectorAll(".drop-target-move, .drop-target-follow").forEach(el => {
      el.classList.remove("drop-target-move", "drop-target-follow");
    });
  }

  function findDropWorkspaceElement(x, y) {
    const el = document.elementFromPoint(x, y);
    const direct = el ? el.closest("[data-drop-ws]") : null;
    if (direct) return direct;

    // In Radial mode, allow dropping based on angle without reaching the outer ring
    if (STATE.layout === "radial") {
      const target = findRadialTargetByAngle(x, y);
      if (target && target.sector && target.sector.name) {
        return document.querySelector(`[data-drop-ws="${CSS.escape(target.sector.name)}"]`);
      }
    }
    return null;
  }

  window.addEventListener("mousedown", function(ev) {
    if (ev.button !== 0 && ev.button !== 2) return;
    // Ignore clicks on top HUD controls (layout/empty buttons)
    if (ev.target.closest(".hud-right")) return;

    const item = ev.target.closest(".draggable-item");
    if (item) {
      const winId = item.getAttribute("data-win-id");
      if (!winId) return;

      ev.stopPropagation();
      ev.preventDefault();

      dragState = {
        winId: winId,
        focusWinId: item.getAttribute("data-focus-win-id") || winId,
        sourceWs: item.getAttribute("data-source-ws") || "",
        label: item.getAttribute("data-win-label") || "Window",
        icon: item.getAttribute("data-win-icon") || "",
        button: ev.button,
        mode: ev.button === 2 ? "follow" : "move",
        startX: ev.clientX,
        startY: ev.clientY,
        active: false,
        targetWs: null,
        fromStage: false
      };
      return;
    }

    // In Radial mode, allow starting a drag from ANYWHERE (e.g. right from the center or along the line)!
    // If you drag (move > 8px while holding L-Click or R-Click):
    //   * If started on/along an aimed window, it drags that window (or the currently focused window if started in the center).
    //   * Left-drag moves the window along the line to the aimed desktop; Right-drag moves it & switches view!
    if (STATE.layout === "radial") {
      const startTarget = findRadialTargetByAngle(ev.clientX, ev.clientY);
      const pickedWin = (startTarget && startTarget.window) ? startTarget.window : STATE.focusedWindow;
      if (pickedWin && pickedWin.id) {
        dragState = {
          winId: String(pickedWin.id),
          focusWinId: String(pickedWin.id),
          sourceWs: pickedWin.workspace || STATE.focusedWorkspace,
          label: pickedWin.appName || "Window",
          icon: pickedWin.icon || "",
          button: ev.button,
          mode: ev.button === 2 ? "follow" : "move",
          startX: ev.clientX,
          startY: ev.clientY,
          active: false,
          targetWs: null,
          fromStage: true
        };
      }
    }
  }, true);

  let lastMouseClientX = null;
  let lastMouseClientY = null;

  function updateDragProgress(clientX, clientY) {
    if (!dragState) return;
    const dx = clientX - dragState.startX;
    const dy = clientY - dragState.startY;
    if (!dragState.active && Math.hypot(dx, dy) > 8) {
      dragState.active = true;
      const ghost = document.getElementById("drag-ghost");
      const ghostImg = document.getElementById("drag-ghost-img");
      const ghostText = document.getElementById("drag-ghost-text");
      const ghostBadge = document.getElementById("drag-ghost-badge");

      ghost.className = "drag-ghost" + (dragState.mode === "follow" ? " ghost-follow" : "");
      if (dragState.icon) {
        ghostImg.src = dragState.icon;
        ghostImg.style.display = "block";
      } else {
        ghostImg.style.display = "none";
      }
      ghostText.textContent = dragState.label;
      ghostBadge.textContent = dragState.mode === "follow" ? "Move + Go" : "Move Win";
      ghost.style.display = "flex";
    }

    if (dragState.active) {
      const ghost = document.getElementById("drag-ghost");
      ghost.style.left = clientX + "px";
      ghost.style.top = clientY + "px";

      clearDropHighlights();
      const dropEl = findDropWorkspaceElement(clientX, clientY);
      if (dropEl) {
        const ws = dropEl.getAttribute("data-drop-ws");
        dragState.targetWs = ws;
        dropEl.classList.add(dragState.mode === "follow" ? "drop-target-follow" : "drop-target-move");
      } else {
        dragState.targetWs = null;
      }

      if (STATE.layout === "radial") {
        const target = findRadialTargetByAngle(clientX, clientY);
        updateRadialSelectionVisuals(target, null, clientX, clientY);
      }
    }
  }

  window.addEventListener("mousemove", function(ev) {
    lastMouseClientX = ev.clientX;
    lastMouseClientY = ev.clientY;
    if (STATE.layout === "radial") {
      handleRadialMouseMove(ev);
    }
    updateDragProgress(ev.clientX, ev.clientY);
  }, true);

  window.addEventListener("mouseup", function(ev) {
    if (!dragState) return;
    const st = dragState;
    dragState = null;

    const ghost = document.getElementById("drag-ghost");
    ghost.style.display = "none";
    clearDropHighlights();

    if (st.active) {
      suppressClickUntil = Date.now() + 200;
      ev.stopPropagation();
      ev.preventDefault();
      // Determine target workspace from drop element OR directly from the radial line angle!
      let targetWs = st.targetWs;
      if (!targetWs && STATE.layout === "radial") {
        const t = findRadialTargetByAngle(ev.clientX, ev.clientY);
        if (t && t.sector) targetWs = t.sector.name;
      }
      if (targetWs) {
        if (st.mode === "follow") {
          triggerWorkspace(targetWs, "follow", null, st.winId, false, st.winId);
        } else {
          triggerWorkspace(targetWs, "move", null, st.winId, true, "");
        }
      }
    } else if (!st.fromStage) {
      // It was a simple click on an individual app/window icon -> switch to that workspace AND focus that exact window!
      suppressClickUntil = Date.now() + 120;
      ev.stopPropagation();
      ev.preventDefault();
      if (st.button === 0 && effectiveMode() === "switch") {
        triggerWorkspace(st.sourceWs, "focus_window", null, "", false, st.focusWinId);
      } else {
        handleWorkspaceClick(st.sourceWs, ev, st.focusWinId);
      }
    }
  }, true);

  window.updateSwitcherState = function(newState) {
    STATE = newState;
    currentMode = "switch";
    modifierHeldMode = null;
    render();
  };

  window.onNativeMouseMove = function(x, y) {
    lastMouseClientX = x;
    lastMouseClientY = y;
    if (STATE.layout === "radial") {
      const el = document.elementFromPoint(x, y);
      const directWinEl = el ? el.closest("[data-focus-win-id]") : null;
      const target = findRadialTargetByAngle(x, y);
      updateRadialSelectionVisuals(target, directWinEl, x, y);
    }
    updateDragProgress(x, y);
  };

  window.setModifierHeld = function(mod) {
    modifierHeldMode = mod;
    updateModeUI();
  };

  window.triggerWorkspaceFromKey = function(wsName) {
    triggerWorkspace(wsName, effectiveMode(), null);
  };

  window.openRenameFromKey = function() {
    openRenameModal(null, null);
  };

  window.toggleShowEmpty = toggleShowEmpty;

  // Keyboard navigation & modifiers
  window.addEventListener("keydown", function(ev) {
    if (renamingWsName) {
      if (ev.key === "Escape") {
        ev.preventDefault();
        closeRenameModal();
      } else if (ev.key === "Enter") {
        ev.preventDefault();
        saveRenameModal();
      }
      return;
    }

    if (ev.key === "Escape") {
      ev.preventDefault();
      postMessage({ action: "close" });
      return;
    }
    if (ev.key === "Tab") {
      ev.preventDefault();
      toggleShowEmpty();
      return;
    }
    if (ev.key === "r" || ev.key === "R") {
      ev.preventDefault();
      openRenameModal(null, ev);
      return;
    }
    if (ev.key === "Shift") {
      modifierHeldMode = "move";
      updateModeUI();
      return;
    }
    if (ev.key === "Meta" || ev.key === "Alt") {
      modifierHeldMode = "follow";
      updateModeUI();
      return;
    }

    const k = ev.key.toLowerCase();
    for (const ws of STATE.workspaces) {
      if (ws.key === k || ws.name.toLowerCase() === k) {
        ev.preventDefault();
        let mode = effectiveMode();
        if (ev.shiftKey) mode = "move";
        else if (ev.metaKey || ev.altKey) mode = "follow";
        triggerWorkspace(ws.name, mode, ev);
        return;
      }
    }
  });

  window.addEventListener("keyup", function(ev) {
    if (ev.key === "Shift" || ev.key === "Meta" || ev.key === "Alt") {
      modifierHeldMode = null;
      updateModeUI();
    }
  });

  // Dismiss when clicking empty background space in Grid / List views (left/right click only, never middle click)
  document.getElementById("content").addEventListener("mousedown", function(ev) {
    if (ev.button === 1) {
      ev.preventDefault();
      ev.stopPropagation();
      return;
    }
    if (ev.target.id === "content" || ev.target.classList.contains("grid-container") || ev.target.classList.contains("list-container")) {
      postMessage({ action: "close" });
    }
  });

  // Prevent middle-click (auxclick) from doing anything in the webview
  window.addEventListener("auxclick", e => {
    if (e.button === 1) {
      e.preventDefault();
      e.stopPropagation();
    }
  }, true);

  window.addEventListener("contextmenu", e => e.preventDefault());
</script>
</body>
</html>
]=]

local function ensureWebview()
  if M.webview then return end

  M.userContent = hs.webview.usercontent.new("aerospaceSwitcher"):setCallback(function(msg)
    local body = msg and msg.body
    if type(body) ~= "table" then return end

    if body.action == "close" then
      M.close()
    elseif body.action == "saveSettings" then
      if body.layout then setSavedLayout(body.layout) end
      if body.showEmpty ~= nil then setSavedShowEmpty(body.showEmpty) end
      if M.cachedState then
        M.cachedState.layout = getSavedLayout()
        M.cachedState.showEmpty = getSavedShowEmpty()
      end
    elseif body.action == "renameWorkspace" then
      M.isRenaming = false
      setCustomLabel(body.workspace, body.label)
      if M.cachedState then
        pushStateToWebview(M.cachedState)
      end
    elseif body.action == "focusWebview" then
      M.isRenaming = true
      local hsApp = hs.application.applicationForPID(hs.processInfo.processID)
      if hsApp then hsApp:activate() end
      local win = M.webview and M.webview:hswindow()
      if win then win:focus() end
    elseif body.action == "closeRename" then
      M.isRenaming = false
    elseif body.action == "workspace" then
      M.performAction(body.workspace, body.mode, body.windowId, body.keepOpen, body.focusWindowId)
    end
  end)

  local screen = hs.screen.mainScreen():fullFrame()
  M.webview = hs.webview.new(screen, { developerExtrasEnabled = false }, M.userContent)
    :windowStyle({ "borderless", "utility" })
    :level(hs.drawing.windowLevels.popUpMenu)
    :transparent(true)
    :allowTextEntry(true)
    :shadow(false)
    :html(HTML_TEMPLATE)
end

function M.close()
  if M.webview and M.isOpen then
    M.webview:hide()
  end
  M.isOpen = false
  M.isRenaming = false
  if M.outsideTap then
    M.outsideTap:stop()
  end
  if M.escTap then
    M.escTap:stop()
  end
end

function M.show()
  ensureWebview()

  local currentScreen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  local screen = currentScreen:fullFrame()

  -- Fullscreen on the active display
  M.webview:frame({ x = screen.x, y = screen.y, w = screen.w, h = screen.h })

  -- In Radial mode, gently center the cursor in the middle of the radial stage so angle flicks work immediately in 360 degrees
  if getSavedLayout() == "radial" then
    local stageCenterX = screen.x + (screen.w / 2)
    local stageCenterY = screen.y + (screen.h / 2) + 8
    hs.mouse.absolutePosition({ x = stageCenterX, y = stageCenterY })
  end

  if M.cachedState then
    M.cachedState.layout = getSavedLayout()
    M.cachedState.showEmpty = getSavedShowEmpty()
    pushStateToWebview(M.cachedState)
  end

  M.webview:show()
  M.webview:bringToFront(true)

  M.isOpen = true

  if M.outsideTap then M.outsideTap:start() end
  if M.escTap then M.escTap:start() end

  -- Trigger a fresh async query so icons/titles are 100% up-to-date
  M.refreshStateAsync(function(freshState)
    if M.isOpen then
      pushStateToWebview(freshState)
    end
  end)
end

function M.toggle()
  if M.isOpen then
    M.close()
  else
    M.show()
  end
end

-- Eventtap to track mouse movement (even when unfocused) & dismiss if clicking on another monitor
M.outsideTap = hs.eventtap.new({
  hs.eventtap.event.types.leftMouseDown,
  hs.eventtap.event.types.rightMouseDown,
  hs.eventtap.event.types.mouseMoved,
  hs.eventtap.event.types.leftMouseDragged,
  hs.eventtap.event.types.rightMouseDragged,
}, function(event)
  if not M.isOpen or not M.webview then return false end
  local evType = event:getType()
  local pt = hs.mouse.absolutePosition()
  local f = M.webview:frame()

  if evType == hs.eventtap.event.types.mouseMoved
    or evType == hs.eventtap.event.types.leftMouseDragged
    or evType == hs.eventtap.event.types.rightMouseDragged then
    local relX = pt.x - f.x
    local relY = pt.y - f.y
    if relX >= 0 and relX <= f.w and relY >= 0 and relY <= f.h then
      M.webview:evaluateJavaScript(string.format("window.onNativeMouseMove && window.onNativeMouseMove(%d, %d);", math.floor(relX), math.floor(relY)))
    end
    return false
  end

  local inside = pt.x >= f.x and pt.x <= (f.x + f.w) and pt.y >= f.y and pt.y <= (f.y + f.h)
  if not inside then
    M.close()
  end
  return false
end)

-- Eventtap for Escape & workspace keyboard shortcuts
M.escTap = hs.eventtap.new({
  hs.eventtap.event.types.keyDown,
  hs.eventtap.event.types.flagsChanged,
}, function(event)
  if not M.isOpen then return false end
  local evType = event:getType()

  if evType == hs.eventtap.event.types.flagsChanged then
    local flags = event:getFlags()
    local mod = "null"
    if flags.shift then mod = "'move'"
    elseif flags.cmd or flags.alt then mod = "'follow'" end
    if M.webview then
      M.webview:evaluateJavaScript(string.format("window.setModifierHeld && window.setModifierHeld(%s);", mod))
    end
    return false
  end

  local keyCode = event:getKeyCode()
  local flags = event:getFlags()

  if M.isRenaming then
    -- Let the webview input handle all typing, Enter, Backspace, and Escape
    return false
  end

  if keyCode == hs.keycodes.map["escape"] then
    M.close()
    return true
  elseif keyCode == hs.keycodes.map["tab"] then
    if M.webview then
      M.webview:evaluateJavaScript("window.toggleShowEmpty && window.toggleShowEmpty();")
    end
    return true
  elseif keyCode == hs.keycodes.map["r"] and not flags.cmd and not flags.ctrl and not flags.alt then
    if M.webview then
      M.webview:evaluateJavaScript("window.openRenameFromKey && window.openRenameFromKey();")
    end
    return true
  end

  local chars = event:getCharacters(true)
  local k = chars and chars:lower() or ""
  if k ~= "" and M.cachedState and M.cachedState.workspaces then
    for _, ws in ipairs(M.cachedState.workspaces) do
      if ws.key == k or ws.name:lower() == k then
        local mode = nil
        if flags.shift then mode = "move"
        elseif flags.cmd or flags.alt then mode = "follow" end
        if mode then
          M.performAction(ws.name, mode)
        elseif M.webview then
          M.webview:evaluateJavaScript(string.format("window.triggerWorkspaceFromKey && window.triggerWorkspaceFromKey(%q);", ws.name))
        else
          M.performAction(ws.name, "switch")
        end
        return true
      end
    end
  end

  return false
end)

-- Single Middle-Click detector
-- Swallows otherMouseDown, otherMouseUp, and otherMouseDragged for middle button (button 2)
-- so middle-clicking opens/closes the switcher cleanly and NEVER triggers a click/paste/tab-close in apps.
local swallowNextMiddleUp = false

M.middleClickTap = hs.eventtap.new({
  hs.eventtap.event.types.otherMouseDown,
  hs.eventtap.event.types.otherMouseUp,
  hs.eventtap.event.types.otherMouseDragged,
}, function(event)
  local button = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber)
  if button ~= 2 then return false end -- button 2 is Middle Click (0=left, 1=right, 2=middle)

  local evType = event:getType()

  -- Always swallow the middle-button release and drag
  if evType == hs.eventtap.event.types.otherMouseUp then
    swallowNextMiddleUp = false
    return true
  end

  if evType == hs.eventtap.event.types.otherMouseDragged then
    return true
  end

  -- otherMouseDown: toggle the switcher on a single middle click!
  swallowNextMiddleUp = true
  if M.isOpen then
    M.close()
  else
    hs.timer.doAfter(0.01, function()
      M.show()
    end)
  end
  return true
end)

function M.start()
  ensureWebview()
  M.refreshStateAsync()
  M.middleClickTap:start()

  -- Keyboard shortcut to open/close switcher without the mouse: Cmd+Ctrl+Alt+Tab
  if not M.toggleHotkey then
    M.toggleHotkey = hs.hotkey.bind({ "cmd", "ctrl", "alt" }, "tab", function()
      M.toggle()
    end)
  end

  -- Refresh state when frontmost application changes
  if not M.appWatcher then
    M.appWatcher = hs.application.watcher.new(function(appName, eventType, appObject)
      if eventType == hs.application.watcher.activated or eventType == hs.application.watcher.launched or eventType == hs.application.watcher.terminated then
        if not M.isOpen then
          M.refreshStateAsync()
        end
      end
    end)
    M.appWatcher:start()
  end
end

M.start()

return M

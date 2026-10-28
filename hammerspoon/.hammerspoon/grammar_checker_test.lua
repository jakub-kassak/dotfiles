-- Run with: hs -c 'dofile(hs.configdir .. "/grammar_checker_test.lua")'
-- Isolated mocks: no network, key disclosure, real keystrokes or clipboard changes.
local real = hs
local checks = 0
local function check(condition, message)
    assert(condition, message)
    checks = checks + 1
end
local function result(text)
    return { language = "en", changed = true, corrected_text = text,
        corrections = {{ before = "are", after = "is", explanation = "Subject–verb agreement." }},
        dictionary = { definition = "", grammar = "", synonyms = {}, translations = { en = "", de = "", sk = "" } } }
end
local pb, count, pid, selected = "This are a longer test.", 1, 42, nil
local settings = { ["grammarChecker.provider"] = "gemini" }
local requests, timers, strokes = {}, {}, {}
local controller, popup, lastState, modal, watcher, appWatcher
local envValues = { HOME = os.getenv("HOME"), GOOGLE_API_KEY = "test-google", OPENAI_API_KEY = "test-openai" }
local secretLines
local function chain()
    return setmetatable({}, { __index = function(_, key)
        return function(self, ...) self[key .. "Args"] = {...}; return self end
    end })
end
local function timer(fn, every)
    local t = { fn = fn, every = every, active = true }
    function t:stop() self.active = false end
    timers[#timers + 1] = t
    return t
end
local element = { attributeValue = function(_, key)
    if key == "AXSelectedText" then return selected end
end }
local screen = { frame = function() return { x = -1440, y = 25, w = 1440, h = 850 } end }
local fake = {
    configdir = real.configdir, json = real.json,
    application = { frontmostApplication = function() return { pid = function() return pid end } end,
        watcher = { activated = 1, new = function(fn) appWatcher = chain(); appWatcher.fn = fn; return appWatcher end } },
    axuielement = { applicationElement = function() return { attributeValue = function() return element end } end },
    window = { frontmostWindow = function() return { id = function() return 7 end } end },
    screen = { mainScreen = function() return screen end },
    mouse = { absolutePosition = function() return { x = -1440, y = 25 } end, getCurrentScreen = function() return screen end },
    drawing = { windowLevels = { floating = 3 } },
    settings = { get = function(k) return settings[k] end, set = function(k, v) settings[k] = v end },
    pasteboard = {
        getContents = function() return pb end, changeCount = function() return count end,
        setContents = function(text) pb, count = text, count + 1; return true end,
        readAllData = function() return { text = pb } end,
        writeAllData = function(data) pb, count = data.text, count + 1; return true end,
    },
    timer = { doAfter = function(_, fn) return timer(fn, false) end, doEvery = function(_, fn) return timer(fn, true) end },
    http = { asyncPost = function(url, body, headers, callback)
        requests[#requests + 1] = { url = url, payload = real.json.decode(body), headers = headers, callback = callback }
    end },
    alert = { show = function() end },
    eventtap = { event = { types = { leftMouseDown = 1, rightMouseDown = 2 } },
        keyStroke = function(mods, key) strokes[#strokes + 1] = key end,
        new = function(_, fn) watcher = chain(); watcher.fn = fn; return watcher end },
    hotkey = { modal = { new = function() modal = chain(); return modal end }, bind = function() return chain() end },
    webview = { usercontent = { new = function()
        controller = {}; function controller:setCallback(fn) self.callback = fn; return self end
        return controller
    end }, new = function(frame)
        popup = chain(); popup.currentFrame = frame
        function popup:frame(value) if value then self.currentFrame = value; return self end; return self.currentFrame end
        function popup:evaluateJavaScript(script, callback)
            lastState = real.json.decode(assert(script:match("^window.render%((.*)%)$")))
            callback(nil, { code = 0 }); return self
        end
        return popup
    end },
}
local env = setmetatable({ hs = fake,
    os = { getenv = function(key) return envValues[key] end },
    io = { open = function(path, mode)
        if path:match("%.zsh_secrets$") then
            if not secretLines then return nil end
            return { close = function() end, lines = function()
                local i = 0
                return function() i = i + 1; return secretLines[i] end
            end }
        end
        return io.open(path, mode)
    end },
}, { __index = _G })
local M = assert(loadfile(real.configdir .. "/grammar_checker.lua", "t", env))().setup()
local function complete(index, value, provider)
    local response = provider == "openai" and { status = "completed", output = {{ type = "message", content = {{ type = "output_text", text = real.json.encode(value) }} }} }
        or { candidates = {{ finishReason = "STOP", content = { parts = {{ thought = true, text = "not output" }, { text = real.json.encode(value) }} } }} }
    requests[index].callback(200, real.json.encode(response), {})
end
local function action(name, value) controller.callback({ body = { action = name, value = value } }) end
local function tickPoll()
    for _, t in ipairs(timers) do if t.active and t.every then t.fn() end end
end

check(M._test.valid(result("This is a longer test.")), "valid schema")
local invalid = result("x"); invalid.corrections = { malicious = true }
check(not M._test.valid(invalid), "reject object masquerading as array")
invalid = result("x"); invalid.dictionary.translations.sk = false
check(not M._test.valid(invalid), "reject malformed dictionary")
check(M._test.geminiSchema(M._test.schema).additionalProperties == nil, "Gemini schema subset")
local text = M._test.responseText("gemini", { candidates = {{ finishReason = "STOP", content = { parts = {{ thought = true, text = "secret" }, { text = "answer" }} } }} })
check(text == "answer", "filter thinking parts")
check(not M._test.responseText("gemini", { candidates = {{ finishReason = "MAX_TOKENS" }} }), "reject truncation")
check(not M._test.responseText("openai", { status = "incomplete" }), "reject incomplete OpenAI response")

M.run({ clipboard = true })
popup.navigationCallbackArgs[1]("didFinishNavigation")
local policy = popup.policyCallbackArgs[1]
check(policy("navigationAction", popup, { request = { URL = { url = "about:blank" } } }), "allow local NSURL page")
check(not policy("navigationAction", popup, { request = { URL = "https://example.org" } }), "block external navigation")
check(not policy("newWindow", popup, {}), "block new windows")
check(requests[1].headers["x-goog-api-key"] == "test-google" and not requests[1].url:find("key="), "key in header, not URL")
check(requests[1].payload.generationConfig.responseMimeType == "application/json", "structured Gemini output")
complete(1, result("This is a longer test."))
check(pb == "This is a longer test.", "copy corrected text only")
check(lastState.result.corrected_text == pb and M.status == "Ready", "HUD renders successfully")
check(not lastState.canReplace, "clipboard-only result cannot replace")
action("resize", 500)
check(popup.currentFrame.h == 500 and popup.currentFrame.x >= -1428 and popup.currentFrame.y >= 37, "bridge resize and negative-coordinate monitor clamp")
action("mode", "polish")
fake.pasteboard.setContents("User copied something new")
complete(2, result("A polished sentence."))
check(pb == "User copied something new", "in-flight clipboard ownership")
action("mode", "concise")
action("mode", "formal")
complete(4, result("A formal sentence."))
complete(3, result("Stale answer"))
check(pb == "A formal sentence.", "stale responses ignored")
action("previous")
check(lastState.original == "This are a longer test.", "history navigation")
action("restore")
check(pb == "This are a longer test.", "restore original")
action("provider", "openai")
check(requests[5].url == "https://api.openai.com/v1/responses" and requests[5].payload.text.format.strict, "OpenAI structured Responses API")
check(requests[5].payload.store == false, "disable OpenAI response storage")
complete(5, result("This is a longer test."), "openai")
action("translate", "sk")
local input = real.json.decode(requests[6].payload.input)
check(input.operation == "translate" and input.target_language == "sk", "translation operation")
complete(6, result("Toto je dlhší test."), "openai")
action("diff"); check(lastState.view == "clean", "clean/diff toggle")
action("lexicon"); complete(7, result("Ignored lexicon rewrite"), "openai")
check(lastState.result.corrected_text == lastState.original, "lexicon cannot rewrite original")
action("retry"); M.close(); complete(8, result("Dismissed answer"), "openai")
check(M.status == "closed", "dismissed response cannot reopen HUD")

pb, count, selected = "Previous clipboard", count + 1, "This are a longer selection."
M.run(); check(strokes[#strokes] == "c", "auto-copy selection")
fake.pasteboard.setContents(selected); tickPoll()
check(#requests == 9, "copy polling starts request")
popup.navigationCallbackArgs[1]("didFinishNavigation")
complete(9, result("This is a longer selection."), "openai")
check(lastState.canReplace, "current selection can replace")
selected = "Another selection"
M.replace(); check(M.status ~= "closed", "changed selection blocks replacement")
selected = "This are a longer selection."
M.replace(); check(M.status == "closed", "replace dismisses HUD")
for _, t in ipairs(timers) do if t.active and not t.every then t.active = false; t.fn() end end
check(strokes[#strokes] == "v", "verified replace sends paste")

selected, pb = nil, "Fallback clipboard contains a sentence."
M.run(); for _ = 1, 6 do tickPoll() end
check(#requests == 10, "150ms clipboard fallback")
popup.navigationCallbackArgs[1]("didFinishNavigation")
local unchanged = result("should not be used"); unchanged.changed = false
local savedCount = count
complete(10, unchanged, "openai")
check(pb == "Fallback clipboard contains a sentence." and count == savedCount, "unchanged result preserves clipboard formats")
for _ = 1, 12 do action("retry"); complete(#requests, unchanged, "openai") end
check(#M.history == 10, "history bounded to ten")
M.close()
check(modal.exitArgs ~= nil and watcher.stopArgs ~= nil, "modal and outside watcher stop on close")
envValues.GOOGLE_API_KEY, envValues.OPENAI_API_KEY = nil, nil
secretLines = { "export GOOGLE_API_KEY=\"$GEMINI_API_KEY\"", "export GEMINI_API_KEY='from-file'" }
settings["grammarChecker.provider"] = "gemini"
pb = "Schadenfreude"
M.run({ clipboard = true })
check(requests[#requests].headers["x-goog-api-key"] == "from-file", "GUI secrets-file fallback with forward alias")
check(real.json.decode(requests[#requests].payload.contents[1].parts[1].text).operation == "lexicon", "short-input automatic lexicon")
popup.navigationCallbackArgs[1]("didFinishNavigation")
requests[#requests].callback(200, "not JSON", {})
check(M.status == "Error", "malformed response handled")
action("retry")
local timeout
for _, t in ipairs(timers) do if t.active and not t.every then timeout = t end end
timeout.fn()
check(M.status == "Error" and not M.busy, "deadline exits busy state")
complete(#requests, result("Late response"))
check(M.status == "Error", "late timed-out response ignored")
action("retry")
requests[#requests].callback(429, "{}", { ["Retry-After"] = "1" })
check(M.status == "Retrying…", "transient error schedules bounded retry")
local retry
for _, t in ipairs(timers) do if t.active and not t.every then retry = t end end
retry.active = false; retry.fn()
complete(#requests, result("ignored dictionary rewrite"))
check(M.status == "Ready", "retry can complete")
M.run({ clipboard = true })
popup.navigationCallbackArgs[1]("didFinishNavigation")
check(watcher.fn({ location = function() return { x = 99999, y = 99999 } end }) == false and M.status == "closed", "outside click dismisses without swallowing click")
local before = #requests
pb = string.rep("x", 24001)
M.run({ clipboard = true })
check(M.status == "Too long" and #requests == before, "oversized input blocked before upload")
pb = "Another harmless test sentence."
M.run(); pid = 99; tickPoll()
check(M.status == "Focus changed" and #requests == before, "focus change cancels selection capture")
pid = 42
selected, pb = nil, "I heisse Jakub."
M.run(); fake.pasteboard.setContents(""); tickPoll()
check(pb == "I heisse Jakub.", "empty Cmd+C write restores previous clipboard")
check(real.json.decode(requests[#requests].payload.contents[1].parts[1].text).operation == "write", "short sentence routes to grammar check")
M.close()

M.run({ clipboard = true })
modal.exitArgs = nil
appWatcher.fn("Other app", 1, { pid = function() return 99 end, bundleID = function() return "test.other" end })
check(modal.exitArgs ~= nil and M.status ~= "closed", "application switch releases modal while keeping window selectable")
appWatcher.fn("Hammerspoon", 1, { pid = function() return -1 end, bundleID = function() return "org.hammerspoon.Hammerspoon" end })
check(modal.enterArgs ~= nil, "focusing Hammerspoon re-enables modal shortcuts")
M.run({ clipboard = true })
M.shutdown()
check(rawget(popup, "deleteArgs") == nil and rawget(popup, "hideArgs") ~= nil and controller.callback == nil,
    "shutdown detaches callbacks without deleting live WebKit objects")
M.cleanup()
print("Grammar checker: " .. checks .. " isolated regression checks passed")

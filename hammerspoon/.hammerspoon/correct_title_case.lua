local M = { status = "ready", busy = false }
local function frontPID()
    local app = hs.application.frontmostApplication()
    return app and app:pid()
end
function M.run()
    if M.busy then return end
    M.busy = true
    M.status = "copying"
    local originalApp = frontPID()
    local saved = hs.pasteboard.readAllData()
    local count = hs.pasteboard.changeCount()
    local attempts = 0
    local poll
    hs.eventtap.keyStroke({"cmd"}, "c", 0)
    poll = hs.timer.doEvery(0.05, function()
        attempts = attempts + 1
        if frontPID() ~= originalApp then
            poll:stop()
            M.status, M.busy = "focus changed", false
            return
        end
        if hs.pasteboard.changeCount() == count then
            if attempts >= 20 then
                poll:stop()
                M.status, M.busy = "no selection", false
                hs.alert.show("Select text first")
            end
            return
        end
        poll:stop()
        local text = hs.pasteboard.getContents()
        if not text or text == "" then
            M.status, M.busy = "no text", false
            return
        end
        local copiedCount = hs.pasteboard.changeCount()
        M.task = hs.task.new("/opt/homebrew/bin/python3", function(code, output, err)
            M.task = nil
            if code ~= 0 then
                M.status, M.busy = "conversion failed", false
                hs.printf("Title case conversion failed: %s", err)
                return
            end
            if frontPID() ~= originalApp or hs.pasteboard.changeCount() ~= copiedCount then
                M.status, M.busy = "focus or clipboard changed", false
                return
            end
            hs.pasteboard.setContents(output)
            local pastedCount = hs.pasteboard.changeCount()
            hs.eventtap.keyStroke({"cmd"}, "v", 0)
            hs.timer.doAfter(0.3, function()
                if hs.pasteboard.changeCount() == pastedCount then
                    hs.pasteboard.writeAllData(saved)
                end
                M.status, M.busy = "done", false
            end)
        end, { hs.configdir .. "/title_case.py" })
        M.task:setInput(text)
        if not M.task:start() then
            M.status, M.busy = "could not start converter", false
        end
    end)
end
hs.urlevent.bind("correct-title-case", M.run)
return M

hs = hs
hs.loadSpoon("AClock")

-- Clipboard cleaner: removes unwanted line breaks from wrapped terminal text
-- Preserves intentional paragraph breaks (double newlines)
local lastClipboard = ""
local clipboardWatcher = hs.timer.doEvery(0.5, function()
    local current = hs.pasteboard.getContents()
    if current and current ~= lastClipboard then
        lastClipboard = current
        -- Only process if it has newlines but no double-newlines (paragraph breaks)
        if current:match("\n") and not current:match("\n\n") then
            -- Replace single newlines with spaces, collapse multiple spaces
            local cleaned = current:gsub("\n", " "):gsub("  +", " "):gsub("^ ", ""):gsub(" $", "")
            if cleaned ~= current then
                hs.pasteboard.setContents(cleaned)
                lastClipboard = cleaned
            end
        end
    end
end)

hs.hotkey.bind({"cmd", "alt"}, "C", function()
  spoon.AClock:toggleShow()
end)


-- hammerspoon can be your next app launcher!!!!
hs.hotkey.bind({"cmd", "alt"}, "A", function()
	hs.application.launchOrFocus("Arc")
	-- local arc = hs.appfinder.appFromName("Arc")
	-- arc:selectMenuItem({"Help", "Getting Started"})
end)

hs.hotkey.bind({"alt"}, "R", function()
	hs.reload()
end)
hs.alert.show("Config loaded")

-- Chrome: Cmd+Shift+C to copy current URL (Cmd+L then Cmd+C)
hs.hotkey.bind({"cmd", "shift"}, "C", function()
    local app = hs.application.frontmostApplication()
    if app and app:bundleID() == "com.google.Chrome" then
        hs.eventtap.keyStroke({"cmd"}, "L")
        hs.timer.doAfter(0.05, function()
            hs.eventtap.keyStroke({"cmd"}, "C")
        end)
    end
end)

local calendar = hs.loadSpoon("GoMaCal")
if calendar then
    calendar:setCalendarPath('/Users/klaudioz/dotfiles/hammerspoon/calendar-app/calapp')
    calendar:start()
end

-- Rescue AeroSpace floating windows that appear off-screen
-- Only rescues each window once (on creation), won't fight with user interaction
do
    local aeroBin = "/opt/homebrew/bin/aerospace"
    local rescued = {}

    local function rescueNewFloating()
        local out = hs.execute(aeroBin .. " list-windows --monitor all --format '%{window-id}\t%{window-layout}' 2>/dev/null", true)
        if not out or out == "" then return end
        local floating = {}
        for line in out:gmatch("[^\n]+") do
            local wid, layout = line:match("(%d+)%s+(%S+)")
            if layout == "floating" and wid then floating[tonumber(wid)] = true end
        end
        if not next(floating) then return end
        for _, win in ipairs(hs.window.allWindows()) do
            local wid = win:id()
            if floating[wid] and not rescued[wid] then
                local f = win:frame()
                local s = win:screen()
                if s and f and f.w >= 200 and f.h >= 100 then
                    local sf = s:frame()
                    local vw = math.max(0, math.min(f.x + f.w, sf.x + sf.w) - math.max(f.x, sf.x))
                    local vh = math.max(0, math.min(f.y + f.h, sf.y + sf.h) - math.max(f.y, sf.y))
                    if vw < 100 or vh < 100 then win:centerOnScreen() end
                end
                rescued[wid] = true
            end
        end
    end

    local debounce
    local function debouncedRescue()
        if debounce then debounce:stop() end
        debounce = hs.timer.doAfter(0.5, rescueNewFloating)
    end

    _aeroRescueWF = hs.window.filter.new():setOverrideFilter({visible = true})
    _aeroRescueWF:subscribe(
        {hs.window.filter.windowCreated, hs.window.filter.windowVisible},
        debouncedRescue
    )
    _aeroRescueScreenWatcher = hs.screen.watcher.new(function()
        rescued = {}
        hs.timer.doAfter(2, rescueNewFloating)
    end)
    _aeroRescueScreenWatcher:start()
    hs.timer.doAfter(1, rescueNewFloating)
end


















-- local function showNotification(title, message)
--     hs.notify.show(title, "", message)
-- end
--
-- hs.hotkey.bind({"cmd", "alt"}, "P", function()
--   hs.alert(hs.brightness.get())
--   showNotification("Hello", "This is a test notification")
-- end)
--
-- hs.hotkey.bind({"alt"}, "R", function()
--   hs.reload()
-- end)
-- hs.alert.show("Config loaded")
--
--
-- local function start_quicktime_movie()
--   hs.application.launchOrFocus("QuickTime Player")
--   local qt = hs.appfinder.appFromName("QuickTime Player")
--   qt:selectMenuItem({"File", "New Movie Recording"})
-- end
-- local function start_quicktime_screen()
--   hs.application.launchOrFocus("QuickTime Player")
--   local qt = hs.appfinder.appFromName("QuickTime Player")
--   qt:selectMenuItem({"File", "New Screen Recording"})
-- end
--
-- hs.hotkey.bind({"cmd", "alt"}, "m", start_quicktime_movie)
-- hs.hotkey.bind({"cmd", "alt"}, "s", start_quicktime_screen)
--
-- local calendar = hs.loadSpoon("GoMaCal")
-- if calendar then
--     calendar:setCalendarPath('/Users/klaudioz/dotfiles/hammerspoon/calendar-app/calapp')
--     calendar:start()
-- end

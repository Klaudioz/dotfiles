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

-- Cover AeroSpace hidden window slivers at screen corners.
-- AeroSpace hides inactive workspace windows at monitor corners and re-positions
-- them if moved (via kAXMovedNotification). So instead of moving the windows,
-- we draw persistent click-through canvas covers at each screen's corners.
-- Combined with transparent inactive borders, this hides all slivers.
do
    local cornerCovers = {}

    local function refreshCornerCovers()
        -- Destroy old covers
        for _, c in ipairs(cornerCovers) do c:delete() end
        cornerCovers = {}

        for _, screen in ipairs(hs.screen.allScreens()) do
            local sf = screen:frame()
            -- Bottom-right corner cover (where AeroSpace typically hides windows)
            local coverW, coverH = 60, 80
            local c = hs.canvas.new({
                x = sf.x + sf.w - coverW,
                y = sf.y + sf.h - coverH,
                w = coverW, h = coverH
            })
            -- Use desktop wallpaper for seamless blending, fall back to black
            local wallpaperURL = screen:desktopImageURL()
            local img = wallpaperURL and hs.image.imageFromURL(wallpaperURL)
            if img then
                local imgSize = img:size()
                -- Scale to fill screen (like macOS "Fill Screen" mode), crop to corner
                local scale = math.max(sf.w / imgSize.w, sf.h / imgSize.h)
                local scaledW = imgSize.w * scale
                local scaledH = imgSize.h * scale
                -- Offset: center the scaled image on screen, then shift to show the corner
                local imgX = (sf.w - scaledW) / 2 - (sf.w - coverW)
                local imgY = (sf.h - scaledH) / 2 - (sf.h - coverH)
                c:insertElement({
                    type = "image",
                    image = img,
                    frame = {x = imgX, y = imgY, w = scaledW, h = scaledH},
                })
            else
                c:insertElement({
                    type = "rectangle",
                    fillColor = {red = 0, green = 0, blue = 0, alpha = 1},
                    action = "fill",
                })
            end
            c:level(hs.canvas.windowLevels.normal + 1)
            c:clickActivating(false)
            c:canvasMouseEvents(false, false, false, false) -- Click-through
            c:show()
            table.insert(cornerCovers, c)
        end
    end

    -- Refresh on config load
    refreshCornerCovers()

    -- Refresh when screens change (connect/disconnect monitors)
    local screenWatcher = hs.screen.watcher.new(refreshCornerCovers)
    screenWatcher:start()

    -- Keep URL handler for manual refresh
    hs.urlevent.bind("pushHidden", function()
        refreshCornerCovers()
    end)
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

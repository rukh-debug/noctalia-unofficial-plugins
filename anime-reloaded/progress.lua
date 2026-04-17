-- progress.lua — bundled with the AnimeReloaded plugin
-- Writes duration and playback position on exit so the plugin can track
-- episode progress and resume playback.
-- progress_file is passed via --script-opts=progress_file=<path>

local progress_file = mp.get_opt("progress_file") or "/tmp/mpv-anime-reloaded-progress.txt"
local last_pos = 0
local last_dur = 0

mp.observe_property("playback-time", "number", function(_, val)
    if val and val > 0 then last_pos = val end
end)

mp.observe_property("duration", "number", function(_, val)
    if val and val > 0 then last_dur = val end
end)

mp.register_event("shutdown", function()
    local f = io.open(progress_file, "w")
    if f then
        f:write("duration=" .. last_dur .. "\nposition=" .. last_pos .. "\n")
        f:close()
    end
end)

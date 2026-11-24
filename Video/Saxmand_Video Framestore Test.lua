-- Throughput benchmark for the framestore analyser (VP_Analyze).
-- Select a video item in REAPER, then run this from Actions -> Load ReaScript.
--
-- Analysis is what every later comparison stage depends on, so the number that
-- matters is decoded frames per second. For reference, the old per-frame
-- AVAssetImageGenerator path manages roughly 30-100 fps.

local function log(s) reaper.ShowConsoleMsg(s .. "\n") end

local function sourcePath()
    local item = reaper.GetSelectedMediaItem(0, 0)
    if not item then return nil, "Select a video item first." end
    local take = reaper.GetActiveTake(item)
    local src  = take and reaper.GetMediaItemTake_Source(take)
    local path = src  and reaper.GetMediaSourceFileName(src)
    if not path or path == "" then return nil, "Could not read a file path from the selected item." end
    return path
end

local function fileSize(path)
    local f = io.open(path, "rb")
    if not f then return 0 end
    local n = f:seek("end")
    f:close()
    return n or 0
end

if not reaper.VP_Analyze then
    log("[FS Test] Extension missing VP_Analyze — rebuild (extension/build.sh) and restart REAPER.")
    return
end

local path, err = sourcePath()
if not path then log("[FS Test] " .. err) return end

local storePath = path .. ".vpfs"

log("")
log("[FS Test] Source: " .. path)
log("[FS Test] Store:  " .. storePath)
if reaper.VP_StoreFresh(storePath, path) == 1 then
    log(string.format("[FS Test] An up-to-date store already exists (%d frames) — forcing a rebuild to time the decode.",
                      reaper.VP_StoreFrames(storePath)))
end

-- force=1 so we time a real decode pass rather than a cache hit
local job = reaper.VP_Analyze(path, storePath, 1)
if job == 0 then log("[FS Test] VP_Analyze refused the request (bad path?).") return end

-- Job ids count up from 1, so anything large means the return value is being
-- marshalled wrongly rather than the analysis having a problem.
if job ~= math.floor(job) or job < 1 or job > 100000 then
    log(string.format("[FS Test] ABORT: VP_Analyze returned %s, which is not a job id.", tostring(job)))
    log("[FS Test] The extension is stale or miscompiled — rerun extension/build.sh and restart REAPER.")
    return
end

local t0 = reaper.time_precise()
local lastShown = -1

local function poll()
    local state = reaper.VP_AnalyzeState(job)

    if state == 0 then
        local pct = math.floor(reaper.VP_AnalyzeProgress(job) * 100)
        if pct >= lastShown + 10 then
            lastShown = pct - (pct % 10)
            log(string.format("[FS Test]   %d%%", lastShown))
        end
        reaper.defer(poll)
        return
    end

    local elapsed = reaper.time_precise() - t0

    if state == 2 then
        log("[FS Test] FAILED: " .. tostring(reaper.VP_AnalyzeError(job)))
        reaper.VP_AnalyzeRelease(job)
        return
    end

    local frames = reaper.VP_AnalyzeFrames(job)
    local fps    = reaper.VP_StoreFPS(storePath)
    local bytes  = fileSize(storePath)

    log("[FS Test] ---------------------------------------------")
    log(string.format("[FS Test] frames analysed : %d", frames))
    log(string.format("[FS Test] source fps      : %.3f", fps))
    log(string.format("[FS Test] elapsed         : %.2f s", elapsed))
    if elapsed > 0 then
        log(string.format("[FS Test] throughput      : %.0f frames/s  (%.1fx realtime)",
                          frames / elapsed, (fps > 0 and (frames / fps) or 0) / elapsed))
    end
    log(string.format("[FS Test] store size      : %.2f MB  (%.0f bytes/frame)",
                      bytes / 1048576, frames > 0 and bytes / frames or 0))
    if frames > 0 then
        local perHour = (bytes / frames) * (fps > 0 and fps or 25) * 3600
        log(string.format("[FS Test] projected       : %.1f MB per hour of footage", perHour / 1048576))
    end
    log("[FS Test] ---------------------------------------------")

    -- Re-open with force=0 to confirm the freshness check accepts what we just wrote
    local cached = reaper.VP_Analyze(path, storePath, 0)
    if cached ~= 0 then
        log(string.format("[FS Test] cache check     : state=%d frames=%d (1=done means the store was reused)",
                          reaper.VP_AnalyzeState(cached), reaper.VP_AnalyzeFrames(cached)))
        reaper.VP_AnalyzeRelease(cached)
    end

    reaper.VP_AnalyzeRelease(job)
end

log("[FS Test] Analysing...")
poll()

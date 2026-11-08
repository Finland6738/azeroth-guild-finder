-- Mock client, part 2: the controllable clock.
--
-- Imitates: GetTime, GetTimePreciseSec, debugprofilestop, GetServerTime, time, date (and os.time / os.date).
-- Dump files: ../WoW-Addons/docs/api/ (GetServerTime and GetTime are in the dump); `time` and `date` are the Lua
-- functions the client keeps.
--
-- Nothing reads the real clock: time moves only through Mock.Advance(seconds) (see 30_timers.lua), Mock.SetTime and
-- Mock.SetServerTime. In the real client time() is the PC clock and GetServerTime() the realm clock; here both come
-- from the same fake epoch, and dates are always UTC, so tests give the same result on every machine.
local Mock, H = ...
local W = Mock.world

W.clock = W.clock or {
	now = 1000.0,          -- GetTime(): seconds since "the client started"
	epoch = 1767225600,    -- GetServerTime(): 2026-01-01 00:00:00 UTC
}
local clock = W.clock

function GetTime() return clock.now end
function GetTimePreciseSec() return clock.now end
function debugprofilestop() return clock.now * 1000 end
function GetServerTime() return math.floor(clock.epoch) end

-- Moves both clocks by `seconds` without running timers (Mock.Advance does the running).
function Mock.StepClock(seconds)
	clock.now = clock.now + seconds
	clock.epoch = clock.epoch + seconds
end

function Mock.SetTime(now) clock.now = now end
function Mock.SetServerTime(epoch) clock.epoch = epoch end

-- UTC conversion of a date table (days-from-civil), the same default noon as os.time.
local function utcTime(t)
	local y, m, d = t.year, t.month, t.day
	y = y + math.floor((m - 1) / 12)
	m = (m - 1) % 12 + 1
	if m <= 2 then y = y - 1 end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local doy = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	local days = era * 146097 + doe - 719468
	return days * 86400 + (t.hour or 12) * 3600 + (t.min or 0) * 60 + (t.sec or 0)
end

function time(t)
	if t == nil then return math.floor(clock.epoch) end
	return utcTime(t)
end

function date(fmt, t)
	fmt = fmt or "%c"
	if fmt:sub(1, 1) ~= "!" then fmt = "!" .. fmt end
	return H.os.date(fmt, t or math.floor(clock.epoch))
end

os = {
	time = time, date = date,
	clock = function() return clock.now end,
	difftime = function(a, b) return a - (b or 0) end,
}

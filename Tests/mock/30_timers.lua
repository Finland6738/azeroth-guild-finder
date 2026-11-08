-- Mock client, part 4: C_Timer and the time-advancing loop.
--
-- Imitates: C_Timer.After, C_Timer.NewTimer, C_Timer.NewTicker and the OnUpdate script of visible frames.
-- Dump file: ../WoW-Addons/docs/api/ (C_Timer: After, NewTicker, NewTimedSignalMap, NewTimer; the last is not mocked).
--
-- Time stands still until a test calls Mock.Advance(seconds). The loop runs in "frames" of Mock.frameStep seconds
-- (0.1: a 10 FPS client): each frame moves the clocks, fires due timers (earliest first, then in creation order) and
-- runs OnUpdate(elapsed) of visible frames, which is what ChatThrottleLib needs to release queued messages.
-- A timer created inside a callback fires on a later frame, like in the client (After(0) is "next frame").
local Mock, H = ...
local W = Mock.world

Mock.frameStep = 0.1

local timers, seq, frameNumber = {}, 0, 0

local function newTimer(seconds, callback, iterations)
	if type(seconds) ~= "number" then error("C_Timer: bad argument #1 (number expected)", 3) end
	if type(callback) ~= "function" then error("C_Timer: bad argument #2 (function expected)", 3) end
	seq = seq + 1
	local timer = {
		_interval = math.max(seconds, 0), _due = W.clock.now + math.max(seconds, 0), _callback = callback,
		_left = iterations, _seq = seq, _born = frameNumber, _cancelled = false,
	}
	function timer:Cancel() self._cancelled = true end
	function timer:IsCancelled() return self._cancelled end
	timers[#timers + 1] = timer
	return timer
end

C_Timer = {}

function C_Timer.After(seconds, callback)
	local t = newTimer(seconds, callback, 1)
	t._plain = true
end

function C_Timer.NewTimer(seconds, callback)
	return newTimer(seconds, callback, 1)
end

function C_Timer.NewTicker(seconds, callback, iterations)
	return newTimer(seconds, callback, iterations)   -- iterations == nil: until cancelled
end

-- How many timers are waiting (cancelled ones excluded).
function Mock.PendingTimers()
	local n = 0
	for _, t in ipairs(timers) do if not t._cancelled then n = n + 1 end end
	return n
end

local function runDueTimers()
	while true do
		local pick
		for _, t in ipairs(timers) do
			if not t._cancelled and t._born < frameNumber and t._due <= W.clock.now + 1e-9 then
				if not pick or t._due < pick._due or (t._due == pick._due and t._seq < pick._seq) then pick = t end
			end
		end
		if not pick then break end
		if pick._left then
			pick._left = pick._left - 1
			if pick._left <= 0 then pick._cancelled = true end
		end
		if not pick._cancelled then
			pick._due = pick._due + math.max(pick._interval, 0.001)
		end
		if pick._plain then Mock.safecall(pick._callback) else Mock.safecall(pick._callback, pick) end
	end
	for i = #timers, 1, -1 do
		if timers[i]._cancelled then table.remove(timers, i) end
	end
end

-- Moves time forward by `seconds`, frame by frame. `step` overrides Mock.frameStep for this call.
function Mock.Advance(seconds, step)
	step = step or Mock.frameStep
	local target = W.clock.now + seconds
	while W.clock.now < target - 1e-9 do
		local dt = math.min(step, target - W.clock.now)
		frameNumber = frameNumber + 1
		Mock.StepClock(dt)
		runDueTimers()
		Mock.RunOnUpdate(dt)
	end
end

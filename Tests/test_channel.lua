-- Channel and /gf debug ping on one client (M1.8): joining the permanent channel, retries, hiding, moving, filters, the
-- channel limit, failures and the ping command. Several clients are in test_sim.lua.
local NAME = "AzGuildFinder"
local function Ch() return AzerothGuildFinder.Channel end
local function Bus() return AzerothGuildFinder.Bus end
local function Tr() return AzerothGuildFinder.Transport end

local function listen(event)
	local seen = {}
	Bus():On(event, function(...) seen[#seen + 1] = { ... } end)
	return seen
end

local function output() return table.concat(Mock.PlainOutput(), "\n") end

-- Channels that exist before the addon joins its own (General, Trade, ...), `n` of them with ids 1..n.
local function otherChannels(n)
	for i = 1, n do Mock.chat.AddChannel("Other" .. i) end
end

describe("Joining", function()
	it("waits for the start delay, then joins with JoinChannelByName and says so on the Bus", function()
		local ready = listen("CHANNEL_READY")
		Mock.Advance(4)
		eq(GetChannelName(NAME), 0, "not before the client had time to join its own channels")
		falsy(Ch():IsReady())
		Mock.Advance(2)
		local id = GetChannelName(NAME)
		truthy(id > 0)
		truthy(Ch():IsReady())
		eq(#ready, 1)
		eq(ready[1][1], id)
		eq(Ch():Id(), id)
	end)

	it("gives the channel number to the Transport", function()
		Mock.Advance(6)
		eq(Tr().channelId(), GetChannelName(NAME))
	end)

	it("never uses a temporary channel: only JoinChannelByName is called", function()
		local joined = {}
		local original = JoinChannelByName
		JoinChannelByName = function(name, ...) joined[#joined + 1] = name return original(name, ...) end
		JoinTemporaryChannel = function() fail("a temporary channel was requested") end
		Mock.Advance(10)
		deepEq(joined, { NAME })
	end)

	it("uses the channel for CHANNEL messages once it is joined", function()
		Mock.Advance(7)
		Tr():Send("CHANNEL", { t = "DEL", k = "g", rev = 1 })
		Mock.Advance(3)
		local sent = Mock.chat.SentWithPrefix("AzGF")
		eq(#sent, 1)
		eq(sent[1].chatType, "CHANNEL")
		eq(tonumber(sent[1].target), GetChannelName(NAME))
	end)

	it("does nothing twice when the channel is already joined (after /reload)", function()
		Mock.Advance(7)
		local id = GetChannelName(NAME)
		Mock.Reload()
		local ready = listen("CHANNEL_READY")
		Mock.Advance(7)
		eq(GetChannelName(NAME), id)
		eq(#ready, 1)
		local count = 0
		for _ in pairs(Mock.chat.channels) do count = count + 1 end
		eq(count, 1, "joined once, not twice")
	end)

	it("takes over a channel the player joined by hand", function()
		Ch():Reset()
		local ready = listen("CHANNEL_READY")
		JoinChannelByName(NAME)
		Mock.Advance(1)
		eq(#ready, 1)
		truthy(Ch():IsReady())
	end)
end)

describe("Retry and failures", function()
	it("tries again every 60 seconds while the client does not answer, and reports a timeout once", function()
		Mock.chat.joinIgnored = true
		local failed = listen("CHANNEL_FAILED")
		Mock.Advance(5.5)
		eq(Ch().state.attempts, 1)
		Mock.Advance(5)
		eq(#failed, 1)
		eq(failed[1][1], "timeout")
		Mock.Advance(55)                  -- 60 s after the first attempt
		eq(Ch().state.attempts, 2)
		Mock.Advance(60)
		eq(Ch().state.attempts, 3)
		eq(#failed, 1, "the same reason is not reported again")
		eq(Ch():IsReady(), false)
	end)

	it("joins on the next attempt once the client lets it, and the failure state is forgotten", function()
		Mock.chat.joinIgnored = true
		local ready = listen("CHANNEL_READY")
		Mock.Advance(20)
		eq(#ready, 0)
		Mock.chat.joinIgnored = false
		Mock.Advance(50)
		eq(#ready, 1)
		eq(Ch().state.failures, 0)
		eq(Ch().state.lastReason, nil)
	end)

	it("reports a refusal notice at once and keeps trying", function()
		Mock.chat.joinNotice = "THROTTLED"
		local failed = listen("CHANNEL_FAILED")
		Mock.Advance(5.5)
		eq(#failed, 1, "no need to wait for the timeout")
		eq(failed[1][1], "throttled")
		Mock.chat.joinNotice = "BANNED"
		Mock.Advance(60)
		eq(#failed, 2)
		eq(failed[2][1], "banned")
	end)

	it("a notice about another channel changes nothing", function()
		Mock.chat.joinIgnored = true
		local failed = listen("CHANNEL_FAILED")
		Mock.Advance(5.5)
		Mock.chat.Notice("THROTTLED", 0, "General")
		Mock.Advance(1)
		eq(#failed, 0)
	end)

	it("without a join function it reports 'unavailable' and does not try again", function()
		JoinChannelByName = nil
		local failed = listen("CHANNEL_FAILED")
		Mock.Advance(300)
		eq(#failed, 1)
		eq(failed[1][1], "unavailable")
		eq(Ch().state.attempts, 1)
	end)

	it("joins again after the player left the channel", function()
		local ready, failed = listen("CHANNEL_READY"), listen("CHANNEL_FAILED")
		Mock.Advance(7)
		eq(#ready, 1)
		LeaveChannelByName(NAME)
		Mock.Advance(1)
		eq(#failed, 1)
		eq(failed[1][1], "left")
		falsy(Ch():IsReady())
		Mock.Advance(60)
		eq(#ready, 2)
		truthy(Ch():IsReady())
	end)

	it("leaves listen-only mode when the channel is joined again", function()
		Mock.Advance(7)
		Mock.chat.channelsRejectAddon = true
		Tr():Send("CHANNEL", { t = "DEL", k = "g", rev = 1 })
		Mock.Advance(2)
		truthy(Tr():IsListenOnly())
		LeaveChannelByName(NAME)
		Mock.chat.channelsRejectAddon = false
		Mock.Advance(65)
		truthy(Ch():IsReady())
		falsy(Tr():IsListenOnly())
	end)
end)

describe("The channel limit", function()
	it("does not ask the client to join and reports 'limit' once, with a message", function()
		otherChannels(10)
		local failed = listen("CHANNEL_FAILED")
		Mock.Advance(5.5)
		eq(#failed, 1)
		eq(failed[1][1], "limit")
		eq(GetChannelName(NAME), 0)
		contains(output(), "maximum of 10 chat channels")
		Mock.ClearOutput()
		Mock.Advance(130)
		eq(Ch().state.attempts, 3)
		eq(#failed, 1)
		eq(#Mock.PlainOutput(), 0, "the warning is shown once")
	end)

	it("joins by itself when a slot becomes free", function()
		otherChannels(10)
		local ready = listen("CHANNEL_READY")
		Mock.Advance(10)
		eq(#ready, 0)
		LeaveChannelByName("Other3")
		Mock.Advance(60)
		eq(#ready, 1)
		truthy(Ch():IsReady())
	end)

	it("detects the limit when the client refuses without a notice", function()
		otherChannels(9)
		Mock.chat.maxChannels = 9   -- the client has a lower limit than the addon assumes
		local failed = listen("CHANNEL_FAILED")
		Mock.Advance(11)
		eq(#failed, 1)
		eq(failed[1][1], "timeout")
	end)
end)

describe("Hiding and moving", function()
	it("removes the channel from every chat window", function()
		Mock.Advance(0.1)
		-- the client shows a new channel in the first window; the addon takes it out
		Mock.Advance(6)
		truthy(Ch():IsReady())
		falsy(Mock.chat.Showing(NAME), "hidden from every window")
	end)

	it("hides it again when the client adds it back after the join notice", function()
		Mock.Advance(6)
		ChatFrame_AddChannel(ChatFrame3, NAME)
		truthy(Mock.chat.Showing(NAME, 3))
		Ch():OnEnteringWorld()   -- loading screen
		falsy(Mock.chat.Showing(NAME))
		ChatFrame_AddChannel(ChatFrame2, NAME)
		Ch():Reset()
		JoinChannelByName(NAME)  -- already there: the module takes it over and hides it
		Mock.Advance(6)
		falsy(Mock.chat.Showing(NAME))
	end)

	it("leaves the other channels where they are", function()
		otherChannels(2)
		Mock.Advance(6)
		truthy(Mock.chat.Showing("Other1"))
		truthy(Mock.chat.Showing("Other2"))
	end)

	it("moves the channel behind the others so /1 stays General", function()
		Mock.chat.AddChannel("General")      -- 1
		Mock.chat.AddChannel("Trade")        -- 2
		Mock.chat.channels[4] = { name = "Custom" }   -- the addon's channel will take number 3
		Mock.Advance(6)
		eq(GetChannelName(NAME), 4)
		eq(GetChannelName("Custom"), 3)
		eq(GetChannelName("General"), 1)
		eq(Tr().channelId(), 4, "the transport follows the move")
	end)

	it("does not move in combat and finishes when combat ends", function()
		Mock.chat.AddChannel("General")
		Mock.chat.channels[3] = { name = "Custom" }
		Mock.world.inCombat = true
		Mock.Advance(6)
		eq(GetChannelName(NAME), 2, "joined but not moved")
		truthy(Ch().state.pendingMove)
		Mock.world.inCombat = false
		Mock.Fire("PLAYER_REGEN_ENABLED")
		eq(GetChannelName(NAME), 3)
		eq(GetChannelName("Custom"), 2)
		falsy(Ch().state.pendingMove)
	end)

	it("still works when the chat window and swap functions are missing", function()
		ChatFrame_RemoveChannel, ChatFrame_AddMessageEventFilter, GetChannelList = nil, nil, nil
		C_ChatInfo.SwapChatChannelsByChannelIndex = nil
		Mock.Advance(6)
		truthy(Ch():IsReady())
		eq(#Mock.errors, 0)
	end)
end)

describe("Notice filters", function()
	it("hides the join notice and every other line of the channel", function()
		Mock.Advance(6)
		eq(#Mock.chat.displayed, 0, "the join notice never reached a window")
		truthy(Ch().state.filtered >= 1)
		-- the client shows the channel in a window again, and someone talks in it
		ChatFrame_AddChannel(ChatFrame1, NAME)
		local id = GetChannelName(NAME)
		for _, event in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE", "CHAT_MSG_CHANNEL_NOTICE_USER" }) do
			Mock.chat.DeliverChannelEvent(event, "hello", "Someone", "", id .. ". " .. NAME, "", 0, 0, id, NAME, 0, 0)
		end
		eq(#Mock.chat.displayed, 0)
	end)

	it("would show the join notice without the filter (the mock really displays it)", function()
		for event in pairs(Mock.chat.filters) do Mock.chat.filters[event] = {} end
		Mock.Advance(6)
		eq(#Mock.chat.displayed, 1)
		eq(Mock.chat.displayed[1].event, "CHAT_MSG_CHANNEL_NOTICE")
	end)

	it("lets the other channels through", function()
		otherChannels(1)
		Mock.Advance(6)
		Mock.chat.DeliverChannelEvent("CHAT_MSG_CHANNEL", "hello", "Someone", "", "1. Other1", "", 0, 0, 1, "Other1", 0, 0)
		Mock.chat.Notice("YOU_JOINED", 1, "Other1")
		eq(#Mock.chat.displayed, 2)
	end)

	it("matches the name without regard to case", function()
		eq(Ch().Filter(nil, nil, "x", "s", "", "3. azguildfinder", "", 0, 0, 3, "azguildfinder"), true)
		eq(Ch().Filter(nil, nil, "x", "s", "", "3. General", "", 0, 0, 3, "General"), false)
		eq(Ch().Filter(nil, nil), false)
	end)
end)

describe("/gf debug and /gf debug ping", function()
	it("/gf debug has a Channel section without names", function()
		Mock.Advance(6)
		Mock.Slash("/gf debug")
		local text = output()
		contains(text, "Channel: AzGuildFinder (number 1), ready")
		contains(text, "Ping: sent 0")
	end)

	it("/gf debug ping before the channel is joined says so", function()
		Mock.chat.joinIgnored = true
		Mock.Slash("/gf debug ping")
		contains(output(), "channel is not joined yet")
	end)

	it("a lone client hears nobody and says so after the wait", function()
		Mock.Advance(10)
		Mock.Slash("/gf debug ping")
		contains(output(), "Ping sent")
		Mock.Advance(7)
		contains(output(), "No peer answered within 5 seconds")
		eq(AzerothGuildFinder.Ping.state.last.answers, 0)
	end)

	it("allows one ping at a time and one every ten seconds", function()
		Mock.Advance(10)
		Mock.Slash("/gf debug ping")
		Mock.Advance(1)
		Mock.Slash("/gf debug ping")
		contains(output(), "already running")
		Mock.Advance(6)   -- the first one is done, but only 7 s have passed
		Mock.Slash("/gf debug ping")
		contains(output(), "one ping every 10 seconds")
		Mock.Advance(4)
		Mock.ClearOutput()
		Mock.Slash("/gf debug ping")
		contains(output(), "Ping sent")
	end)

	it("counts each answering peer once, ignores other nonces and PONGs that did not come by whisper", function()
		Mock.Advance(10)
		Mock.Slash("/gf debug ping")
		Mock.Advance(1)
		local nonce = AzerothGuildFinder.Ping.state.pending.nonce
		local function pong(n, sender, dist) Bus():Emit("NET_MESSAGE", { t = "PONG", nonce = n, v = 1 }, sender, dist or "WHISPER") end
		pong(nonce, "Alpha-TestRealm")
		pong(nonce, "Alpha-TestRealm")             -- the same peer again
		pong(nonce, "Beta-TestRealm")
		pong(nonce + 1, "Gamma-TestRealm")         -- somebody else's ping
		pong(nonce, "Delta-TestRealm", "CHANNEL")  -- a PONG is a whisper
		Mock.Advance(6)
		local last = AzerothGuildFinder.Ping.state.last
		eq(last.answers, 2)
		matches(output(), "2 peer%(s%) answered%. Round trip: shortest %d+ ms, average %d+ ms, longest %d+ ms%.")
		falsy(output():find("Alpha", 1, true), "no names in the output")
		falsy(output():find("Beta", 1, true))
	end)

	it("answers a PING by whisper to its sender, but not its own and not more than one per five seconds", function()
		Mock.Advance(10)
		local function ping(n, sender) Bus():Emit("NET_MESSAGE", { t = "PING", nonce = n, v = 1 }, sender, "CHANNEL") end
		local function whispers() return #Mock.chat.SentWithPrefix("AzGF") end
		ping(11, "Testchar-TestRealm")   -- the echo of our own message (the player is Testchar)
		Mock.Advance(2)
		eq(whispers(), 0)
		ping(12, "Other-TestRealm")
		ping(13, "Third-TestRealm")      -- too soon
		Mock.Advance(2)
		eq(whispers(), 1)
		local sent = Mock.chat.SentWithPrefix("AzGF")[1]
		eq(sent.chatType, "WHISPER")
		eq(sent.target, "Other-TestRealm")
		eq(AzerothGuildFinder.Ping.state.ignored, 1)
		Mock.Advance(5)
		ping(14, "Third-TestRealm")
		Mock.Advance(2)
		eq(whispers(), 2)
	end)

	it("does not answer a PING that arrives by whisper", function()
		Mock.Advance(10)
		Bus():Emit("NET_MESSAGE", { t = "PING", nonce = 5, v = 1 }, "Other-TestRealm", "WHISPER")
		Mock.Advance(2)
		eq(#Mock.chat.SentWithPrefix("AzGF"), 0)
	end)

	it("reports a ping the transport could not send", function()
		Mock.Advance(10)
		Mock.chat.channelsRejectAddon = true
		Mock.Slash("/gf debug ping")
		Mock.Advance(3)
		contains(output(), "could not be sent (InvalidChannel)")
		contains(AzerothGuildFinder.Ping.state.last.error, "InvalidChannel")
	end)
end)

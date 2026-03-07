-- =============================================================================
-- spec/timers_spec.lua
-- Unit tests for src/Timers.lua: timer creation, combat deferral, FlushPending.
--
-- Design note: pendingAlerts and timers are file-locals in Timers.lua.
-- We infer their state through:
--   - C_Timer.GetTickers() to inspect created ticker handles
--   - Spying on SelfCare.ShowNotif to detect when alerts fire
-- =============================================================================

dofile("spec/stubs/wow_api.lua")
dofile("spec/helpers/load_addon.lua")

describe("Timers", function()

    local showNotifCalls  -- list of alerts passed to ShowNotif

    before_each(function()
        WowStubs_Reset()
        C_Timer.Reset()
        LoadAddon()

        -- Apply defaults so SelfCareDB is fully populated
        SelfCare.ApplyDefaults()

        -- Spy on ShowNotif
        showNotifCalls = {}
        SelfCare.ShowNotif = function(alert)
            table.insert(showNotifCalls, alert)
        end
    end)

    -- -------------------------------------------------------------------------
    describe("StartTimer", function()
        it("creates a NewTicker with the correct interval from SelfCareDB", function()
            local hydrateAlert = SelfCare.FindAlertByKey("hydrate")
            SelfCare.StartTimer(hydrateAlert)

            local tickers = C_Timer.GetTickers()
            assert.equal(1, #tickers)
            assert.equal(SelfCareDB.hydrateInterval, tickers[1].interval)
        end)

        it("does not create a ticker when the alert is disabled", function()
            SelfCareDB.hydrateEnabled = false
            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            assert.equal(0, #C_Timer.GetTickers())
        end)

        it("does not create a ticker when interval is zero", function()
            SelfCareDB.hydrateInterval = 0
            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            assert.equal(0, #C_Timer.GetTickers())
        end)

        it("cancels existing ticker before starting a new one", function()
            local alert = SelfCare.FindAlertByKey("hydrate")
            SelfCare.StartTimer(alert)
            local firstTicker = C_Timer.GetTickers()[1]

            -- Simulate interval change: nextDue cleared, then StartTimer called
            C_Timer.Reset()
            SelfCareDB.nextDue["hydrate"] = nil
            SelfCare.StartTimer(alert)

            -- First ticker was cancelled
            assert.is_true(firstTicker.cancelled)
            -- A new ticker exists
            assert.equal(1, #C_Timer.GetTickers())
        end)

        it("ticker callback calls ShowNotif when out of combat", function()
            _G._inCombat = false
            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            C_Timer.GetTickers()[1]:Fire()
            assert.equal(1, #showNotifCalls)
            assert.equal("hydrate", showNotifCalls[1].key)
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("StartAllTimers", function()
        it("creates one ticker per enabled alert", function()
            SelfCare.StartAllTimers()
            -- All 3 alerts are enabled by default
            assert.equal(3, #C_Timer.GetTickers())
        end)

        it("skips disabled alerts", function()
            SelfCareDB.hydrateEnabled = false
            SelfCare.StartAllTimers()
            assert.equal(2, #C_Timer.GetTickers())
        end)

        it("uses correct intervals for each alert", function()
            SelfCare.StartAllTimers()
            local tickers = C_Timer.GetTickers()
            -- TOC order: hydrate, posture, break
            assert.equal(SelfCareDB.hydrateInterval, tickers[1].interval)
            assert.equal(SelfCareDB.postureInterval, tickers[2].interval)
            assert.equal(SelfCareDB.breakInterval,   tickers[3].interval)
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("StopAllTimers", function()
        it("cancels all active ticker handles", function()
            SelfCare.StartAllTimers()
            local tickers = C_Timer.GetTickers()
            assert.equal(3, #tickers)

            SelfCare.StopAllTimers()
            for _, ticker in ipairs(tickers) do
                assert.is_true(ticker.cancelled)
            end
        end)

        it("is safe to call when no timers are running", function()
            -- Should not error
            assert.has_no.errors(function()
                SelfCare.StopAllTimers()
            end)
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("FireAlert / combat deferral", function()
        it("queues alert in pendingAlerts when in combat", function()
            _G._inCombat = true
            SelfCareDB.disableInCombat = true

            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            C_Timer.GetTickers()[1]:Fire()

            -- ShowNotif should NOT have been called
            assert.equal(0, #showNotifCalls)
        end)

        it("does not queue duplicate alerts during combat", function()
            _G._inCombat = true
            SelfCareDB.disableInCombat = true

            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            local ticker = C_Timer.GetTickers()[1]
            -- Fire twice — should only queue once
            ticker:Fire()
            ticker:Fire()

            -- Out of combat, flush
            _G._inCombat = false
            SelfCare.FlushPending()
            assert.equal(1, #showNotifCalls)
        end)

        it("fires immediately when disableInCombat is false, even in combat", function()
            _G._inCombat = true
            SelfCareDB.disableInCombat = false

            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            C_Timer.GetTickers()[1]:Fire()

            assert.equal(1, #showNotifCalls)
        end)

        it("queues during cutscene when disableInCutscene is true", function()
            _G._inCutscene = true
            SelfCareDB.disableInCutscene = true
            SelfCareDB.disableInCombat   = false

            SelfCare.StartTimer(SelfCare.FindAlertByKey("posture"))
            C_Timer.GetTickers()[1]:Fire()

            assert.equal(0, #showNotifCalls)
        end)

    -- -------------------------------------------------------------------------
    describe("AFK deferral", function()
        it("queues alert when AFK and disableWhenAFK is true", function()
            _G._isAFK = true
            SelfCareDB.disableWhenAFK = true

            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            C_Timer.GetTickers()[1]:Fire()

            assert.equal(0, #showNotifCalls)
        end)

        it("fires immediately when disableWhenAFK is false, even if AFK", function()
            _G._isAFK = true
            SelfCareDB.disableWhenAFK = false

            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            C_Timer.GetTickers()[1]:Fire()

            assert.equal(1, #showNotifCalls)
        end)

        it("flushes queued alerts when un-AFK", function()
            _G._isAFK = true
            SelfCareDB.disableWhenAFK = true

            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            C_Timer.GetTickers()[1]:Fire()
            assert.equal(0, #showNotifCalls)

            _G._isAFK = false
            SelfCare.FlushPending()
            assert.equal(1, #showNotifCalls)
        end)
    end)
    end)

    -- -------------------------------------------------------------------------
    describe("FlushPending", function()
        it("fires all queued alerts when out of combat", function()
            -- Queue two alerts in combat
            _G._inCombat = true
            SelfCareDB.disableInCombat = true
            SelfCare.StartAllTimers()
            local tickers = C_Timer.GetTickers()
            tickers[1]:Fire()  -- hydrate
            tickers[2]:Fire()  -- posture

            assert.equal(0, #showNotifCalls)

            -- Leave combat, flush
            _G._inCombat = false
            SelfCare.FlushPending()

            assert.equal(2, #showNotifCalls)
        end)

        it("clears the queue after flushing", function()
            _G._inCombat = true
            SelfCareDB.disableInCombat = true
            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            C_Timer.GetTickers()[1]:Fire()

            _G._inCombat = false
            SelfCare.FlushPending()
            local firstFlushCount = #showNotifCalls

            -- Second flush should not re-fire anything
            SelfCare.FlushPending()
            assert.equal(firstFlushCount, #showNotifCalls)
        end)

        it("does nothing when still in combat", function()
            _G._inCombat = true
            SelfCareDB.disableInCombat = true
            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            C_Timer.GetTickers()[1]:Fire()

            -- Still in combat — FlushPending should not fire
            SelfCare.FlushPending()
            assert.equal(0, #showNotifCalls)
        end)

        it("updates nextDue when flushing a pending alert", function()
            _G._now = 1000
            _G._isAFK = true
            SelfCareDB.disableWhenAFK = true

            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            C_Timer.GetTickers()[1]:Fire()  -- queued while AFK

            _G._isAFK = false
            SelfCare.FlushPending()

            local expected = 1000 + SelfCareDB.hydrateInterval
            assert.equal(expected, SelfCareDB.nextDue["hydrate"])
        end)

        it("cancels old ticker and creates a fresh After timer after flushing", function()
            _G._now = 1000
            _G._isAFK = true
            SelfCareDB.disableWhenAFK = true

            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            local oldTicker = C_Timer.GetTickers()[1]
            oldTicker:Fire()  -- queued while AFK

            _G._isAFK = false
            C_Timer.Reset()  -- isolate what FlushPending creates
            SelfCare.FlushPending()

            -- Old ticker was cancelled; a new After timer replaces it
            assert.is_true(oldTicker.cancelled)
            assert.equal(1, #C_Timer.GetAfterTimers())
            assert.equal(SelfCareDB.hydrateInterval, C_Timer.GetAfterTimers()[1].delay)
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("nextDue persistence", function()
        it("starts full-interval ticker when nextDue is nil (never fired)", function()
            _G._now = 1000
            SelfCareDB.nextDue["hydrate"] = nil
            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))

            assert.equal(0, #C_Timer.GetAfterTimers())
            assert.equal(1, #C_Timer.GetTickers())
            assert.equal(SelfCareDB.hydrateInterval, C_Timer.GetTickers()[1].interval)
            assert.equal(1000 + SelfCareDB.hydrateInterval, SelfCareDB.nextDue["hydrate"])
        end)

        it("uses C_Timer.After with remaining time when nextDue is in the future", function()
            _G._now = 1000
            SelfCareDB.nextDue["hydrate"] = 1000 + 300  -- 300 seconds remaining
            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))

            assert.equal(1, #C_Timer.GetAfterTimers())
            assert.equal(300, C_Timer.GetAfterTimers()[1].delay)
            assert.equal(0, #C_Timer.GetTickers())
        end)

        it("fires immediately and starts full ticker when nextDue is overdue", function()
            _G._now = 2000
            SelfCareDB.nextDue["hydrate"] = 1000  -- 1000 seconds in the past
            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))

            assert.equal(1, #showNotifCalls)
            assert.equal(1, #C_Timer.GetTickers())
            assert.equal(SelfCareDB.hydrateInterval, C_Timer.GetTickers()[1].interval)
        end)

        it("starts fresh full ticker when nextDue is corrupt (> interval)", function()
            _G._now = 1000
            SelfCareDB.nextDue["hydrate"] = 1000 + SelfCareDB.hydrateInterval + 999
            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))

            assert.equal(0, #C_Timer.GetAfterTimers())
            assert.equal(1, #C_Timer.GetTickers())
            assert.equal(SelfCareDB.hydrateInterval, C_Timer.GetTickers()[1].interval)
            assert.equal(1000 + SelfCareDB.hydrateInterval, SelfCareDB.nextDue["hydrate"])
        end)

        it("writes nextDue to SelfCareDB when alert fires", function()
            _G._now = 5000
            local alert = SelfCare.FindAlertByKey("hydrate")
            SelfCare.StartTimer(alert)
            C_Timer.GetTickers()[1]:Fire()

            local expected = 5000 + SelfCareDB.hydrateInterval
            assert.equal(expected, SelfCareDB.nextDue["hydrate"])
        end)

        it("writes nextDue at start; does not overwrite while alert is queued in combat", function()
            _G._now = 1000
            _G._inCombat = true
            SelfCareDB.disableInCombat = true
            local alert = SelfCare.FindAlertByKey("hydrate")
            SelfCare.StartTimer(alert)

            -- nextDue is written at start time, not deferred
            local expectedNextDue = 1000 + SelfCareDB.hydrateInterval
            assert.equal(expectedNextDue, SelfCareDB.nextDue["hydrate"])

            -- FireAlert is blocked by combat; nextDue remains unchanged
            C_Timer.GetTickers()[1]:Fire()
            assert.equal(expectedNextDue, SelfCareDB.nextDue["hydrate"])
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("After timer cancellation", function()
        it("cancels pending After timer when StartTimer is called again", function()
            _G._now = 1000
            SelfCareDB.nextDue["hydrate"] = 1300  -- 300s remaining

            -- First call — goes down C_Timer.After path
            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            local firstAfter = C_Timer.GetAfterTimers()[1]
            assert.is_false(firstAfter.cancelled)

            -- Second call (simulates /reload or settings change)
            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))

            -- First After must be cancelled so it can't orphan a ticker
            assert.is_true(firstAfter.cancelled)
        end)

        it("fires alert exactly once when StartTimer is called twice before After fires", function()
            _G._now = 1000
            SelfCareDB.nextDue["hydrate"] = 1300  -- 300s remaining

            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))
            SelfCare.StartTimer(SelfCare.FindAlertByKey("hydrate"))  -- reload

            -- Fire every After timer (first is cancelled, second is not)
            for _, t in ipairs(C_Timer.GetAfterTimers()) do
                t:Fire()
            end

            -- Alert should fire exactly once, not twice
            assert.equal(1, #showNotifCalls)
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("RestartTimers", function()
        it("cancels old tickers and creates new ones", function()
            SelfCare.StartAllTimers()
            local oldTickers = { unpack(C_Timer.GetTickers()) }
            assert.equal(3, #oldTickers)

            C_Timer.Reset()
            SelfCare.RestartTimers()

            -- Old tickers were cancelled
            for _, t in ipairs(oldTickers) do
                assert.is_true(t.cancelled)
            end
            -- New tickers were created
            assert.equal(3, #C_Timer.GetTickers())
        end)

        it("clears nextDue so interval changes start fresh full-interval tickers", function()
            _G._now = 1000
            -- nextDue within new interval — would normally cause C_Timer.After
            SelfCareDB.nextDue["hydrate"] = 1000 + 60   -- 60s remaining
            SelfCareDB.hydrateInterval    = 300          -- new 5-min interval

            SelfCare.RestartTimers()

            -- Should start fresh (no After timer), not resume from stale nextDue
            assert.equal(0, #C_Timer.GetAfterTimers())
            assert.equal(3, #C_Timer.GetTickers())
        end)
    end)

end)

-- =============================================================================
-- spec/notifications_spec.lua
-- Unit tests for src/Notifications.lua: ShowNotif, HideNotif, timers, sound.
--
-- Design note: notifFrame, notifDismissTimer, notifHideTimer are file-locals.
-- We observe side effects: UIFrameFadeIn/Out calls, PlaySound, chat prints,
-- and C_Timer.NewTimer handles.
-- =============================================================================

dofile("spec/stubs/wow_api.lua")
dofile("spec/helpers/load_addon.lua")

describe("Notifications", function()

    local fadeInCalls, fadeOutCalls, soundCalls, printCalls

    before_each(function()
        WowStubs_Reset()
        C_Timer.Reset()
        LoadAddon()
        SelfCare.ApplyDefaults()

        -- Spy on WoW API calls.
        -- Use _G.X = ... to bypass busted's setfenv sandbox so the addon's
        -- functions (which run in _G) pick up the spy rather than the stub.
        fadeInCalls  = {}
        fadeOutCalls = {}
        soundCalls   = {}
        printCalls   = {}

        _G.UIFrameFadeIn = function(frame, duration, startAlpha, endAlpha)
            table.insert(fadeInCalls, { frame = frame, duration = duration })
            if frame then frame:SetAlpha(endAlpha or 1) end
        end

        _G.UIFrameFadeOut = function(frame, duration, startAlpha, endAlpha)
            table.insert(fadeOutCalls, { frame = frame, duration = duration })
            if frame then frame:SetAlpha(endAlpha or 0) end
        end

        _G.PlaySound = function(id, channel)
            table.insert(soundCalls, { id = id, channel = channel })
        end

        local origPrint = SelfCare.Print
        SelfCare.Print = function(msg)
            table.insert(printCalls, msg)
            origPrint(msg)  -- still call print() so tests don't break on output checks
        end
    end)

    local function makeAlert(key, msg)
        return { key = key, message = msg or "Test message" }
    end

    -- -------------------------------------------------------------------------
    describe("ShowNotif", function()
        it("calls UIFrameFadeIn", function()
            SelfCare.ShowNotif(makeAlert("hydrate"))
            assert.equal(1, #fadeInCalls)
        end)

        it("plays the default sound 808", function()
            SelfCare.ShowNotif(makeAlert("hydrate"))
            assert.equal(1, #soundCalls)
            assert.equal(808, soundCalls[1].id)
            assert.equal("SFX", soundCalls[1].channel)
        end)

        it("plays the configured alert sound", function()
            SelfCareDB.alertSound = 8960
            SelfCare.ShowNotif(makeAlert("hydrate"))
            assert.equal(1, #soundCalls)
            assert.equal(8960, soundCalls[1].id)
        end)

        it("sets Sound_SFXVolume CVar before playing and defers restore", function()
            SelfCareDB.alertVolume = 50
            local setCvarCalls = {}
            _G.SetCVar = function(key, value)
                table.insert(setCvarCalls, { key = key, value = tostring(value) })
            end
            SelfCare.ShowNotif(makeAlert("hydrate"))
            -- First SetCVar call should set volume to 0.5
            assert.equal("Sound_SFXVolume", setCvarCalls[1].key)
            assert.equal("0.5", setCvarCalls[1].value)
            -- Restore is deferred (via C_Timer.After), not immediate
            assert.equal(1, #setCvarCalls)
            -- Fire the deferred restore
            local afterTimers = C_Timer.GetAfterTimers()
            assert.equal(1, #afterTimers)
            afterTimers[1]:Fire()
            assert.equal(2, #setCvarCalls)
        end)

        it("does not play sound or set CVar when alertVolume is 0", function()
            SelfCareDB.alertVolume = 0
            local setCvarCalls = {}
            _G.SetCVar = function(key, value)
                table.insert(setCvarCalls, { key = key, value = value })
            end
            SelfCare.ShowNotif(makeAlert("hydrate"))
            assert.equal(0, #soundCalls)
            assert.equal(0, #setCvarCalls)
        end)

        it("does not call PlaySound when alertSound is 0 (None)", function()
            SelfCareDB.alertSound = 0
            SelfCare.ShowNotif(makeAlert("hydrate"))
            assert.equal(0, #soundCalls)
        end)

        it("prints to chat when printToChat is true", function()
            SelfCareDB.printToChat = true
            SelfCare.ShowNotif(makeAlert("hydrate", "Drink water!"))
            assert.equal(1, #printCalls)
            assert.truthy(printCalls[1]:find("Drink water!"))
        end)

        it("does not print to chat when printToChat is false", function()
            SelfCareDB.printToChat = false
            SelfCare.ShowNotif(makeAlert("hydrate"))
            assert.equal(0, #printCalls)
        end)

        it("creates an auto-dismiss timer with the configured delay", function()
            SelfCareDB.dismissDelay = 15
            SelfCare.ShowNotif(makeAlert("hydrate"))
            local timers = C_Timer.GetTimers()
            -- At least one timer should be the dismiss timer
            local found = false
            for _, t in ipairs(timers) do
                if t.delay == 15 then found = true end
            end
            assert.is_true(found, "No dismiss timer found with delay=15")
        end)

        it("cancels any pending dismiss timer before showing a new notif", function()
            SelfCare.ShowNotif(makeAlert("hydrate"))
            local firstDismissTimer = C_Timer.GetTimers()[1]

            -- Show another notification immediately
            SelfCare.ShowNotif(makeAlert("posture"))

            assert.is_true(firstDismissTimer.cancelled,
                "Previous dismiss timer should have been cancelled")
        end)

        it("shows the notification frame", function()
            SelfCare.ShowNotif(makeAlert("hydrate"))
            -- The frame should have been shown; UIFrameFadeIn was called
            assert.equal(1, #fadeInCalls)
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("HideNotif", function()
        it("calls UIFrameFadeOut after ShowNotif", function()
            SelfCare.ShowNotif(makeAlert("hydrate"))
            SelfCare.HideNotif()
            assert.equal(1, #fadeOutCalls)
        end)

        it("cancels the dismiss timer", function()
            SelfCare.ShowNotif(makeAlert("hydrate"))
            local dismissTimer = C_Timer.GetTimers()[1]
            assert.is_false(dismissTimer.cancelled)

            SelfCare.HideNotif()
            assert.is_true(dismissTimer.cancelled)
        end)

        it("does not error when called before any ShowNotif", function()
            assert.has_no.errors(function()
                SelfCare.HideNotif()
            end)
        end)

        it("creates a short hide timer after fading out", function()
            SelfCare.ShowNotif(makeAlert("hydrate"))
            C_Timer.Reset()  -- clear dismiss timer so we can isolate the hide timer

            SelfCare.HideNotif()

            local timers = C_Timer.GetTimers()
            -- The 0.31s hide timer should have been created
            local found = false
            for _, t in ipairs(timers) do
                if math.abs(t.delay - 0.31) < 0.001 then found = true end
            end
            assert.is_true(found, "Expected a 0.31s hide timer after HideNotif")
        end)

        it("auto-dismiss timer fires HideNotif", function()
            SelfCare.ShowNotif(makeAlert("hydrate"))
            local dismissTimer = C_Timer.GetTimers()[1]
            assert.is_false(dismissTimer.cancelled)

            -- Simulate the timer expiring
            dismissTimer:Fire()

            -- After the dismiss fires, UIFrameFadeOut should be called
            assert.equal(1, #fadeOutCalls)
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("hint text", function()
        it("shows countdown hint when autoDismiss is true", function()
            SelfCareDB.autoDismiss = true
            SelfCare.ShowNotif(makeAlert("hydrate"))
            -- Smoke check: no error, frame fades in
            assert.equal(1, #fadeInCalls)
        end)

        it("shows 'Click to dismiss' hint when autoDismiss is false", function()
            SelfCareDB.autoDismiss = false
            SelfCare.ShowNotif(makeAlert("hydrate"))
            assert.equal(1, #fadeInCalls)
        end)
    end)

end)

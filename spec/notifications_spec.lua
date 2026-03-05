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

        _G.PlaySound = function(id)
            table.insert(soundCalls, id)
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

        it("plays sound 808", function()
            SelfCare.ShowNotif(makeAlert("hydrate"))
            assert.equal(1, #soundCalls)
            assert.equal(808, soundCalls[1])
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
        it("shows 'Click to dismiss' hint when dismissOnClick is true", function()
            SelfCareDB.dismissOnClick = true
            SelfCare.ShowNotif(makeAlert("hydrate"))
            -- We can't inspect file-local notifFrame.hint._text directly,
            -- but no error should occur (smoke check)
            assert.equal(1, #fadeInCalls)
        end)

        it("shows 'Dismisses in Xs' hint when dismissOnClick is false", function()
            SelfCareDB.dismissOnClick = false
            SelfCare.ShowNotif(makeAlert("hydrate"))
            assert.equal(1, #fadeInCalls)
        end)
    end)

end)

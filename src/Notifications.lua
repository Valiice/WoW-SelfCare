-- =============================================================================
-- Notifications.lua
-- Single reusable notification frame — fades in/out, click-to-dismiss or
-- auto-dismiss. Private frame state stays in file-level locals.
-- =============================================================================

local notifFrame        -- the shared Button frame
local notifDismissTimer -- auto-dismiss timer handle
local notifHideTimer    -- the 0.31s fade-then-hide timer

local function BuildNotifFrame()
    if notifFrame then return end

    -- A simple clickable frame — just floating text, no border or background,
    -- matching the minimal style of the original FFXIV plugin.
    local f = CreateFrame("Button", "SelfCareNotifFrame", UIParent)
    f:SetSize(400, 60)
    -- Restore saved position, or default to slightly above centre
    if SelfCareDB.notifPos then
        local p = SelfCareDB.notifPos
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(100)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        SelfCareDB.notifPos = { point, relPoint, x, y }
    end)

    -- Main reminder text — large, centered, white
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    text:SetAllPoints(f)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(true)
    text:SetTextColor(1, 1, 1, 1)
    f.text = text

    -- Subtle "click to dismiss" hint below the main text
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", text, "BOTTOM", 0, -4)
    hint:SetText("Click to dismiss")
    f.hint = hint

    -- Click to dismiss
    f:SetScript("OnClick", function()
        if SelfCareDB.dismissOnClick then
            SelfCare.HideNotif()
        end
    end)

    f:Hide()
    notifFrame = f
end

function SelfCare.ShowNotif(alert)
    BuildNotifFrame()
    if notifHideTimer    then notifHideTimer:Cancel();    notifHideTimer    = nil end
    if notifDismissTimer then notifDismissTimer:Cancel(); notifDismissTimer = nil end

    notifFrame.text:SetText(alert.message)

    -- Hint: mention click-to-dismiss if enabled, always show the auto-dismiss countdown
    if SelfCareDB.dismissOnClick then
        notifFrame.hint:SetText(string.format("Click to dismiss · %ds", SelfCareDB.dismissDelay))
    else
        notifFrame.hint:SetText(string.format("Dismisses in %ds", SelfCareDB.dismissDelay))
    end

    notifFrame:Show()
    notifFrame:SetAlpha(0)
    UIFrameFadeIn(notifFrame, 0.4, 0, 1)

    -- Optional chat print
    if SelfCareDB.printToChat then
        SelfCare.Print(alert.message)
    end

    -- Play a pleasant UI sound
    PlaySound(808)

    -- Always auto-dismiss after the delay; dismissOnClick just adds click as an extra way out
    notifDismissTimer = C_Timer.NewTimer(SelfCareDB.dismissDelay, function()
        SelfCare.HideNotif()
    end)
end

function SelfCare.HideNotif()
    if notifHideTimer    then notifHideTimer:Cancel();    notifHideTimer    = nil end
    if notifDismissTimer then notifDismissTimer:Cancel(); notifDismissTimer = nil end
    if notifFrame and notifFrame:IsShown() then
        UIFrameFadeOut(notifFrame, 0.3, 1, 0)
        notifHideTimer = C_Timer.NewTimer(0.31, function()
            notifFrame:Hide()
            notifHideTimer = nil
        end)
    end
end

//
//  KeySessionMark.swift
//  RunningLog · Training
//
//  THE ONE ANSWER to "was this a key session?"
//
//  Before this file there were four rules, each guessing from different
//  inputs, none of them correctable (KEY-SESSION-APPLY.md §"The diagnosis"):
//  the calendar starred any day containing a single fast stretch; the journal
//  starred a hardcoded set of workout_type strings; the server had a third
//  rule; the coach portal had a fourth with two constants that exist nowhere
//  else. The same run got two different answers on two screens.
//
//  The fix is not a fifth rule. It's an order of precedence, so that the
//  athlete's own word is allowed to win:
//
//      athlete override   (day_overrides — set from the day sheet)
//            ↓ falls through to
//      plan intent        (scheduled_workouts.is_key_session — when scheduled)
//            ↓ falls through to
//      derived            (whatever the surface can compute)
//
//  First non-nil wins. No blending, and no hiding the marker when two levels
//  happen to agree.
//
//  A key session becomes something you DECLARE, not something a classifier
//  notices afterwards — which also makes it knowable before you run it.
//
//  ── Scope note, phase 1 ────────────────────────────────────────────────────
//  `planIntent` is wired through and honored here, but nothing writes it yet
//  (that's §2/§5 of the spec — the scheduled_workouts column and the plan
//  builder). Every caller passes nil today. It is in the signature now so
//  that landing plan intent later is a write, not a re-architecture.
//
//  `derived` is supplied BY THE CALLER rather than computed here, also on
//  purpose. Each surface still passes its own existing rule, so this change
//  adds the override without silently changing which days are starred. When
//  §1/§4 land (persisted quality_load), every caller switches to passing
//  `QualityLoad.qualifies(dayLoad)` and the old rules get deleted — and this
//  file does not change. That is the seam.
//

import Foundation

/// NAMED `KeySessionMark`, not `KeySession`, because `Trends/TrendsModels.swift`
/// already owns `struct KeySession` — the decode shape for one scored session
/// coming back from `trends-timeline`. That type is a MEASUREMENT of a session;
/// this one is the DECISION about a day. Different things, and the compiler was
/// right to refuse both names.
enum KeySessionMark {

    /// Who decided this day was (or wasn't) a key session. Drives how the
    /// star is drawn — an athlete's declaration should not look identical to
    /// the app's guess.
    enum Provenance: Equatable {
        /// Derived by the app. The guess.
        case auto
        /// Set on the plan when the session was scheduled. Somebody meant this.
        case planned
        /// The athlete said so, after the fact. Outranks everything.
        case athlete
    }

    /// The one definition. First non-nil wins.
    ///
    /// - Parameters:
    ///   - override:   `day_overrides.is_key_session`. nil = nothing said,
    ///                 true = key, **false = explicitly not key**. That third
    ///                 state is why this is `Bool?` and not `Bool` — without
    ///                 it you can only fail to claim a day was key, you can't
    ///                 say it wasn't.
    ///   - planIntent: `scheduled_workouts.is_key_session`. Same three states.
    ///   - derived:    the surface's own derivation, or nil if it can't say.
    ///   - isFuture:   a day that hasn't happened yet.
    ///
    /// Future days: `derived` never applies (there's no run to score), but a
    /// declaration does. A Tuesday you marked as key shows its star before you
    /// run it — which is the whole point of marking at scheduling time.
    static func isKey(override: Bool?,
                      planIntent: Bool?,
                      derived: Bool?,
                      isFuture: Bool) -> Bool {
        if let override { return override }
        if let planIntent { return planIntent }
        if isFuture { return false }
        return derived ?? false
    }

    /// Which level produced the answer. Note this reports the level that
    /// DECIDED, regardless of whether the levels agree: a day the athlete
    /// marked key that also derives as key is still `.athlete`, because the
    /// athlete's mark is a fact about intent and shouldn't disappear just
    /// because the app happened to agree with it.
    static func provenance(override: Bool?, planIntent: Bool?) -> Provenance {
        if override != nil { return .athlete }
        if planIntent != nil { return .planned }
        return .auto
    }
}

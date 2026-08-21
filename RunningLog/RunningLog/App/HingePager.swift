//
//  HingePager.swift
//  RunningLog
//
//  The page turn, as a hinge.
//
//  `HistoryDetailPager` and `JournalPagerView` both paged with the same
//  mechanic: `ScrollView(.horizontal)` + `.scrollTargetBehavior(.paging)`.
//  That slides. It does not turn. This replaces the slide with a sheet that
//  rotates about its leading edge and lifts off the page beneath it, which is
//  what a page actually does.
//
//  WHY THIS IS A CONTAINER AND NOT AN EFFECT
//
//  `.scrollTransition` can decorate a paging ScrollView cheaply — that is how
//  the "paper slide" option in `page-turn-lab-prototype.html` was costed at
//  ~40 lines. A hinge cannot be done that way. A sheet rotating past 90° has
//  to be *composited above* the page it is revealing, and a paging ScrollView
//  lays its children out side by side in a row: there is no "beneath". So the
//  pages stack in a `ZStack` and the paging behaviour — velocity, snapping,
//  rubber-banding at the ends — is hand-rolled below.
//
//  Both call sites keep their own rails, spines, haptics and accessibility
//  actions. This owns the turn and nothing else.
//
//  THE ONE NUMBER TO TUNE: `perspective`. At 0 the page shears flat with no
//  depth; at 1 it looks like a wide-angle lens. 0.55 is a book held at
//  reading distance. Everything else is downstream of that.
//
//  DIRECTION IS A PARAMETER, DELIBERATELY. This app has two pagers that run
//  opposite ways in time — `HistoryDetailPager` is book order (oldest page
//  first) and `HomeDayPager` is newspaper order (today is the front page).
//  See `PAGED-HOME-APPLY.md` §8.1. While the turn was a flat slide that was a
//  detail. A hinge makes direction physical, so it now needs an answer rather
//  than a default. `HingeOrder` does not change any behaviour today — it
//  changes only the VoiceOver wording — but it puts the decision in one place
//  so settling it later is a one-line edit per call site, not a rewrite.
//

import SwiftUI

// MARK: - Reading order

/// Which way the index runs in time. Affects the words VoiceOver uses for the
/// turn actions, nothing else.
enum HingeOrder {
    /// Index grows forward in time — oldest page first, today last.
    /// Turning forward means "newer". `HistoryDetailPager` is this.
    case book
    /// Index grows backward in time — today is the front page.
    /// Turning forward means "older". `HomeDayPager` is this.
    case newspaper
    /// The pages are parts of one thing, not moments in time — the four faces
    /// of a single session. Forward is just "next".
    case sequence

    var forwardLabel: String {
        switch self {
        case .book:      return "Newer entry"
        case .newspaper: return "Older entry"
        case .sequence:  return "Next page"
        }
    }

    var backwardLabel: String {
        switch self {
        case .book:      return "Older entry"
        case .newspaper: return "Newer entry"
        case .sequence:  return "Previous page"
        }
    }
}

// MARK: - The pager

/// A stack of pages turned by a hinge on the leading edge.
///
/// Drop-in for the paging `ScrollView` both existing pagers used. The
/// selection binding has the same shape (`Item.ID?`), so the surrounding
/// `.onChange` haptics, rails and spines keep working untouched.
///
///     HingePager(items: pages, selection: $pageID, locked: $pagingLocked, order: .sequence) { page in
///         pageView(page, entry: entry)
///     }
///
struct HingePager<Item: Identifiable, Content: View>: View {

    let items: [Item]
    @Binding var selection: Item.ID?
    /// Honours the existing `pageTurnLocked` contract — a child that owns the
    /// horizontal drag (the telemetry scrubber) raises this and the turn stops
    /// accepting gestures.
    @Binding var locked: Bool
    var order: HingeOrder = .sequence
    /// Depth of the fold. 0.55 ≈ a book at reading distance. See file header.
    var perspective: CGFloat = 0.55
    @ViewBuilder var content: (Item) -> Content

    /// The animated source of truth, in pages. Fractional while turning.
    ///
    /// Deliberately NOT derived from `selection`. If it were, committing a
    /// turn would change `selection` (and therefore the derived index)
    /// instantly while the drag offset animated separately to zero, and the
    /// page would jump a full width at the start of every commit. Position
    /// animates; `selection` is written alongside it and read back only when
    /// something outside changes it.
    @State private var position: Double = 0
    @State private var anchorIndex: Int = 0
    @State private var isDragging = false
    @State private var engaged = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var index: Int {
        items.firstIndex { $0.id == selection } ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)

            ZStack(alignment: .topLeading) {
                ForEach(visibleIndices, id: \.self) { i in
                    page(at: i)
                        .frame(width: geo.size.width, height: geo.size.height)
                        // Lower index rides above, so the sheet being turned is
                        // always composited over the one it is revealing.
                        .zIndex(Double(items.count - i))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(turn(width: width), including: gestureMask)
        }
        .onAppear { position = Double(index) }
        .onChange(of: selection) { _, _ in
            // A rail tap, a spine tap or a VoiceOver action moved the page
            // from outside. Catch up — unless the drag is what moved it.
            guard !isDragging else { return }
            withAnimation(.snappy(duration: 0.34, extraBounce: 0)) {
                position = Double(index)
            }
        }
        .onChange(of: items.count) { _, _ in
            // The page list changed underfoot (the charts page appearing once
            // the stream flag loads, an entry deleted). Re-seat without
            // animating — there is no turn to show.
            position = Double(index)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text(order.forwardLabel)) { step(1) }
        .accessibilityAction(named: Text(order.backwardLabel)) { step(-1) }
        .accessibilityScrollAction { edge in
            switch edge {
            case .leading:  step(-1)
            case .trailing: step(1)
            default:        break
            }
        }
    }

    // MARK: Pages

    /// Only the sheet being turned, the one beneath it, and one either side.
    /// The old `LazyHStack` kept about three alive; this keeps at most four,
    /// and never rebuilds the whole run.
    private var visibleIndices: [Int] {
        guard !items.isEmpty else { return [] }
        let lo = max(Int(floor(position)) - 1, 0)
        let hi = min(Int(ceil(position)) + 1, items.count - 1)
        guard lo <= hi else { return [] }
        return Array(lo ... hi)
    }

    @ViewBuilder
    private func page(at i: Int) -> some View {
        // How far past this sheet we have turned. 0 = lying flat and face up,
        // 1 = fully turned away.
        let q = clamp(position - Double(i), 0, 1)

        // The sheet directly above this one, so a page can draw the shadow its
        // neighbour casts into the gutter as that neighbour lifts.
        let above = i > 0 ? clamp(position - Double(i - 1), 0, 1) : 0

        content(items[i])
            .overlay {
                // Gutter shadow — the fold above this page throwing a shadow
                // down the binding edge. Strongest at the half-turn, gone at
                // both ends, so it breathes with the turn instead of blinking.
                if !reduceMotion && above > 0 && above < 1 {
                    LinearGradient(
                        colors: [
                            Color.drip.textPrimary.opacity(0.26 * sin(.pi * above)),
                            Color.drip.textPrimary.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .center
                    )
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                // The turning sheet itself falling into shade as it goes edge-on.
                if !reduceMotion && q > 0 {
                    Color.drip.textPrimary
                        .opacity(0.34 * q)
                        .allowsHitTesting(false)
                }
            }
            // Past the half-turn the sheet is edge-on and would begin showing
            // its own back — SwiftUI has no `backface-visibility`, and the
            // reverse of a page is a mirrored copy of its front, which reads as
            // a rendering bug. Cut it there. At 90° the sheet is a line, so the
            // cut is invisible.
            .opacity(reduceMotion ? 1 - q : (q < 0.5 ? 1 : 0))
            .rotation3DEffect(
                .degrees(reduceMotion ? 0 : -180 * q),
                axis: (x: 0, y: 1, z: 0),
                anchor: .leading,
                anchorZ: 0,
                perspective: perspective
            )
            // Only the sheet you can actually see should take a tap.
            .allowsHitTesting(q < 0.5)
            .accessibilityHidden(q >= 0.5)
    }

    // MARK: Turning

    private var gestureMask: GestureMask {
        // `.subviews` lets the page's own controls keep working while the turn
        // itself is suppressed — the documented way to conditionally disable a
        // gesture without disabling the content under it.
        (locked || items.count < 2) ? .subviews : .all
    }

    private func turn(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                if !engaged {
                    // Only take the drag once it is clearly horizontal. Without
                    // this the turn steals every vertical scroll inside a page.
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.2
                    else { return }
                    engaged = true
                    isDragging = true
                    anchorIndex = index
                }

                var d = -value.translation.width / width
                let lower = Double(-anchorIndex)
                let upper = Double(items.count - 1 - anchorIndex)
                // Rubber-band past the first and last page rather than stopping
                // dead, so the ends of the journal feel like ends and not walls.
                if d < lower { d = lower + (d - lower) * 0.28 }
                if d > upper { d = upper + (d - upper) * 0.28 }

                position = Double(anchorIndex) + d
            }
            .onEnded { value in
                defer { engaged = false; isDragging = false }
                guard engaged else { return }

                let travelled = position - Double(anchorIndex)
                // `predictedEndTranslation` is how a flick commits a turn the
                // finger never finished — the same feel `.scrollTargetBehavior`
                // gave us for free.
                let predicted = -value.predictedEndTranslation.width / width

                let step: Int
                if travelled > 0.26 || predicted > 0.55 { step = 1 }
                else if travelled < -0.26 || predicted < -0.55 { step = -1 }
                else { step = 0 }

                commit(anchorIndex + step)
            }
    }

    private func commit(_ target: Int) {
        let landing = min(max(target, 0), max(items.count - 1, 0))
        // Write the selection first and animate position alongside it. The
        // call site's `.onChange(of:)` fires the haptic; this file owns no
        // feedback of its own so the two pagers keep the feel they had.
        if items.indices.contains(landing), items[landing].id != selection {
            selection = items[landing].id
        }
        withAnimation(.snappy(duration: 0.34, extraBounce: 0)) {
            position = Double(landing)
        }
    }

    private func step(_ delta: Int) {
        commit(index + delta)
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        v < lo ? lo : (v > hi ? hi : v)
    }
}

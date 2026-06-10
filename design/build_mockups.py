"""
Negative Splits — Running Log Trends mockups
Generates a 4-page PDF of iPhone-screen mockups for the v1 analytics surface.
"""
from PIL import Image, ImageDraw, ImageFont
import math
import random
import os

random.seed(7)

# -------- canvas + palette ----------
PAGE_W, PAGE_H = 1200, 1800
PHONE_W, PHONE_H = 560, 1212
PHONE_X = (PAGE_W - PHONE_W) // 2
PHONE_Y = 280
PHONE_RADIUS = 64
SCREEN_INSET = 14

BONE = (244, 241, 234)
PAPER = (252, 250, 244)
INK = (26, 22, 20)
SLATE = (123, 128, 133)
SLATE_LIGHT = (180, 183, 187)
HAIR = (220, 217, 209)
AMBER = (232, 116, 60)
GREEN_OK = (90, 138, 109)

# -------- fonts ----------
FONT_DIR = "/sessions/gracious-lucid-heisenberg/mnt/.claude/skills/canvas-design/canvas-fonts"
def f(name, size):
    return ImageFont.truetype(os.path.join(FONT_DIR, name), size)

DISPLAY     = lambda s: f("CrimsonPro-Regular.ttf", s)   # big numerals
DISPLAY_B   = lambda s: f("CrimsonPro-Bold.ttf", s)
SERIF_IT    = lambda s: f("CrimsonPro-Italic.ttf", s)
SANS        = lambda s: f("InstrumentSans-Regular.ttf", s)
SANS_B      = lambda s: f("InstrumentSans-Bold.ttf", s)
MONO        = lambda s: f("GeistMono-Regular.ttf", s)
MONO_B      = lambda s: f("GeistMono-Bold.ttf", s)

# -------- helpers ----------
def text(d, xy, s, font, fill=INK, anchor="la", spacing=4):
    d.text(xy, s, font=font, fill=fill, anchor=anchor, spacing=spacing)

def tw(d, s, font):
    return d.textlength(s, font=font)

def hairline(d, x1, y1, x2, y2, fill=HAIR, width=1):
    d.line([(x1,y1),(x2,y2)], fill=fill, width=width)

def rounded_box(d, x1, y1, x2, y2, r, fill=None, outline=None, width=1):
    d.rounded_rectangle([x1,y1,x2,y2], radius=r, fill=fill, outline=outline, width=width)

def caret_down(d, cx, cy, size=5, fill=SLATE):
    """Draw a small filled downward triangle — font-independent."""
    d.polygon([(cx-size, cy-size//2),(cx+size, cy-size//2),(cx, cy+size)], fill=fill)

def arrow_up_right(d, x, y, size=8, fill=AMBER, width=2):
    """Tiny diagonal arrow — for SHARE indicator. Font-independent."""
    d.line([(x, y+size),(x+size, y)], fill=fill, width=width)
    d.line([(x+size-4, y),(x+size, y),(x+size, y+4)], fill=fill, width=width)

# -------- canvas chrome (every page) ----------
def new_page():
    img = Image.new("RGB", (PAGE_W, PAGE_H), BONE)
    d = ImageDraw.Draw(img)
    return img, d

def page_chrome(d, fig_no, title_eyebrow, title_main, caption):
    # marginalia
    text(d, (60, 60), "RUNNING LOG", MONO(14), fill=SLATE, anchor="la")
    text(d, (60, 82), "— TRENDS · v1 ANALYTICS SURFACE", MONO(14), fill=SLATE, anchor="la")
    text(d, (PAGE_W-60, 60), f"FIG. {fig_no}", MONO(14), fill=SLATE, anchor="ra")
    text(d, (PAGE_W-60, 82), "NEGATIVE SPLITS · 04.2026", MONO(14), fill=SLATE, anchor="ra")
    hairline(d, 60, 110, PAGE_W-60, 110, fill=SLATE_LIGHT)

    # main title (left of phone, vertical breathing room)
    text(d, (60, 170), title_eyebrow, MONO(14), fill=AMBER, anchor="la")
    text(d, (60, 200), title_main, DISPLAY_B(64), fill=INK, anchor="la")

    # bottom caption + footer
    hairline(d, 60, PAGE_H-150, PAGE_W-60, PAGE_H-150, fill=SLATE_LIGHT)
    # caption wraps
    cx, cy = 60, PAGE_H - 125
    for line in caption:
        text(d, (cx, cy), line, SERIF_IT(22), fill=INK, anchor="la")
        cy += 30

    text(d, (60, PAGE_H-50), "PLATE " + str(fig_no).zfill(2) + " / 29", MONO(14), fill=SLATE, anchor="la")
    text(d, (PAGE_W-60, PAGE_H-50), "—— restraint as foundation, intensity as accent", MONO(14), fill=SLATE, anchor="ra")

# -------- phone frame ----------
def draw_phone(d):
    # outer phone
    rounded_box(d, PHONE_X, PHONE_Y, PHONE_X+PHONE_W, PHONE_Y+PHONE_HEIGHT, PHONE_RADIUS,
                fill=INK, outline=None)
    # screen
    sx1, sy1 = PHONE_X+SCREEN_INSET, PHONE_Y+SCREEN_INSET
    sx2, sy2 = PHONE_X+PHONE_W-SCREEN_INSET, PHONE_Y+PHONE_HEIGHT-SCREEN_INSET
    rounded_box(d, sx1, sy1, sx2, sy2, PHONE_RADIUS-SCREEN_INSET, fill=PAPER)
    # dynamic island
    di_w, di_h = 130, 32
    di_x = (PHONE_X + PHONE_W//2) - di_w//2
    di_y = sy1 + 18
    rounded_box(d, di_x, di_y, di_x+di_w, di_y+di_h, di_h//2, fill=INK)
    # status bar
    text(d, (sx1+30, di_y+8), "9:41", SANS_B(18), fill=INK, anchor="la")
    text(d, (sx2-30, di_y+8), "● ● ● ●", SANS(14), fill=INK, anchor="ra")
    return sx1, sy1, sx2, sy2

PHONE_HEIGHT = PHONE_H

# -------- screen content helpers ----------
def screen_header(d, sx1, sy1, sx2, eyebrow, title, week_label=None,
                  week_caret=False, week_arrow=False):
    y = sy1 + 90
    text(d, (sx1+30, y), eyebrow, MONO(12), fill=AMBER, anchor="la")
    if week_label:
        # if a caret/arrow follows the label, leave room on the right for it
        right_pad = 14 if (week_caret or week_arrow) else 0
        text(d, (sx2-30-right_pad, y), week_label, MONO(12), fill=SLATE, anchor="ra")
        if week_caret:
            caret_down(d, sx2-30-5, y+8, size=4, fill=SLATE)
        elif week_arrow:
            arrow_up_right(d, sx2-30-10, y-2, size=10, fill=AMBER, width=2)
    text(d, (sx1+30, y+22), title, DISPLAY_B(34), fill=INK, anchor="la")
    hairline(d, sx1+30, y+72, sx2-30, y+72, fill=HAIR)
    return y + 90

def tab_bar(d, sx1, sy1, sx2, sy2, active_idx):
    # five tabs: Log Train Trends Coach Workouts
    bar_y = sy2 - 90
    hairline(d, sx1+20, bar_y, sx2-20, bar_y, fill=HAIR)
    labels = ["LOG","TRAIN","TRENDS","COACH","RUNS"]
    icons  = ["·","·","·","·","·"]  # restrained — abstract dots
    cell_w = (sx2 - sx1 - 40) // 5
    for i, lab in enumerate(labels):
        cx = sx1 + 20 + cell_w*i + cell_w//2
        active = (i == active_idx)
        # dot icon (filled if active, else hollow)
        r = 4
        if active:
            d.ellipse([cx-r, bar_y+22-r, cx+r, bar_y+22+r], fill=INK)
        else:
            d.ellipse([cx-r, bar_y+22-r, cx+r, bar_y+22+r], outline=SLATE_LIGHT, width=1)
        text(d, (cx, bar_y+42), lab, MONO(10),
             fill=INK if active else SLATE, anchor="ma")

# ---------------------------------------------------------------------------
# PAGE 1 — TRENDS HOME
# ---------------------------------------------------------------------------
def page_1():
    img, d = new_page()
    page_chrome(d, 1,
                "OPENING FIGURE",
                "The 5-Second View",
                ["The athlete crosses a threshold. Within five seconds: volume, fitness,",
                 "load, risk — four numerals that decide whether today is push or pull."])
    sx1, sy1, sx2, sy2 = draw_phone(d)
    y = screen_header(d, sx1, sy1, sx2, "TRENDS · WEEK 09 OF 16", "Marathon block", week_label="MON · APR 27")

    # 2x2 KPI tiles
    tile_pad = 12
    grid_x1 = sx1 + 30
    grid_x2 = sx2 - 30
    tile_w = (grid_x2 - grid_x1 - tile_pad) // 2
    tile_h = 150

    def tile(x, y, label, big, unit, sub, accent=False, sub_color=SLATE):
        rounded_box(d, x, y, x+tile_w, y+tile_h, 14, fill=BONE, outline=HAIR, width=1)
        text(d, (x+18, y+16), label, MONO(11), fill=SLATE, anchor="la")
        # big numeral
        text(d, (x+18, y+38), big, DISPLAY_B(54), fill=AMBER if accent else INK, anchor="la")
        # unit, anchored to baseline of big numeral via right-of measure
        big_w = tw(d, big, DISPLAY_B(54))
        text(d, (x+18+big_w+8, y+72), unit, MONO(11), fill=SLATE, anchor="la")
        # sub
        text(d, (x+18, y+tile_h-30), sub, MONO(11), fill=sub_color, anchor="la")

    tile(grid_x1, y, "VOLUME · 7D",
         "47.2", "MI", "+8%  vs 4-WK AVG", sub_color=GREEN_OK)
    tile(grid_x1+tile_w+tile_pad, y, "FITNESS",
         "3:14", "FULL", "−47s  vs 4 WEEKS AGO", sub_color=GREEN_OK)
    y2 = y + tile_h + tile_pad
    tile(grid_x1, y2, "LOAD · ACWR",
         "1.18", "RATIO", "PRODUCTIVE", sub_color=GREEN_OK)
    tile(grid_x1+tile_w+tile_pad, y2, "INJURY RISK",
         "2.4", "/ 10", "LOW · 4W AVG 2.1", sub_color=SLATE)

    # mini fitness chart
    sec_y = y2 + tile_h + 36
    text(d, (grid_x1, sec_y), "FITNESS · 12-WEEK PROGRESSION", MONO(11), fill=SLATE, anchor="la")
    text(d, (grid_x2, sec_y), "TAP TO EXPAND →", MONO(11), fill=SLATE, anchor="ra")
    chart_x1, chart_x2 = grid_x1, grid_x2
    chart_y1, chart_y2 = sec_y + 22, sec_y + 22 + 130
    rounded_box(d, chart_x1, chart_y1, chart_x2, chart_y2, 10, fill=BONE, outline=HAIR, width=1)
    # baseline / target lines
    target_y = chart_y1 + 32
    hairline(d, chart_x1+12, target_y, chart_x2-12, target_y, fill=SLATE_LIGHT)
    text(d, (chart_x2-16, target_y-12), "GOAL  3:10", MONO(10), fill=SLATE, anchor="ra")
    # fitness curve — descending (faster predicted time)
    pts = []
    n = 24
    for i in range(n):
        t = i/(n-1)
        # smooth descent + small ripples
        v = 80 - t*55 - 4*math.sin(t*5.0) + (random.random()-0.5)*3
        x = chart_x1 + 12 + t*(chart_x2 - chart_x1 - 24)
        yy = chart_y2 - 12 - v
        pts.append((x, yy))
    # confidence band (faint)
    band_top = [(x, y-7) for x,y in pts]
    band_bot = [(x, y+7) for x,y in pts]
    d.polygon(band_top + list(reversed(band_bot)), fill=(232,228,218))
    # draw line
    d.line(pts, fill=INK, width=2, joint="curve")
    # current point (amber)
    cx, cy = pts[-1]
    d.ellipse([cx-5, cy-5, cx+5, cy+5], fill=AMBER, outline=PAPER, width=2)

    # mini load chart
    sec2_y = chart_y2 + 28
    text(d, (grid_x1, sec2_y), "LOAD · WEEKLY VOLUME × ACWR", MONO(11), fill=SLATE, anchor="la")
    bar_y1 = sec2_y + 22
    bar_y2 = bar_y1 + 110
    rounded_box(d, chart_x1, bar_y1, chart_x2, bar_y2, 10, fill=BONE, outline=HAIR, width=1)
    weeks = 12
    bw = (chart_x2 - chart_x1 - 40) / (weeks*1.6)
    base_y = bar_y2 - 14
    vals = [28,32,36,30,38,42,46,40,47,44,52,47]
    acwr = [0.9,0.95,1.05,0.9,1.05,1.12,1.18,1.05,1.16,1.10,1.30,1.18]
    bx = chart_x1 + 20
    bar_pts = []
    for i,v in enumerate(vals):
        h = (v/55)*(base_y - bar_y1 - 16)
        x1 = bx + i*(bw*1.6)
        x2 = x1 + bw
        d.rectangle([x1, base_y-h, x2, base_y], fill=INK if i==len(vals)-1 else SLATE)
        bar_pts.append((x1 + bw/2, bar_y1 + 12 + (1.4-acwr[i])*60))
    # acwr line overlay
    d.line(bar_pts, fill=AMBER, width=2)
    text(d, (chart_x2-16, bar_y1+8), "ACWR 1.18", MONO(10), fill=AMBER, anchor="ra")

    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=2)
    return img

# ---------------------------------------------------------------------------
# PAGE 2 — FITNESS PROGRESSION
# ---------------------------------------------------------------------------
def page_2():
    img, d = new_page()
    page_chrome(d, 2,
                "MIDDLE PASSAGE",
                "Fitness, Patiently Plotted",
                ["Twenty-four observations. A target line. A confidence band that narrows",
                 "as the weeks compound. The plan is working — quietly, then noticeably."])
    sx1, sy1, sx2, sy2 = draw_phone(d)
    y = screen_header(d, sx1, sy1, sx2, "FITNESS · MARATHON", "Predicted finish",
                      week_label="DISTANCE", week_caret=True)

    # Big number block
    text(d, (sx1+30, y+10), "3:14:08", DISPLAY_B(86), fill=INK, anchor="la")
    text(d, (sx1+30, y+102), "−1:24 vs 4 WEEKS AGO   ·   GOAL 3:10:00", MONO(12), fill=GREEN_OK, anchor="la")

    # Big chart
    cx1, cx2 = sx1 + 30, sx2 - 30
    cy1, cy2 = y + 150, y + 150 + 320
    rounded_box(d, cx1, cy1, cx2, cy2, 10, fill=BONE, outline=HAIR, width=1)

    # Y axis labels (times)
    times = ["3:30","3:20","3:10","3:00"]
    for i,t in enumerate(times):
        ty = cy1 + 24 + i*((cy2-cy1-48)/(len(times)-1))
        text(d, (cx1+10, ty-8), t, MONO(10), fill=SLATE, anchor="la")
        hairline(d, cx1+60, ty, cx2-12, ty, fill=(235,232,224))

    # GOAL highlight line at 3:10
    goal_y = cy1 + 24 + 2*((cy2-cy1-48)/3)
    d.line([(cx1+60, goal_y),(cx2-12, goal_y)], fill=AMBER, width=2)
    text(d, (cx2-16, goal_y-22), "GOAL", MONO(10), fill=AMBER, anchor="ra")

    # X axis weeks
    n = 24
    chart_l, chart_r = cx1+60, cx2-12
    chart_t, chart_b = cy1+24, cy2-32
    week_labels = ["W1","W4","W8","W12","W16"]
    for i,wl in enumerate(week_labels):
        wx = chart_l + i*((chart_r-chart_l)/(len(week_labels)-1))
        text(d, (wx, cy2-22), wl, MONO(10), fill=SLATE, anchor="ma")

    # synthesize a smooth descending curve from ~3:30 toward ~3:12
    def time_to_y(t_min):
        # 210 (3:30) at top -> chart_t ; 180 (3:00) at bottom -> chart_b
        return chart_t + (210 - t_min)/(210-180) * (chart_b-chart_t)

    pts = []
    for i in range(n):
        t = i/(n-1)
        v = 209 - t*27 - 1.2*math.sin(t*4.5) + (random.random()-0.5)*0.8
        xx = chart_l + t*(chart_r-chart_l)
        yy = time_to_y(v)
        pts.append((xx, yy))

    # confidence band (wider on left, narrower on right)
    band_top = []
    band_bot = []
    for i,(xx,yy) in enumerate(pts):
        spread = 14 - 9*(i/(n-1))
        band_top.append((xx, yy-spread))
        band_bot.append((xx, yy+spread))
    d.polygon(band_top + list(reversed(band_bot)), fill=(230,226,216))

    # main curve
    d.line(pts, fill=INK, width=3, joint="curve")
    # current marker
    cx, cy = pts[-1]
    d.ellipse([cx-7, cy-7, cx+7, cy+7], fill=AMBER, outline=PAPER, width=2)
    # TODAY label set to the LEFT of the dot, well clear of the line
    text(d, (cx-14, cy+12), "TODAY", MONO(10), fill=AMBER, anchor="ra")

    # interpretation
    interp_y = cy2 + 30
    text(d, (sx1+30, interp_y), "INTERPRETATION", MONO(11), fill=SLATE, anchor="la")
    text(d, (sx1+30, interp_y+22), "Trending toward goal.", DISPLAY_B(28), fill=INK, anchor="la")
    text(d, (sx1+30, interp_y+62), "On pace to finish ~3:12 if current trajectory holds",
         SERIF_IT(18), fill=SLATE, anchor="la")
    text(d, (sx1+30, interp_y+86), "through the next 7 weeks.",
         SERIF_IT(18), fill=SLATE, anchor="la")

    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=2)
    return img

# ---------------------------------------------------------------------------
# PAGE 3 — TRAINING LOAD (ACWR)
# ---------------------------------------------------------------------------
def page_3():
    img, d = new_page()
    page_chrome(d, 3,
                "ACCUMULATION",
                "Volume × Ratio",
                ["Twelve weeks of weekly mileage. The amber line above tracks the ratio",
                 "of acute to chronic load — the runner's tempo of restraint and release."])
    sx1, sy1, sx2, sy2 = draw_phone(d)
    y = screen_header(d, sx1, sy1, sx2, "LOAD · 12 WEEKS", "Acute : Chronic",
                      week_label="STRAIN", week_caret=True)

    # Headline
    text(d, (sx1+30, y+10), "1.18", DISPLAY_B(86), fill=INK, anchor="la")
    text(d, (sx1+30, y+102), "PRODUCTIVE OVERLOAD  ·  HOLD STEADY", MONO(12), fill=GREEN_OK, anchor="la")

    # Chart
    cx1, cx2 = sx1+30, sx2-30
    cy1, cy2 = y + 150, y + 150 + 320
    rounded_box(d, cx1, cy1, cx2, cy2, 10, fill=BONE, outline=HAIR, width=1)

    # Two-panel layout: ACWR on top (with bands), bars below as separate volume strip.
    chart_l, chart_r = cx1+60, cx2-12
    # ACWR panel occupies upper ~60%, bar panel the lower ~30% with a gap
    panel_split_top = cy1+30
    panel_split_mid = cy1 + 30 + int((cy2-cy1-70) * 0.62)
    panel_split_bot = cy2 - 40

    # ACWR scale: bottom = 0.7, top = 1.6
    def acwr_y(a):
        return panel_split_top + (1.6 - a)/(1.6-0.7)*(panel_split_mid-panel_split_top)

    # productive band 0.8-1.3
    py1 = acwr_y(1.3)
    py2 = acwr_y(0.8)
    d.rectangle([chart_l, py1, chart_r, py2], fill=(238,242,236))
    # spike band 1.3-1.6
    sy_top = acwr_y(1.6)
    sy_bot = acwr_y(1.3)
    d.rectangle([chart_l, sy_top, chart_r, sy_bot], fill=(248,232,222))

    # zone labels — left-anchored where the ACWR line is lowest (no overlap)
    text(d, (chart_l+10, py1+8), "PRODUCTIVE  0.8 – 1.3", MONO(9), fill=GREEN_OK, anchor="la")
    text(d, (chart_l+10, sy_top+8), "SPIKE  > 1.3", MONO(9), fill=AMBER, anchor="la")

    # ACWR line
    weeks = 12
    acwr = [0.9,0.95,1.05,0.9,1.05,1.12,1.18,1.05,1.16,1.10,1.30,1.18]
    bw = (chart_r - chart_l - 24) / (weeks*1.4)
    line_pts = []
    for i,a in enumerate(acwr):
        x = chart_l + 12 + i*(bw*1.4) + bw/2
        line_pts.append((x, acwr_y(a)))
    d.line(line_pts, fill=AMBER, width=2)
    for x,yy in line_pts:
        d.ellipse([x-3,yy-3,x+3,yy+3], fill=AMBER, outline=PAPER, width=1)

    # divider between panels
    hairline(d, chart_l, panel_split_mid + 18, chart_r, panel_split_mid + 18, fill=HAIR)
    text(d, (chart_l, panel_split_mid + 26), "WEEKLY  MI", MONO(9), fill=SLATE, anchor="la")

    # bars panel
    bar_top = panel_split_mid + 46
    bar_base = panel_split_bot
    vals = [28,32,36,30,38,42,46,40,47,44,52,47]
    max_v = 55
    for i,v in enumerate(vals):
        h = (v/max_v)*(bar_base - bar_top)
        x1 = chart_l + 12 + i*(bw*1.4)
        x2 = x1 + bw
        col = INK if i==len(vals)-1 else SLATE_LIGHT
        d.rectangle([x1, bar_base-h, x2, bar_base], fill=col)
    # x-axis week labels
    week_marks = [0,3,6,9,11]
    for wm in week_marks:
        x = chart_l + 12 + wm*(bw*1.4) + bw/2
        text(d, (x, bar_base+8), f"W{wm+1}", MONO(9), fill=SLATE, anchor="ma")
    # current week annotation
    last_x = chart_l + 12 + (weeks-1)*(bw*1.4) + bw/2
    text(d, (last_x, bar_top - 18), "47 MI", MONO(9), fill=INK, anchor="ma")

    # interpretation panel
    interp_y = cy2 + 30
    text(d, (sx1+30, interp_y), "READ", MONO(11), fill=SLATE, anchor="la")
    text(d, (sx1+30, interp_y+22), "Hold steady this week.", DISPLAY_B(28), fill=INK, anchor="la")
    text(d, (sx1+30, interp_y+62), "Last week's spike landed back inside productive band.",
         SERIF_IT(18), fill=SLATE, anchor="la")
    text(d, (sx1+30, interp_y+86), "No need to back off; no need to push further.",
         SERIF_IT(18), fill=SLATE, anchor="la")

    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=2)
    return img

# ---------------------------------------------------------------------------
# PAGE 4 — BLOCK REVIEW
# ---------------------------------------------------------------------------
def page_4():
    img, d = new_page()
    page_chrome(d, 4,
                "RESOLUTION",
                "Block Review · 04 Weeks",
                ["A passage of training closed and counted. The narrative below is",
                 "machine-written, but it cites only what the runner can already see."])
    sx1, sy1, sx2, sy2 = draw_phone(d)
    y = screen_header(d, sx1, sy1, sx2, "BLOCK 03  ·  WEEKS 09 — 12", "Closed  04.27.2026",
                      week_label="SHARE", week_arrow=True)

    # 4 small stat tiles (single row, smaller height)
    stat_y = y + 10
    tile_w = (sx2 - sx1 - 60 - 36) // 4
    th = 110
    def stat(i, label, big, sub, sub_color=SLATE):
        x = sx1+30 + i*(tile_w+12)
        rounded_box(d, x, stat_y, x+tile_w, stat_y+th, 10, fill=BONE, outline=HAIR, width=1)
        text(d, (x+12, stat_y+10), label, MONO(9), fill=SLATE, anchor="la")
        text(d, (x+12, stat_y+30), big, DISPLAY_B(34), fill=INK, anchor="la")
        text(d, (x+12, stat_y+th-22), sub, MONO(9), fill=sub_color, anchor="la")

    stat(0, "AVG WEEKLY",      "47", "MI · +6%", GREEN_OK)
    stat(1, "FITNESS DELTA",   "−1:24", "PREDICTED", GREEN_OK)
    stat(2, "LONGEST RUN",     "18", "MI · WEEK 11")
    stat(3, "HARD SESSIONS",   "11", "OF 12 PLANNED")

    # narrative card
    nar_y = stat_y + th + 34
    text(d, (sx1+30, nar_y), "SUMMARY", MONO(11), fill=SLATE, anchor="la")
    text(d, (sx1+30, nar_y+22), "A patient block.", DISPLAY_B(34), fill=INK, anchor="la")

    para = [
        "You ran 188 miles across four weeks, an average of 47/wk and",
        "your most consistent block this cycle. Fitness improved by 1:24",
        "on the predicted marathon — most of the gain came from week 11,",
        "where two threshold sessions and the long run all landed on plan.",
        "",
        "ACWR closed at 1.18 (productive). Mood trended up; sleep",
        "averaged 7h 12m. Two flagged weeks: Week 9 you missed a",
        "tempo for travel; Week 11 saw a brief spike, recovered cleanly.",
        "",
        "If the next block holds 45–50 mi/wk and adds one race-pace",
        "long run, the model predicts a sub-3:12 finish becomes high-",
        "confidence by week 14.",
    ]
    py = nar_y + 70
    for line in para:
        if line == "":
            py += 14
            continue
        text(d, (sx1+30, py), line, SERIF_IT(16), fill=INK, anchor="la")
        py += 22

    # share / next-block strip
    strip_y = py + 18
    hairline(d, sx1+30, strip_y, sx2-30, strip_y, fill=HAIR)
    text(d, (sx1+30, strip_y+16), "← BLOCK 02", MONO(11), fill=SLATE, anchor="la")
    text(d, ((sx1+sx2)//2, strip_y+16), "·  EXPORT IMAGE  ·", MONO(11), fill=AMBER, anchor="ma")
    text(d, (sx2-30, strip_y+16), "BLOCK 04 →", MONO(11), fill=SLATE, anchor="ra")

    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=2)
    return img

# ---------------------------------------------------------------------------
# PAGE 5 — WORKOUT DAY SHEET (REDESIGN OF EXISTING SCREEN)
# ---------------------------------------------------------------------------
def page_5():
    img, d = new_page()
    page_chrome(d, 5,
                "RE-TUNING",
                "Workout Day · Sheet",
                ["An existing screen, retuned. Three stats, one calculator, three steps —",
                 "the same content arranged so the eye can find it without searching."])
    sx1, sy1, sx2, sy2 = draw_phone(d)

    # Sheet handle (small horizontal pill at top, in lieu of dynamic island)
    handle_w, handle_h = 56, 6
    hx = (sx1+sx2)//2 - handle_w//2
    hy = sy1 + 30
    rounded_box(d, hx, hy, hx+handle_w, hy+handle_h, handle_h//2, fill=SLATE_LIGHT)

    # Sheet header: Edit / Date / Done
    head_y = sy1 + 76
    text(d, (sx1+30, head_y), "EDIT", MONO(12), fill=AMBER, anchor="la")
    text(d, ((sx1+sx2)//2, head_y-4), "Tue · May 5", DISPLAY_B(26), fill=INK, anchor="ma")
    text(d, (sx2-30, head_y), "DONE", MONO(12), fill=AMBER, anchor="ra")

    hairline(d, sx1+30, head_y+30, sx2-30, head_y+30, fill=HAIR)

    # ── three-stat strip (no boxes, only hairline dividers) ──
    stat_y = head_y + 60
    col_w = (sx2 - sx1 - 60) / 3
    def stat_col(i, label, big, unit):
        x_center = sx1 + 30 + col_w*i + col_w/2
        text(d, (x_center, stat_y), label, MONO(11), fill=SLATE, anchor="ma")
        text(d, (x_center, stat_y+18), big, DISPLAY_B(48), fill=INK, anchor="ma")
        text(d, (x_center, stat_y+82), unit, MONO(11), fill=SLATE, anchor="ma")

    stat_col(0, "DISTANCE", "11.0", "MILES")
    stat_col(1, "DURATION", "—",    "TBD")
    stat_col(2, "STEPS",    "3",    "PHASES")
    # vertical dividers between columns
    for i in [1, 2]:
        x = sx1 + 30 + col_w*i
        d.line([(x, stat_y+6), (x, stat_y+92)], fill=HAIR, width=1)

    hairline(d, sx1+30, stat_y+118, sx2-30, stat_y+118, fill=HAIR)

    # ── HEAT CALCULATOR (restrained — no orange block) ──
    heat_y = stat_y + 144
    # eyebrow row
    text(d, (sx1+30, heat_y), "HEAT  ·  COMPENSATION", MONO(11), fill=SLATE, anchor="la")
    # toggle pill on the right (compact)
    tg_w, tg_h = 36, 18
    tgx = sx2 - 30 - tg_w
    tgy = heat_y - 2
    rounded_box(d, tgx, tgy, tgx+tg_w, tgy+tg_h, tg_h//2, fill=AMBER)
    d.ellipse([tgx+tg_w-tg_h+1, tgy+1, tgx+tg_w-1, tgy+tg_h-1], fill=PAPER)

    # title + meta line
    text(d, (sx1+30, heat_y+22), "Run at 6 AM", DISPLAY_B(24), fill=INK, anchor="la")
    # caret next to the time
    title_w = tw(d, "Run at 6 AM", DISPLAY_B(24))
    caret_down(d, sx1+30+title_w+12, heat_y+38, size=4, fill=SLATE)
    text(d, (sx2-30, heat_y+30), "RESET", MONO(11), fill=SLATE, anchor="ra")

    # error sentence as quiet annotation
    text(d, (sx1+30, heat_y+62), "—— forecast service unreachable.", SERIF_IT(15), fill=SLATE, anchor="la")
    text(d, (sx1+30, heat_y+86), "REFRESH FORECAST", MONO(11), fill=AMBER, anchor="la")
    # tiny vector amber arrow after refresh
    arrow_up_right(d, sx1+30 + tw(d,"REFRESH FORECAST", MONO(11)) + 8, heat_y+82, size=8, fill=AMBER, width=1)

    hairline(d, sx1+30, heat_y+118, sx2-30, heat_y+118, fill=HAIR)

    # ── WORKOUT STEPS (vertical timeline) ──
    ws_y = heat_y + 148
    text(d, (sx1+30, ws_y), "WORKOUT  ·  3 STEPS", MONO(11), fill=SLATE, anchor="la")
    text(d, (sx2-30, ws_y), "11.0 MI  TOTAL", MONO(11), fill=SLATE, anchor="ra")

    # timeline
    tl_x = sx1 + 50  # center of node circles
    tl_top = ws_y + 36
    tl_bot = ws_y + 36 + 460  # rough total height
    # connecting hairline (drawn first; nodes overpaint)
    d.line([(tl_x, tl_top+10), (tl_x, tl_bot-10)], fill=HAIR, width=1)

    def step_node(y, filled=False, color=INK):
        r = 10
        if filled:
            d.ellipse([tl_x-r, y-r, tl_x+r, y+r], fill=color)
        else:
            d.ellipse([tl_x-r, y-r, tl_x+r, y+r], fill=PAPER, outline=color, width=2)

    def step_block(y, kind, distance, target_left, target_right_color, target_right, note,
                   sub_annotation=None, accent=False):
        text_x = tl_x + 32
        # phase name
        name_color = AMBER if accent else GREEN_OK
        text(d, (text_x, y-12), kind, DISPLAY_B(22), fill=name_color, anchor="la")
        # distance, right side
        text(d, (sx2-30, y-12), distance, DISPLAY_B(22), fill=INK, anchor="ra")
        unit_w = tw(d, distance, DISPLAY_B(22))
        # target line
        text(d, (text_x, y+22), "TARGET", MONO(10), fill=SLATE, anchor="la")
        tw1 = tw(d, "TARGET   ", MONO(10))
        text(d, (text_x+tw1, y+22), target_left, MONO(11), fill=GREEN_OK, anchor="la")
        tw2 = tw(d, target_left+"   ", MONO(11))
        text(d, (text_x+tw1+tw2, y+22), "·  " + target_right, MONO(11), fill=target_right_color, anchor="la")
        # note (italic)
        text(d, (text_x, y+44), note, SERIF_IT(15), fill=SLATE, anchor="la")
        # sub-annotation (small mono)
        if sub_annotation:
            text(d, (text_x, y+66), sub_annotation, MONO(10), fill=SLATE, anchor="la")

    # Step 1 — Warm-up
    s1_y = tl_top + 30
    step_node(s1_y, filled=False, color=GREEN_OK)
    step_block(s1_y, "WARM-UP", "2.0 mi",
               "6:26 – 7:38 / mi", GREEN_OK, "EASY",
               "conversational pace")

    # Step 2 — Active
    s2_y = s1_y + 170
    step_node(s2_y, filled=True, color=AMBER)
    step_block(s2_y, "ACTIVE", "7.0 mi",
               "5:29 / mi", AMBER, "MP",
               "goal marathon race pace",
               sub_annotation="YOUR MP  5:32  ·  −1%  TODAY",
               accent=True)

    # Step 3 — Cool-down
    s3_y = s2_y + 200
    step_node(s3_y, filled=False, color=GREEN_OK)
    step_block(s3_y, "COOL-DOWN", "2.0 mi",
               "6:26 – 7:38 / mi", GREEN_OK, "EASY",
               "conversational pace")

    # Subtle FIN. annotation in negative space below
    text(d, ((sx1+sx2)//2, sy2 - 130),
         "FIN.   —   sheet may be dismissed",
         MONO(10), fill=SLATE_LIGHT, anchor="ma")

    # Tab bar (Trends still highlighted to keep the set's continuity, but this
    # screen actually launches from TRAIN — so highlight TRAIN here)
    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=1)
    return img

# ---------------------------------------------------------------------------
# Volume chart variants (used inside page_6)
# ---------------------------------------------------------------------------
def _draw_chart_A(d, x1, y1, x2, y2):
    """Horizontal zone bars with pace ranges. The Plate-06-v3 chart."""
    zones = [
        ("EASY",      "6:30 – 7:30/MI",  28.3, 60, GREEN_OK),
        ("STEADY",    "6:00 – 6:30/MI",  11.4, 24, SLATE),
        ("THRESHOLD", "5:50 – 6:00/MI",   4.2,  9, AMBER),
        ("VO2",       "5:25 – 5:40/MI",   2.1,  4, INK),
        ("RACE",      "5:42 / MI",        1.2,  3, INK),
    ]
    label_w = 78
    pace_w = 116
    miles_w = 50
    pct_w = 32
    bar_x1 = x1 + label_w + pace_w
    bar_x2 = x2 - miles_w - pct_w - 6
    max_miles = max(z[2] for z in zones)
    bar_h = 12
    gap = 12
    total_h = len(zones)*(bar_h + gap)
    start_y = y1 + (y2 - y1 - total_h)/2
    for i,(name, pace, miles, pct, col) in enumerate(zones):
        row_y = start_y + i*(bar_h + gap)
        text(d, (x1, row_y + bar_h/2 - 6), name, MONO(10), fill=INK, anchor="la")
        text(d, (x1 + label_w, row_y + bar_h/2 - 6), pace, MONO(9), fill=SLATE_LIGHT, anchor="la")
        d.rectangle([bar_x1, row_y, bar_x2, row_y + bar_h], fill=BONE, outline=None)
        bw = (miles / max_miles) * (bar_x2 - bar_x1)
        d.rectangle([bar_x1, row_y, bar_x1 + bw, row_y + bar_h], fill=col, outline=None)
        text(d, (bar_x2 + 6, row_y + bar_h/2 - 6), f"{miles:.1f}MI", MONO(10), fill=INK, anchor="la")
        text(d, (x2, row_y + bar_h/2 - 6), f"{pct}%", MONO(10), fill=SLATE_LIGHT, anchor="ra")

def _draw_chart_B(d, x1, y1, x2, y2):
    """Stacked weekly trend — 8 weeks across, segmented by zone."""
    weeks = [
        (24, 8, 2, 1, 0),
        (28, 9, 3, 1, 0),
        (26, 10, 3, 2, 1),
        (30, 11, 3, 2, 1),
        (32, 12, 4, 2, 1),
        (34, 11, 4, 2, 1),
        (36, 12, 4, 2, 1),
        (28.3, 11.4, 4.2, 2.1, 1.2),
    ]
    zone_colors = [GREEN_OK, SLATE, AMBER, INK, INK]
    n = len(weeks)
    # legend
    leg_y = y1 + 4
    leg_x = x1
    for label, col in [("EASY", GREEN_OK), ("STEADY", SLATE), ("THRESH", AMBER), ("VO2", INK)]:
        d.rectangle([leg_x, leg_y, leg_x+8, leg_y+8], fill=col)
        text(d, (leg_x + 12, leg_y - 2), label, MONO(9), fill=SLATE, anchor="la")
        leg_x += tw(d, label, MONO(9)) + 24
    # max miles label, top right
    max_total = max(sum(w) for w in weeks)
    text(d, (x2, leg_y - 2), f"{int(max_total)} MI / WK", MONO(9), fill=SLATE_LIGHT, anchor="ra")

    pad_top = 28
    pad_bot = 28
    pad_left = 0
    pad_right = 0
    base = y2 - pad_bot
    chart_top = y1 + pad_top
    cw = (x2 - x1 - pad_left - pad_right) / n
    bw = cw * 0.5
    hairline(d, x1, base, x2, base, fill=HAIR)
    for i, w in enumerate(weeks):
        bx1 = x1 + pad_left + i*cw + (cw - bw)/2
        bx2 = bx1 + bw
        cur_y = base
        for j, v in enumerate(w):
            seg_h = (v / max_total) * (base - chart_top)
            d.rectangle([bx1, cur_y - seg_h, bx2, cur_y], fill=zone_colors[j])
            cur_y -= seg_h
        # week labels — first, middle, current
        if i in [0, n//2, n-1]:
            lab = "8W AGO" if i == 0 else ("4W AGO" if i == n//2 else "NOW")
            color = AMBER if i == n-1 else SLATE
            text(d, ((bx1+bx2)/2, base + 4), lab, MONO(9), fill=color, anchor="ma")
        # total mile label above the current bar only
        if i == n-1:
            total = sum(w)
            text(d, ((bx1+bx2)/2, cur_y - 12), f"{total:.1f}", MONO(9), fill=AMBER, anchor="ma")

def _draw_chart_C(d, x1, y1, x2, y2):
    """Day-of-Week rhythm — 7 bars Mon-Sun, segmented by zone."""
    days = [
        ("MON", [4, 2, 0, 0, 0],     "done"),
        ("TUE", [3, 4, 1, 0, 0],     "done"),
        ("WED", [2, 5, 3, 1, 0],     "today"),
        ("THU", [0, 0, 0, 0, 0],     "ahead"),
        ("FRI", [6, 0, 0, 0, 0],     "ahead"),
        ("SAT", [14, 4, 1, 0, 1],    "ahead"),
        ("SUN", [0, 0, 0, 0, 0],     "ahead"),
    ]
    zone_colors = [GREEN_OK, SLATE, AMBER, INK, INK]
    n = len(days)
    # legend
    leg_y = y1 + 4
    leg_x = x1
    for label, col in [("EASY", GREEN_OK), ("STEADY", SLATE), ("THRESH", AMBER), ("VO2", INK)]:
        d.rectangle([leg_x, leg_y, leg_x+8, leg_y+8], fill=col)
        text(d, (leg_x + 12, leg_y - 2), label, MONO(9), fill=SLATE, anchor="la")
        leg_x += tw(d, label, MONO(9)) + 24
    text(d, (x2, leg_y - 2), "47 MI PLANNED", MONO(9), fill=SLATE_LIGHT, anchor="ra")

    pad_top = 28
    pad_bot = 28
    base = y2 - pad_bot
    chart_top = y1 + pad_top
    cw = (x2 - x1) / n
    bw = cw * 0.6
    max_total = max(sum(d_[1]) for d_ in days)
    hairline(d, x1, base, x2, base, fill=HAIR)
    for i, (lab, vals, state) in enumerate(days):
        bx1 = x1 + i*cw + (cw - bw)/2
        bx2 = bx1 + bw
        cx = (bx1 + bx2)/2
        text(d, (cx, base + 4), lab, MONO(9),
             fill=AMBER if state=="today" else SLATE, anchor="ma")
        if sum(vals) == 0:
            d.line([(bx1+4, base-3),(bx2-4, base-3)], fill=SLATE_LIGHT, width=1)
            text(d, (cx, base - 18), "REST", MONO(8), fill=SLATE_LIGHT, anchor="ma")
            continue
        cur_y = base
        for j, v in enumerate(vals):
            seg_h = (v / max_total) * (base - chart_top)
            col = zone_colors[j]
            d.rectangle([bx1, cur_y - seg_h, bx2, cur_y], fill=col)
            cur_y -= seg_h
        # total above
        total = sum(vals)
        col = AMBER if state == "today" else SLATE
        text(d, (cx, cur_y - 14), f"{total}", MONO(9), fill=col, anchor="ma")

def _draw_chart_E(d, x1, y1, x2, y2):
    """Pace × Volume Spectrum — continuous density anchored by four reference
    paces: EASY · MP · LT · 5K. Realistic pace range for a sub-3:10 marathoner."""
    # Axis spans realistic training pace for this athlete:
    # 9:00/mi (recovery shuffle) → 5:30/mi (5K-pace work). Seconds per mile.
    pace_slow = 540   # 9:00/mi
    pace_fast = 330   # 5:30/mi

    pad_top = 44   # room for two-line anchor labels above the curve
    pad_bot = 22   # axis tick labels
    pad_lr  = 14
    chart_x1 = x1 + pad_lr
    chart_x2 = x2 - pad_lr
    chart_y1 = y1 + pad_top
    chart_y2 = y2 - pad_bot

    def x_for_pace(p):
        t = (pace_slow - p) / (pace_slow - pace_fast)
        return chart_x1 + t * (chart_x2 - chart_x1)

    def gauss(p, mu, sigma, h):
        return h * math.exp(-((p - mu) ** 2) / (2 * sigma ** 2))

    # Realistic distribution for a sub-3:10 marathoner mid-block.
    # Most volume is recovery/easy. MP-day has a tight hump.
    # LT and 5K-pace work are present but small.
    def vol_at(p):
        return (
            gauss(p, 510, 32, 28.3) +   # EASY centered at 8:30, broad
            gauss(p, 435, 14,  8.0) +   # MP work at 7:15 (the 11-mi MP run)
            gauss(p, 395,  9,  4.2) +   # LT at 6:35 (threshold tempo)
            gauss(p, 360,  8,  2.1)     # 5K pace at 6:00 (intervals)
        )

    samples = []
    p = pace_slow
    while p >= pace_fast:
        samples.append((x_for_pace(p), vol_at(p), p))
        p -= 1
    max_v = max(v for _, v, _ in samples)
    chart_h = chart_y2 - chart_y1
    poly_top = [(x, chart_y2 - (v / max_v) * chart_h * 0.85) for x, v, _ in samples]

    # Color the filled area in pace-segmented bands. Boundaries land between
    # the four anchors so each anchor sits inside its color region.
    # > 7:45 easy (green) — 6:55–7:45 MP zone (slate) — 6:15–6:55 LT (amber)
    # — 5:30–6:15 5K (ink)
    def color_for_pace(p):
        if p > 465: return GREEN_OK   # easy
        if p > 415: return SLATE      # MP zone
        if p > 375: return AMBER      # LT zone
        return INK                    # 5K and faster

    for i in range(len(samples) - 1):
        (xa, ya), (xb, yb) = poly_top[i], poly_top[i+1]
        pa, pb = samples[i][2], samples[i+1][2]
        col = color_for_pace((pa + pb) / 2)
        d.polygon([(xa, ya), (xb, yb), (xb, chart_y2), (xa, chart_y2)], fill=col)

    d.line(poly_top, fill=INK, width=1)
    hairline(d, chart_x1, chart_y2, chart_x2, chart_y2, fill=HAIR)

    # ── Four anchors — vertical hairlines + two-line labels above ──
    anchors = [
        (510, "EASY", "8:30", GREEN_OK),
        (435, "MP",   "7:15", SLATE),
        (395, "LT",   "6:35", AMBER),
        (360, "5K",   "6:00", INK),
    ]
    for pace_sec, lab, pace_str, col in anchors:
        x = x_for_pace(pace_sec)
        # vertical line through the chart
        d.line([(x, chart_y1), (x, chart_y2)], fill=SLATE_LIGHT, width=1)
        # short colored tick above the chart
        d.line([(x, chart_y1 - 6), (x, chart_y1)], fill=col, width=2)
        # two-line label: anchor name (colored) + pace (slate) below
        text(d, (x, chart_y1 - 32), lab, MONO(9), fill=col, anchor="ma")
        text(d, (x, chart_y1 - 18), pace_str, MONO(8), fill=SLATE, anchor="ma")

    # X-axis pace labels (round numbers; no SLOWER/FASTER hint — it's obvious)
    for pace_sec, lab in [(540, "9:00"), (480, "8:00"), (420, "7:00"), (360, "6:00")]:
        x = x_for_pace(pace_sec)
        text(d, (x, chart_y2 + 6), lab, MONO(9), fill=SLATE_LIGHT, anchor="ma")

def _draw_chart_D(d, x1, y1, x2, y2):
    """This week vs last — paired bars per zone with numeric delta."""
    zones = [
        ("EASY",   28.3, 26.1, GREEN_OK),
        ("STEADY", 11.4,  9.8, SLATE),
        ("THRESH",  4.2,  3.6, AMBER),
        ("VO2",     2.1,  1.4, INK),
        ("RACE",    1.2,  1.2, INK),
    ]
    label_w = 56
    delta_w = 44
    bar_x1 = x1 + label_w
    bar_x2 = x2 - delta_w - 8
    max_v = max(max(z[1], z[2]) for z in zones)
    bar_h = 8
    pair_gap = 4
    row_gap = 10
    pair_h = 2*bar_h + pair_gap
    total_h = len(zones) * (pair_h + row_gap)
    start_y = y1 + (y2 - y1 - total_h)/2 + 6

    text(d, (bar_x1, start_y - 22), "THIS WEEK", MONO(9), fill=INK, anchor="la")
    text(d, (bar_x1 + 90, start_y - 22), "LAST WEEK", MONO(9), fill=SLATE_LIGHT, anchor="la")
    text(d, (x2, start_y - 22), "Δ MILES", MONO(9), fill=SLATE, anchor="ra")

    for i, (n, this_w, last_w, c) in enumerate(zones):
        ry = start_y + i*(pair_h + row_gap)
        text(d, (x1, ry + pair_h/2 - 6), n, MONO(10), fill=INK, anchor="la")
        bw = (this_w / max_v) * (bar_x2 - bar_x1)
        d.rectangle([bar_x1, ry, bar_x1 + bw, ry + bar_h], fill=c)
        bw2 = (last_w / max_v) * (bar_x2 - bar_x1)
        faint = tuple(int(v + (244 - v) * 0.55) for v in c)
        d.rectangle([bar_x1, ry + bar_h + pair_gap, bar_x1 + bw2, ry + 2*bar_h + pair_gap], fill=faint)
        delta = this_w - last_w
        sign = "+" if delta >= 0 else ""
        delta_color = GREEN_OK if delta > 0 else (SLATE if abs(delta) < 0.1 else AMBER)
        text(d, (x2, ry + pair_h/2 - 6),
             f"{sign}{delta:.1f}", MONO(10), fill=delta_color, anchor="ra")

# ---------------------------------------------------------------------------
# PAGE 6 — TRAINING TAB (REDESIGN OF EXISTING DASHBOARD)
# ---------------------------------------------------------------------------
def page_6(chart_style="A", fig_no=6):
    """Training tab mockup, parameterized on volume chart style.
       chart_style ∈ {"A","B","C","D"} maps to:
         A — Horizontal Zone Bars (distribution)
         B — Stacked Weekly Trend (trajectory + composition)
         C — Day-of-Week Rhythm (this-week shape)
         D — This Week vs Last (direct comparison)
    """
    style_titles = {
        "A": ("OPTION A", "Horizontal Zone Bars",
              "Where the miles went — distribution by zone."),
        "B": ("OPTION B", "Stacked Weekly Trend",
              "Volume trajectory + composition over 8 weeks."),
        "C": ("OPTION C", "Day-of-Week Rhythm",
              "The shape of this week, day by day."),
        "D": ("OPTION D", "This Week vs Last",
              "Direct comparison with numeric deltas."),
        "E": ("OPTION E", "Pace × Volume Spectrum",
              "Continuous pace axis, anchored by reference paces."),
    }
    eyebrow, title, blurb = style_titles[chart_style]
    img, d = new_page()
    page_chrome(d, fig_no,
                eyebrow,
                title,
                ["The same training tab, with one volume-chart variant.",
                 blurb])
    sx1, sy1, sx2, sy2 = draw_phone(d)

    y = screen_header(d, sx1, sy1, sx2,
                      "TRAINING  ·  WEEK 09 OF 16",
                      "Marathon block",
                      week_label="MON · APR 27")

    inner_l = sx1 + 30
    inner_r = sx2 - 30

    # ── GOAL CONTEXT (compact one-liner — context, not action) ─
    text(d, (inner_l, y), "GOAL", MONO(11), fill=AMBER, anchor="la")
    text(d, (inner_l + 38, y),
         "Sub-3:10  ·  May 18  ·  47 days out",
         MONO(12), fill=INK, anchor="la")
    text(d, (inner_r, y), "EDIT", MONO(11), fill=SLATE, anchor="ra")
    arrow_up_right(d, inner_r - 4, y - 2, size=8, fill=SLATE, width=1)

    # ── WEEKLY MILEAGE ─────────────────────────────────────────
    y_mi = y + 36
    hairline(d, inner_l, y_mi, inner_r, y_mi, fill=HAIR)

    text(d, (inner_l, y_mi + 16), "WEEKLY MILEAGE", MONO(11), fill=SLATE, anchor="la")
    # WEEK | MONTH toggle, right aligned
    rp_x = inner_r
    for label, active in [("MONTH", False), ("WEEK", True)]:
        w = tw(d, label, MONO(10)) + 16
        rx2 = rp_x; rx1 = rp_x - w
        if active:
            rounded_box(d, rx1, y_mi + 8, rx2, y_mi + 28, 6,
                        fill=(248,232,222), outline=None)
        text(d, (rx1 + w/2, y_mi + 14), label, MONO(10),
             fill=AMBER if active else SLATE, anchor="ma")
        rp_x -= (w + 4)

    # Big number + comparison
    text(d, (inner_l, y_mi + 38), "47.2", DISPLAY_B(56), fill=INK, anchor="la")
    big_w = tw(d, "47.2", DISPLAY_B(56))
    text(d, (inner_l + big_w + 8, y_mi + 78), "MILES", MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_l, y_mi + 110),
         "+8%  VS LAST WEEK",
         MONO(11), fill=GREEN_OK, anchor="la")
    text(d, (inner_l + tw(d, "+8%  VS LAST WEEK   ", MONO(11)), y_mi + 110),
         "·  188 MI  THIS MONTH",
         MONO(11), fill=SLATE, anchor="la")

    # 4-week sparkline bars on the right side of the weekly mileage block
    spark_x1 = inner_r - 120
    spark_x2 = inner_r
    spark_top = y_mi + 44
    spark_bot = y_mi + 96
    spark_vals = [38, 42, 44, 47.2]  # last 4 weeks
    spark_max = max(spark_vals)
    bw_each = (spark_x2 - spark_x1 - 18) / 4
    for i,v in enumerate(spark_vals):
        bx1 = spark_x1 + i*(bw_each + 6)
        bx2 = bx1 + bw_each
        h = (v / spark_max) * (spark_bot - spark_top - 18)
        col = AMBER if i == 3 else SLATE_LIGHT
        d.rectangle([bx1, spark_bot - h, bx2, spark_bot], fill=col)
    text(d, (spark_x1, spark_bot + 6), "LAST 4 WEEKS", MONO(9), fill=SLATE_LIGHT, anchor="la")

    # ── COACH'S PLAN · WEEK 09 ─────────────────────────────────
    y_plan = y_mi + 138
    hairline(d, inner_l, y_plan, inner_r, y_plan, fill=HAIR)
    text(d, (inner_l, y_plan + 16), "COACH'S PLAN  ·  WEEK 09", MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_r, y_plan + 16),
         "4 OF 7  ·  27 / 47 MI",
         MONO(11), fill=SLATE, anchor="ra")

    strip_y = y_plan + 44
    days = [
        ("MON", "6",  "EASY",  "done"),
        ("TUE", "8",  "TEMPO", "done"),
        ("WED", "11", "MP",    "today"),
        ("THU", "—",  "REST",  "ahead"),
        ("FRI", "6",  "EASY",  "ahead"),
        ("SAT", "20", "LONG",  "ahead"),
        ("SUN", "—",  "REST",  "ahead"),
    ]
    n = len(days)
    cell_w = (inner_r - inner_l) / n
    node_y = strip_y + 30
    hairline(d, inner_l + cell_w/2, node_y, inner_r - cell_w/2, node_y, fill=HAIR)

    for i,(day,dist,kind,state) in enumerate(days):
        cx = inner_l + i*cell_w + cell_w/2
        text(d, (cx, strip_y), day, MONO(10), fill=SLATE, anchor="ma")
        r = 8
        if state == "done":
            d.ellipse([cx-r, node_y-r, cx+r, node_y+r], fill=INK)
        elif state == "today":
            d.ellipse([cx-r-2, node_y-r-2, cx+r+2, node_y+r+2], outline=AMBER, width=1)
            d.ellipse([cx-r, node_y-r, cx+r, node_y+r], fill=AMBER)
        else:
            d.ellipse([cx-r, node_y-r, cx+r, node_y+r], fill=PAPER, outline=SLATE_LIGHT, width=2)
        dist_color = AMBER if state == "today" else INK
        text(d, (cx, node_y + 18), dist, DISPLAY_B(18), fill=dist_color, anchor="ma")
        text(d, (cx, node_y + 44), kind, MONO(9), fill=AMBER if state=="today" else SLATE, anchor="ma")

    # ── PACE & VOLUME — chart varies by chart_style ────────────
    y_pv = strip_y + 96
    hairline(d, inner_l, y_pv, inner_r, y_pv, fill=HAIR)

    text(d, (inner_l, y_pv + 16), "PACE  &  VOLUME", MONO(11), fill=SLATE, anchor="la")
    rp_x = inner_r
    # Toggle style depends on chart variant
    toggle_pairs = [("MONTH", False), ("WEEK", True)]
    if chart_style == "B":
        toggle_pairs = [("MONTH", False), ("8 WEEKS", True)]
    elif chart_style == "D":
        toggle_pairs = [("MONTH", False), ("VS LAST", True)]
    elif chart_style == "E":
        toggle_pairs = [("MONTH", False), ("WEEK", True)]
    for label, active in toggle_pairs:
        w = tw(d, label, MONO(10)) + 16
        rx2 = rp_x; rx1 = rp_x - w
        if active:
            rounded_box(d, rx1, y_pv + 8, rx2, y_pv + 28, 6,
                        fill=(248,232,222), outline=None)
        text(d, (rx1 + w/2, y_pv + 14), label, MONO(10),
             fill=AMBER if active else SLATE, anchor="ma")
        rp_x -= (w + 4)

    chart_top_y = y_pv + 44
    chart_bot_y = chart_top_y + 156   # all variants given equal vertical room

    if chart_style == "A":
        _draw_chart_A(d, inner_l, chart_top_y, inner_r, chart_bot_y)
    elif chart_style == "B":
        _draw_chart_B(d, inner_l, chart_top_y, inner_r, chart_bot_y)
    elif chart_style == "C":
        _draw_chart_C(d, inner_l, chart_top_y, inner_r, chart_bot_y)
    elif chart_style == "D":
        _draw_chart_D(d, inner_l, chart_top_y, inner_r, chart_bot_y)
    elif chart_style == "E":
        _draw_chart_E(d, inner_l, chart_top_y, inner_r, chart_bot_y)

    # ── TRAINING LOG ──────────────────────────────────────────
    y_log = chart_bot_y + 12
    hairline(d, inner_l, y_log, inner_r, y_log, fill=HAIR)
    text(d, (inner_l, y_log + 16), "TRAINING LOG  ·  RECENT", MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_r, y_log + 16), "VIEW ALL", MONO(11), fill=SLATE, anchor="ra")
    arrow_up_right(d, inner_r - 2, y_log + 14, size=8, fill=SLATE, width=1)

    # Three log entries
    entries = [
        ("APR 26  ·  LONG RUN  ·  18 MI",
         "“Felt strong through 14, started to fade on the hills…”",
         "2:34", True, GREEN_OK, "POSITIVE"),
        ("APR 24  ·  TEMPO  ·  8 MI",
         "“Hit the prescribed paces cleanly. Slight headwind on the way…”",
         "1:12", True, GREEN_OK, "ENERGIZED"),
        ("APR 22  ·  EASY  ·  6 MI",
         "“Legs heavy, took it easy and kept HR low. Tomorrow should be…”",
         None, False, AMBER, "TIRED"),
    ]
    log_y = y_log + 50
    row_h = 78
    for i,(meta, snippet, audio_dur, has_audio, mood_col, mood_label) in enumerate(entries):
        ry = log_y + i*row_h
        # Eyebrow row
        text(d, (inner_l, ry), meta, MONO(10), fill=SLATE, anchor="la")
        # right side: audio button OR text-only
        if has_audio:
            # tiny play triangle + mono duration
            play_x = inner_r - tw(d, audio_dur, MONO(10)) - 18
            d.polygon([(play_x, ry-2),(play_x, ry+10),(play_x+9, ry+4)], fill=AMBER)
            text(d, (inner_r, ry), audio_dur, MONO(10), fill=AMBER, anchor="ra")
        else:
            text(d, (inner_r, ry), "TEXT ONLY", MONO(10), fill=SLATE_LIGHT, anchor="ra")
        # snippet (italic serif)
        text(d, (inner_l, ry + 22), snippet, SERIF_IT(13), fill=INK, anchor="la")
        # mood pill bottom-left
        text(d, (inner_l, ry + 50), mood_label, MONO(9), fill=mood_col, anchor="la")
        # divider between entries
        if i < len(entries) - 1:
            hairline(d, inner_l, ry + row_h - 8, inner_r, ry + row_h - 8, fill=HAIR)

    # Tab bar — TRAIN active
    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=1)
    return img

# ---------------------------------------------------------------------------
# PAGE 7 — VOLUME CHART OPTIONS
# ---------------------------------------------------------------------------
def page_7():
    img, d = new_page()
    page_chrome(d, 7,
                "OPTIONS",
                "Volume Charts",
                ["Four ways to show the same data. Pick the one that matches",
                 "the question a runner asks at this point in the screen."])

    # Page is split into a 2×2 grid of chart panels (no phone frame this time —
    # this is a design-options spread).
    grid_l = 110
    grid_r = PAGE_W - 110
    grid_top = 320
    grid_bottom = PAGE_H - 200
    cell_w = (grid_r - grid_l - 30) / 2
    cell_h = (grid_bottom - grid_top - 60) / 2

    panels = [
        ("OPTION A", "Horizontal Zone Bars", "Distribution — where the miles went.",
         "in the mockup today — one row per zone, ranked by volume."),
        ("OPTION B", "Stacked Weekly Trend", "Trend + composition — is volume building?",
         "8 weeks; each bar = one week, segmented by zone color."),
        ("OPTION C", "Day-of-Week Rhythm",  "Cadence — is the week balanced?",
         "7 bars Mon-Sun; segmented by zone or single-color."),
        ("OPTION D", "This Week vs Last",   "Direct comparison — did I match last week?",
         "side-by-side bars per zone with numeric delta."),
    ]

    for i, (eyebrow, title, blurb, sub) in enumerate(panels):
        col = i % 2
        row = i // 2
        x1 = grid_l + col*(cell_w + 30)
        y1 = grid_top + row*(cell_h + 60)
        x2 = x1 + cell_w
        y2 = y1 + cell_h

        # eyebrow + title
        text(d, (x1, y1), eyebrow, MONO(11), fill=AMBER, anchor="la")
        text(d, (x1, y1 + 22), title, DISPLAY_B(28), fill=INK, anchor="la")
        text(d, (x1, y1 + 60), blurb, SERIF_IT(15), fill=INK, anchor="la")
        text(d, (x1, y1 + 84), sub,   MONO(10), fill=SLATE, anchor="la")

        # chart area
        chart_y1 = y1 + 110
        chart_y2 = y2
        rounded_box(d, x1, chart_y1, x2, chart_y2, 10, fill=BONE, outline=HAIR, width=1)

        # render the chart
        if i == 0: render_horizontal_zone_bars(d, x1+16, chart_y1+16, x2-16, chart_y2-16)
        elif i == 1: render_stacked_weekly(d, x1+16, chart_y1+16, x2-16, chart_y2-16)
        elif i == 2: render_dow_rhythm(d, x1+16, chart_y1+16, x2-16, chart_y2-16)
        elif i == 3: render_compare(d, x1+16, chart_y1+16, x2-16, chart_y2-16)

    return img

def render_horizontal_zone_bars(d, x1, y1, x2, y2):
    zones = [("EASY", 28.3, GREEN_OK), ("STEADY", 11.4, SLATE),
             ("THRESH", 4.2, AMBER), ("VO2", 2.1, INK), ("RACE", 1.2, INK)]
    label_w = 60
    pct_w = 36
    bar_x1 = x1 + label_w
    bar_x2 = x2 - pct_w
    max_v = max(z[1] for z in zones)
    bar_h = 12
    gap = 10
    total_h = len(zones) * (bar_h + gap)
    start_y = (y1 + y2 - total_h) / 2
    for i, (n, v, c) in enumerate(zones):
        ry = start_y + i*(bar_h + gap)
        text(d, (x1, ry + bar_h/2 - 6), n, MONO(10), fill=INK, anchor="la")
        d.rectangle([bar_x1, ry, bar_x2, ry + bar_h], fill=BONE)
        bw = (v / max_v) * (bar_x2 - bar_x1)
        d.rectangle([bar_x1, ry, bar_x1 + bw, ry + bar_h], fill=c)
        text(d, (x2, ry + bar_h/2 - 6), f"{v:.1f}MI", MONO(10), fill=SLATE, anchor="ra")

def render_stacked_weekly(d, x1, y1, x2, y2):
    # 8 weeks; each bar segmented by zone
    weeks = [
        # easy, steady, thresh, vo2, race
        (24, 8, 2, 1, 0),
        (28, 9, 3, 1, 0),
        (26, 10, 3, 2, 1),
        (30, 11, 3, 2, 1),
        (32, 12, 4, 2, 1),
        (34, 11, 4, 2, 1),
        (36, 12, 4, 2, 1),
        (28.3, 11.4, 4.2, 2.1, 1.2),
    ]
    zone_colors = [GREEN_OK, SLATE, AMBER, INK, INK]
    n = len(weeks)
    pad_left = 28
    pad_right = 8
    pad_top = 12
    pad_bot = 22
    base = y2 - pad_bot
    chart_top = y1 + pad_top
    cw = (x2 - x1 - pad_left - pad_right) / n
    bw = cw * 0.6
    max_total = max(sum(w) for w in weeks)
    # y-axis tick (just a hairline at top)
    text(d, (x1, chart_top - 6), f"{int(max_total)} MI", MONO(9), fill=SLATE_LIGHT, anchor="la")
    hairline(d, x1 + pad_left - 4, chart_top, x2 - pad_right, chart_top, fill=HAIR)
    hairline(d, x1 + pad_left - 4, base, x2 - pad_right, base, fill=HAIR)
    for i, w in enumerate(weeks):
        bx1 = x1 + pad_left + i*cw + (cw - bw)/2
        bx2 = bx1 + bw
        cur_y = base
        total = sum(w)
        for j, v in enumerate(w):
            seg_h = (v / max_total) * (base - chart_top)
            d.rectangle([bx1, cur_y - seg_h, bx2, cur_y], fill=zone_colors[j])
            cur_y -= seg_h
        # week label, only first/last/current
        if i in [0, n//2, n-1]:
            lab = f"W{i+1}" if i < n-1 else "NOW"
            color = AMBER if i == n-1 else SLATE
            text(d, ((bx1+bx2)/2, base + 4), lab, MONO(9), fill=color, anchor="ma")

def render_dow_rhythm(d, x1, y1, x2, y2):
    days = [
        ("MON", [4, 2, 0, 0, 0], "done"),
        ("TUE", [3, 4, 1, 0, 0], "done"),
        ("WED", [2, 5, 3, 1, 0], "today"),  # MP day
        ("THU", [0, 0, 0, 0, 0], "ahead"),
        ("FRI", [6, 0, 0, 0, 0], "ahead"),
        ("SAT", [14, 4, 1, 0, 1], "ahead"),
        ("SUN", [0, 0, 0, 0, 0], "ahead"),
    ]
    zone_colors = [GREEN_OK, SLATE, AMBER, INK, INK]
    n = len(days)
    pad_left = 8
    pad_right = 8
    pad_top = 12
    pad_bot = 22
    base = y2 - pad_bot
    chart_top = y1 + pad_top
    cw = (x2 - x1 - pad_left - pad_right) / n
    bw = cw * 0.7
    max_total = max(sum(d_[1]) for d_ in days)
    hairline(d, x1 + pad_left, base, x2 - pad_right, base, fill=HAIR)
    for i, (lab, vals, state) in enumerate(days):
        bx1 = x1 + pad_left + i*cw + (cw - bw)/2
        bx2 = bx1 + bw
        cx = (bx1 + bx2)/2
        # day label
        text(d, (cx, base + 4), lab, MONO(9),
             fill=AMBER if state=="today" else SLATE, anchor="ma")
        if sum(vals) == 0:
            # rest day — render a tiny dash above baseline
            d.line([(bx1+4, base-3),(bx2-4, base-3)], fill=SLATE_LIGHT, width=1)
            continue
        cur_y = base
        for j, v in enumerate(vals):
            seg_h = (v / max_total) * (base - chart_top)
            col = zone_colors[j]
            if state == "today" and j == 2:  # highlight MP day
                col = AMBER
            d.rectangle([bx1, cur_y - seg_h, bx2, cur_y], fill=col)
            cur_y -= seg_h

def render_compare(d, x1, y1, x2, y2):
    zones = [
        ("EASY",   28.3, 26.1, GREEN_OK),
        ("STEADY", 11.4,  9.8, SLATE),
        ("THRESH",  4.2,  3.6, AMBER),
        ("VO2",     2.1,  1.4, INK),
        ("RACE",    1.2,  1.2, INK),
    ]
    label_w = 56
    delta_w = 44
    bar_x1 = x1 + label_w
    bar_x2 = x2 - delta_w - 8
    max_v = max(max(z[1], z[2]) for z in zones)
    bar_h = 8
    pair_gap = 4
    row_gap = 12
    pair_h = 2*bar_h + pair_gap
    total_h = len(zones) * (pair_h + row_gap)
    start_y = (y1 + y2 - total_h) / 2

    # legend at top
    text(d, (bar_x1, start_y - 18), "THIS WEEK", MONO(9), fill=INK, anchor="la")
    text(d, (bar_x1 + 90, start_y - 18), "LAST WEEK", MONO(9), fill=SLATE_LIGHT, anchor="la")

    for i, (n, this_w, last_w, c) in enumerate(zones):
        ry = start_y + i*(pair_h + row_gap)
        # zone label
        text(d, (x1, ry + pair_h/2 - 6), n, MONO(10), fill=INK, anchor="la")
        # this week (filled, top)
        bw = (this_w / max_v) * (bar_x2 - bar_x1)
        d.rectangle([bar_x1, ry, bar_x1 + bw, ry + bar_h], fill=c)
        # last week (faint, bottom)
        bw2 = (last_w / max_v) * (bar_x2 - bar_x1)
        # mix to a paler version
        faint = tuple(int(v + (244 - v) * 0.55) for v in c)
        d.rectangle([bar_x1, ry + bar_h + pair_gap, bar_x1 + bw2, ry + 2*bar_h + pair_gap], fill=faint)
        # delta
        delta = this_w - last_w
        sign = "+" if delta >= 0 else ""
        delta_color = GREEN_OK if delta > 0 else (SLATE if abs(delta) < 0.1 else AMBER)
        text(d, (x2, ry + pair_h/2 - 6),
             f"{sign}{delta:.1f}", MONO(10), fill=delta_color, anchor="ra")

# ---------------------------------------------------------------------------
# PAGE 8 — LOG TAB (REDESIGN)
# ---------------------------------------------------------------------------
def page_8():
    img, d = new_page()
    page_chrome(d, 8,
                "RE-TUNING",
                "Log Tab",
                ["The voice journal. Record button stays loud — the rest",
                 "recedes. Mode toggle, linked workout, recent log entries."])
    sx1, sy1, sx2, sy2 = draw_phone(d)

    # Header — eyebrow + title + sidebar marker
    text(d, (sx1+30, sy1+76), "VOICE LOG", MONO(11), fill=AMBER, anchor="la")
    text(d, (sx2-30, sy1+76), "≡", DISPLAY_B(20), fill=SLATE, anchor="ra")

    inner_l = sx1 + 30
    inner_r = sx2 - 30

    # ── Mode toggle: LOG RUN | CHECK IN ─────────────────────
    mode_y = sy1 + 110
    hairline(d, inner_l, mode_y, inner_r, mode_y, fill=HAIR)
    half = (inner_l + inner_r) // 2
    # active (LOG RUN) — amber underline
    text(d, ((inner_l + half) // 2, mode_y + 16), "LOG RUN", MONO(12), fill=AMBER, anchor="ma")
    d.rectangle([(inner_l + half) // 2 - 36, mode_y + 38,
                 (inner_l + half) // 2 + 36, mode_y + 39], fill=AMBER)
    # inactive (CHECK IN)
    text(d, ((half + inner_r) // 2, mode_y + 16), "CHECK IN", MONO(12), fill=SLATE, anchor="ma")
    hairline(d, inner_l, mode_y + 50, inner_r, mode_y + 50, fill=HAIR)

    # ── Title + italic subtitle ─────────────────────────────
    title_y = mode_y + 80
    text(d, (inner_l, title_y), "Log your run.", DISPLAY_B(36), fill=INK, anchor="la")
    text(d, (inner_l, title_y + 50),
         "Tap the button. Speak as you would to a coach.",
         SERIF_IT(15), fill=SLATE, anchor="la")

    # ── Workout context (linked workout) ────────────────────
    wk_y = title_y + 100
    hairline(d, inner_l, wk_y, inner_r, wk_y, fill=HAIR)
    text(d, (inner_l, wk_y + 14), "LINKED TO", MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_r, wk_y + 14), "CHANGE", MONO(10), fill=SLATE, anchor="ra")
    arrow_up_right(d, inner_r - 2, wk_y + 12, size=8, fill=SLATE, width=1)
    text(d, (inner_l, wk_y + 36),
         "Apr 26  ·  6.50 mi  ·  48:08",
         DISPLAY_B(20), fill=INK, anchor="la")
    text(d, (inner_l, wk_y + 66),
         "7:25 / MI   ·   HEALTHKIT",
         MONO(10), fill=SLATE_LIGHT, anchor="la")
    hairline(d, inner_l, wk_y + 92, inner_r, wk_y + 92, fill=HAIR)

    # ── Record button — the loud accent ─────────────────────
    rec_cy = wk_y + 200
    rec_cx = (sx1 + sx2) // 2
    # Outer faint ring (pulse)
    r_outer = 78
    d.ellipse([rec_cx - r_outer, rec_cy - r_outer,
               rec_cx + r_outer, rec_cy + r_outer],
              outline=(232, 191, 165), width=1)
    # Inner ring
    r_mid = 60
    d.ellipse([rec_cx - r_mid, rec_cy - r_mid,
               rec_cx + r_mid, rec_cy + r_mid],
              outline=(232, 159, 110), width=2)
    # Solid coral button
    r_btn = 44
    d.ellipse([rec_cx - r_btn, rec_cy - r_btn,
               rec_cx + r_btn, rec_cy + r_btn],
              fill=AMBER)
    # Inner white dot
    r_dot = 18
    d.ellipse([rec_cx - r_dot, rec_cy - r_dot,
               rec_cx + r_dot, rec_cy + r_dot],
              fill=PAPER)

    text(d, (rec_cx, rec_cy + 110), "TAP TO RECORD",
         MONO(11), fill=SLATE, anchor="ma")

    # ── OR · TYPE NOTES ─────────────────────────────────────
    notes_y = rec_cy + 160
    hairline(d, inner_l, notes_y, inner_r, notes_y, fill=HAIR)
    text(d, (inner_l, notes_y + 14), "OR  ·  TYPE NOTES",
         MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_r, notes_y + 14), "SAVE",
         MONO(11), fill=SLATE_LIGHT, anchor="ra")
    text(d, (inner_l, notes_y + 44),
         "How did your run feel today?",
         SERIF_IT(14), fill=SLATE_LIGHT, anchor="la")

    # ── YOUR LOGS · history feed ────────────────────────────
    log_y = notes_y + 90
    hairline(d, inner_l, log_y, inner_r, log_y, fill=HAIR)
    text(d, (inner_l, log_y + 14), "YOUR LOGS  ·  8 ENTRIES",
         MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_r, log_y + 14), "VIEW ALL",
         MONO(11), fill=SLATE, anchor="ra")
    arrow_up_right(d, inner_r - 2, log_y + 12, size=8, fill=SLATE, width=1)

    # Two log entries (compact preview rows, mockup style)
    entries = [
        ("APR 26  ·  LONG RUN  ·  18 MI",
         "“Felt strong through 14, started to fade on the hills…”",
         "VOICE", AMBER, GREEN_OK, "POSITIVE"),
        ("APR 24  ·  TEMPO  ·  8 MI",
         "“Hit the prescribed paces cleanly. Slight headwind…”",
         "VOICE", AMBER, GREEN_OK, "ENERGIZED"),
    ]
    e_y = log_y + 50
    row_h = 92
    for i, (meta, snip, ind_label, ind_col, mood_col, mood_lab) in enumerate(entries):
        ry = e_y + i * row_h
        text(d, (inner_l, ry), meta, MONO(10), fill=SLATE, anchor="la")
        # right side indicator
        play_x = inner_r - tw(d, ind_label, MONO(10)) - 14
        d.polygon([(play_x, ry-2),(play_x, ry+10),(play_x+9, ry+4)], fill=ind_col)
        text(d, (inner_r, ry), ind_label, MONO(10), fill=ind_col, anchor="ra")
        text(d, (inner_l, ry + 24), snip, SERIF_IT(13), fill=INK, anchor="la")
        text(d, (inner_l, ry + 56), mood_lab, MONO(9), fill=mood_col, anchor="la")
        if i < len(entries) - 1:
            hairline(d, inner_l, ry + row_h - 12, inner_r, ry + row_h - 12, fill=HAIR)

    # Tab bar — LOG active
    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=0)
    return img

# ---------------------------------------------------------------------------
# PAGE 9 — LOG TAB (JOURNAL ENTRIES VARIANT)
# ---------------------------------------------------------------------------
def page_9():
    img, d = new_page()
    page_chrome(d, 9,
                "RE-TUNING",
                "Log Tab · Journal",
                ["Voice log entries restyled as journal pages — bigger dates,",
                 "fuller prose, mood-color rule, room to breathe between entries."])
    sx1, sy1, sx2, sy2 = draw_phone(d)

    # Header
    text(d, (sx1+30, sy1+76), "VOICE LOG", MONO(11), fill=AMBER, anchor="la")
    text(d, (sx2-30, sy1+76), "≡", DISPLAY_B(20), fill=SLATE, anchor="ra")

    inner_l = sx1 + 30
    inner_r = sx2 - 30

    # Mode toggle (same as Plate 08, compact)
    mode_y = sy1 + 110
    hairline(d, inner_l, mode_y, inner_r, mode_y, fill=HAIR)
    half = (inner_l + inner_r) // 2
    text(d, ((inner_l + half) // 2, mode_y + 16), "LOG RUN", MONO(12), fill=AMBER, anchor="ma")
    d.rectangle([(inner_l + half) // 2 - 36, mode_y + 38,
                 (inner_l + half) // 2 + 36, mode_y + 39], fill=AMBER)
    text(d, ((half + inner_r) // 2, mode_y + 16), "CHECK IN", MONO(12), fill=SLATE, anchor="ma")
    hairline(d, inner_l, mode_y + 50, inner_r, mode_y + 50, fill=HAIR)

    # Compact title — keep but smaller, since the page focus is the journal feed
    title_y = mode_y + 70
    text(d, ((inner_l + inner_r) // 2, title_y), "Log your run.",
         DISPLAY_B(28), fill=INK, anchor="ma")
    text(d, ((inner_l + inner_r) // 2, title_y + 38),
         "Tap the button to start your voice memo.",
         SERIF_IT(13), fill=SLATE, anchor="ma")

    # Compact record button (smaller — to leave room for journal feed)
    rec_cy = title_y + 130
    rec_cx = (sx1 + sx2) // 2
    r_outer = 60
    d.ellipse([rec_cx - r_outer, rec_cy - r_outer,
               rec_cx + r_outer, rec_cy + r_outer],
              outline=(232, 191, 165), width=1)
    r_mid = 46
    d.ellipse([rec_cx - r_mid, rec_cy - r_mid,
               rec_cx + r_mid, rec_cy + r_mid],
              outline=(232, 159, 110), width=2)
    r_btn = 34
    d.ellipse([rec_cx - r_btn, rec_cy - r_btn,
               rec_cx + r_btn, rec_cy + r_btn],
              fill=AMBER)
    r_dot = 13
    d.ellipse([rec_cx - r_dot, rec_cy - r_dot,
               rec_cx + r_dot, rec_cy + r_dot],
              fill=PAPER)

    # ── YOUR LOGS — journal entries ─────────────────────────
    feed_y = rec_cy + 110
    hairline(d, inner_l, feed_y, inner_r, feed_y, fill=HAIR)
    text(d, (inner_l, feed_y + 14), "JOURNAL  ·  RECENT",
         MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_r, feed_y + 14), "VIEW ALL",
         MONO(11), fill=SLATE, anchor="ra")
    arrow_up_right(d, inner_r - 2, feed_y + 12, size=8, fill=SLATE, width=1)

    # Three journal entries
    entries = [
        ("TUESDAY",      "APR 16  ·  EASY  ·  8.0 MI",
         "“I went for an easy run today and felt pretty good. My",
         "focus was on recovery, getting ready for the upcoming",
         "race in two weeks. Legs felt heavy at first…”",
         "POSITIVE", GREEN_OK, "VOICE", "2:34", AMBER),
        ("SUNDAY",       "APR 14  ·  EASY  ·  6.36 MI",
         "“Heavy legs again. Took it really easy and kept HR low.",
         "Tomorrow should be a better day. Need to dial in",
         "sleep — only 6 hours last night.”",
         "TIRED",     AMBER,    "VOICE", "1:12", AMBER),
        ("FRIDAY",       "APR 12  ·  RACE  ·  6.50 MI",
         "“Ran the Cap 10K today. It was a tough race with hot,",
         "humid weather and a very hilly course. My pace varied",
         "but I held it together for a respectable finish.”",
         "STRUGGLING", (175, 79, 79), "VOICE", "3:08", AMBER),
    ]
    e_y = feed_y + 56
    row_h = 220
    for i, (day, meta, line1, line2, line3, mood, mood_col, ind, ind_dur, ind_col) in enumerate(entries):
        ry = e_y + i * row_h
        # Vertical mood-color rule on the left (the "page" feel)
        rule_x = inner_l
        d.rectangle([rule_x, ry + 10, rule_x + 2, ry + row_h - 30], fill=mood_col)
        # Indent body content past the rule
        body_l = inner_l + 16
        # Day-of-week eyebrow (serif italic)
        text(d, (body_l, ry), day, DISPLAY_B(20), fill=INK, anchor="la")
        # voice/text indicator on the right
        play_x = inner_r - tw(d, ind, MONO(10)) - tw(d, " · " + ind_dur, MONO(10)) - 16
        d.polygon([(play_x, ry+4),(play_x, ry+16),(play_x+9, ry+10)], fill=ind_col)
        text(d, (inner_r, ry + 6),
             ind + "  ·  " + ind_dur, MONO(10), fill=ind_col, anchor="ra")
        # Date · workout · distance line (mono caps slate)
        text(d, (body_l, ry + 30), meta, MONO(10), fill=SLATE, anchor="la")
        # Body — three italic-serif lines
        text(d, (body_l, ry + 60), line1, SERIF_IT(14), fill=INK, anchor="la")
        text(d, (body_l, ry + 84), line2, SERIF_IT(14), fill=INK, anchor="la")
        text(d, (body_l, ry + 108), line3, SERIF_IT(14), fill=INK, anchor="la")
        # Mood label as quiet footer
        text(d, (body_l, ry + 144), mood, MONO(9), fill=mood_col, anchor="la")
        # Hairline divider between entries
        if i < len(entries) - 1:
            hairline(d, inner_l, ry + row_h - 10, inner_r, ry + row_h - 10, fill=HAIR)

    # Tab bar — LOG active
    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=0)
    return img

# ---------------------------------------------------------------------------
# PAGE 10 — PLAN TAB (REDESIGN)
# ---------------------------------------------------------------------------
def page_10():
    img, d = new_page()
    page_chrome(d, 10,
                "RE-TUNING",
                "Plan Tab",
                ["Calendar-first plan view. Goal at the top as a quiet line,",
                 "pace ladder as a four-column hairline, then the month grid."])
    sx1, sy1, sx2, sy2 = draw_phone(d)

    # Header
    text(d, (sx1+30, sy1+76), "≡", DISPLAY_B(20), fill=SLATE, anchor="la")
    text(d, ((sx1+sx2)//2, sy1+76), "TRAINING PLAN", MONO(11), fill=SLATE, anchor="ma")
    text(d, (sx2-30, sy1+76), "⋯", DISPLAY_B(20), fill=SLATE, anchor="ra")

    inner_l = sx1 + 30
    inner_r = sx2 - 30

    # ── GOAL STRIP ───────────────────────────────────────────
    goal_y = sy1 + 110
    text(d, (inner_l, goal_y), "GOAL  ·  MARATHON", MONO(11), fill=AMBER, anchor="la")
    text(d, (inner_r, goal_y), "EDIT", MONO(11), fill=SLATE, anchor="ra")
    arrow_up_right(d, inner_r - 4, goal_y - 2, size=8, fill=SLATE, width=1)
    text(d, (inner_l, goal_y + 18),
         "Sub-3:10",
         DISPLAY_B(38), fill=INK, anchor="la")
    text(d, (inner_l, goal_y + 70),
         "MAY 18, 2026   ·   47 DAYS OUT",
         MONO(11), fill=SLATE, anchor="la")

    # ── PACE LADDER ──────────────────────────────────────────
    pl_y = goal_y + 110
    hairline(d, inner_l, pl_y, inner_r, pl_y, fill=HAIR)
    text(d, (inner_l, pl_y + 14), "PACE LADDER", MONO(11), fill=SLATE, anchor="la")
    paces = [
        ("EASY", "8:30", GREEN_OK),
        ("MP",   "7:15", SLATE),
        ("LT",   "6:35", AMBER),
        ("5K",   "6:00", INK),
    ]
    pl_row_y = pl_y + 40
    cell_w = (inner_r - inner_l) / len(paces)
    for i, (lab, pace, col) in enumerate(paces):
        cx = inner_l + i*cell_w + cell_w/2
        text(d, (cx, pl_row_y), lab, MONO(10), fill=col, anchor="ma")
        text(d, (cx, pl_row_y + 18), pace, DISPLAY_B(20), fill=INK, anchor="ma")
    for i in range(1, len(paces)):
        x = inner_l + i*cell_w
        d.line([(x, pl_row_y - 4),(x, pl_row_y + 50)], fill=HAIR, width=1)

    # ── COACH NOTE (quiet line) ──────────────────────────────
    note_y = pl_row_y + 80
    hairline(d, inner_l, note_y, inner_r, note_y, fill=HAIR)
    text(d, (inner_l, note_y + 14), "COACH NOTE  ·  WEEK 09 OF 16",
         MONO(11), fill=SLATE, anchor="la")
    arrow_up_right(d, inner_r - 4, note_y + 12, size=8, fill=SLATE, width=1)
    text(d, (inner_l, note_y + 36),
         "“47 mi planned. MP run Wed, long run Sat.”",
         SERIF_IT(14), fill=INK, anchor="la")

    # ── CALENDAR HEADER ──────────────────────────────────────
    cal_y = note_y + 84
    hairline(d, inner_l, cal_y, inner_r, cal_y, fill=HAIR)
    text(d, (inner_l, cal_y + 14), "APRIL 2026", MONO(11), fill=SLATE, anchor="la")
    # toggle: WEEK | MONTH (MONTH active)
    rp_x = inner_r
    for label, active in [("MONTH", True), ("WEEK", False)]:
        w = tw(d, label, MONO(10)) + 16
        rx2 = rp_x; rx1 = rp_x - w
        if active:
            rounded_box(d, rx1, cal_y + 6, rx2, cal_y + 26, 6,
                        fill=(248,232,222), outline=None)
        text(d, (rx1 + w/2, cal_y + 12), label, MONO(10),
             fill=AMBER if active else SLATE, anchor="ma")
        rp_x -= (w + 4)

    # ── MONTHLY CALENDAR GRID ────────────────────────────────
    # M T W T F S S header
    grid_top = cal_y + 50
    days_header = ["M", "T", "W", "T", "F", "S", "S"]
    col_w = (inner_r - inner_l) / 7
    for i, d_lab in enumerate(days_header):
        cx = inner_l + i*col_w + col_w/2
        text(d, (cx, grid_top), d_lab, MONO(10), fill=SLATE, anchor="ma")

    # Synthesize April 2026 (April 1 = Wednesday)
    # Layout: 5 weeks visible
    # Rows: each row is one week; cells contain day number + dot indicator.
    # Status: done | today | scheduled | rest | missed
    grid_body_top = grid_top + 22
    cell_h = 68
    # April 2026 starts Wed (April 1)
    # Week 1: -, -, 1, 2, 3, 4, 5
    # Week 2: 6 7 8 9 10 11 12
    # Week 3: 13 14 15 16 17 18 19
    # Week 4: 20 21 22 23 24 25 26
    # Week 5: 27 28 29 30 - - -
    weeks = [
        [None, None, ("1","done"),  ("2","done"),  ("3","done"),  ("4","done"),  ("5","done")],
        [("6","done"), ("7","done"), ("8","done"), ("9","done"), ("10","done"), ("11","done"), ("12","done")],
        [("13","done"), ("14","done"), ("15","done"), ("16","done"), ("17","done"), ("18","done"), ("19","done")],
        [("20","done"), ("21","done"), ("22","done"), ("23","done"), ("24","done"), ("25","done"), ("26","done")],
        [("27","today"), ("28","sched"), ("29","sched"), ("30","sched"), None, None, None],
    ]
    # Add some variation — make some "missed" / rest days
    weeks[2][3] = ("16","missed")
    weeks[3][2] = ("22","rest")
    weeks[3][4] = ("24","rest")

    for wi, week in enumerate(weeks):
        ry = grid_body_top + wi*cell_h
        # subtle hairline between rows
        if wi > 0:
            hairline(d, inner_l, ry - 4, inner_r, ry - 4, fill=HAIR)
        for di, cell in enumerate(week):
            if cell is None:
                continue
            day_str, status = cell
            cx = inner_l + di*col_w + col_w/2
            # Day number — slate when not today, ink when current/done
            num_color = AMBER if status == "today" else (INK if status == "done" else SLATE)
            text(d, (cx, ry + 6), day_str, MONO(11), fill=num_color, anchor="ma")
            # Status indicator below number
            ind_y = ry + 32
            r = 6
            if status == "today":
                # outer halo
                d.ellipse([cx-r-3, ind_y-r-3, cx+r+3, ind_y+r+3], outline=AMBER, width=1)
                d.ellipse([cx-r, ind_y-r, cx+r, ind_y+r], fill=AMBER)
            elif status == "done":
                d.ellipse([cx-r, ind_y-r, cx+r, ind_y+r], fill=INK)
            elif status == "sched":
                d.ellipse([cx-r, ind_y-r, cx+r, ind_y+r], fill=PAPER, outline=SLATE_LIGHT, width=2)
            elif status == "missed":
                d.ellipse([cx-r, ind_y-r, cx+r, ind_y+r], fill=PAPER, outline=SLATE_LIGHT, width=2)
                # strike through
                d.line([(cx-r-2, ind_y+r+1),(cx+r+2, ind_y-r-1)], fill=SLATE, width=1)
            elif status == "rest":
                # short dash
                d.line([(cx-5, ind_y),(cx+5, ind_y)], fill=SLATE_LIGHT, width=1)

    # Bottom legend strip
    leg_y = grid_body_top + 5*cell_h + 8
    hairline(d, inner_l, leg_y, inner_r, leg_y, fill=HAIR)
    leg_text_y = leg_y + 14
    # Build legend with vector dots inline
    legend_items = [
        ("DONE", INK, "fill"),
        ("TODAY", AMBER, "fill"),
        ("AHEAD", SLATE_LIGHT, "ring"),
        ("REST", SLATE_LIGHT, "dash"),
        ("MISSED", SLATE_LIGHT, "strike"),
    ]
    n_leg = len(legend_items)
    leg_col_w = (inner_r - inner_l) / n_leg
    for i, (lab, col, kind) in enumerate(legend_items):
        cx = inner_l + i*leg_col_w + leg_col_w/2
        # tiny indicator
        rdot = 4
        ix = cx - tw(d, lab, MONO(9))/2 - 12
        iy = leg_text_y + 4
        if kind == "fill":
            d.ellipse([ix-rdot, iy-rdot, ix+rdot, iy+rdot], fill=col)
        elif kind == "ring":
            d.ellipse([ix-rdot, iy-rdot, ix+rdot, iy+rdot], outline=col, width=1)
        elif kind == "dash":
            d.line([(ix-rdot, iy),(ix+rdot, iy)], fill=col, width=1)
        elif kind == "strike":
            d.ellipse([ix-rdot, iy-rdot, ix+rdot, iy+rdot], outline=col, width=1)
            d.line([(ix-rdot-1, iy+rdot+1),(ix+rdot+1, iy-rdot-1)], fill=col, width=1)
        text(d, (cx + 6, leg_text_y), lab, MONO(9), fill=SLATE, anchor="la")

    # Tab bar — PLAN active (last tab)
    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=4)
    return img

# ---------------------------------------------------------------------------
# PAGE 11 — PLAN TAB · MONTH VIEW (workout label + mileage per day)
# ---------------------------------------------------------------------------
def page_11():
    img, d = new_page()
    page_chrome(d, 11,
                "RE-TUNING",
                "Plan Tab · Month",
                ["Full month grid. Each day shows the workout label (Easy /",
                 "Long / Tempo) and its mileage — the shape of the block at a glance."])
    sx1, sy1, sx2, sy2 = draw_phone(d)

    # Header
    text(d, (sx1+30, sy1+76), "≡", DISPLAY_B(20), fill=SLATE, anchor="la")
    text(d, ((sx1+sx2)//2, sy1+76), "TRAINING PLAN", MONO(11), fill=SLATE, anchor="ma")
    text(d, (sx2-30, sy1+76), "⋯", DISPLAY_B(20), fill=SLATE, anchor="ra")

    inner_l = sx1 + 30
    inner_r = sx2 - 30

    # Compact goal one-liner (single row to leave room for the month grid)
    goal_y = sy1 + 110
    text(d, (inner_l, goal_y), "GOAL  ·  MARATHON", MONO(11), fill=AMBER, anchor="la")
    text(d, (inner_l + tw(d, "GOAL  ·  MARATHON  ", MONO(11)), goal_y),
         "Sub-3:10  ·  47 days out",
         MONO(11), fill=INK, anchor="la")
    text(d, (inner_r, goal_y), "EDIT", MONO(11), fill=SLATE, anchor="ra")
    arrow_up_right(d, inner_r - 4, goal_y - 2, size=8, fill=SLATE, width=1)

    # ── CALENDAR HEADER ──────────────────────────────────────
    cal_y = goal_y + 30
    hairline(d, inner_l, cal_y, inner_r, cal_y, fill=HAIR)
    text(d, (inner_l, cal_y + 14), "APRIL 2026  ·  47 MI THIS WEEK",
         MONO(11), fill=SLATE, anchor="la")
    # Toggle — MONTH active for this view
    rp_x = inner_r
    for label, active in [("WEEK", False), ("MONTH", True)]:
        w = tw(d, label, MONO(10)) + 16
        rx2 = rp_x; rx1 = rp_x - w
        if active:
            rounded_box(d, rx1, cal_y + 6, rx2, cal_y + 26, 6,
                        fill=(248,232,222), outline=None)
        text(d, (rx1 + w/2, cal_y + 12), label, MONO(10),
             fill=AMBER if active else SLATE, anchor="ma")
        rp_x -= (w + 4)

    # ── MONTH GRID — each cell shows day · workout label · mileage ──
    grid_top = cal_y + 50
    days_header = ["M", "T", "W", "T", "F", "S", "S"]
    col_w = (inner_r - inner_l) / 7
    for i, d_lab in enumerate(days_header):
        cx = inner_l + i*col_w + col_w/2
        text(d, (cx, grid_top), d_lab, MONO(9), fill=SLATE_LIGHT, anchor="ma")

    grid_body_top = grid_top + 22
    cell_h = 92    # taller cells so workout label has room
    # Full April + first week of May. April 1 = Wednesday.
    # Status: done | today | sched | rest
    # Workout labels are spelled out — TEMPO, LONG, EASY, INTERVALS, MP,
    # PROG (progression), RECOV (recovery), RACE — and shown bigger (10pt
    # mono caps) so they're scannable at a glance.
    weeks_month = [
        # Week 1 (Apr 1 – Apr 5): Apr 1 = Wednesday
        [None, None,
         ("1","EASY","6","done"),     ("2","TEMPO","8","done"),  ("3","EASY","3","done"),
         ("4","EASY","6","done"),     ("5","LONG","14","done")],
        # Week 2 (Apr 6 – 12)
        [("6","RECOV","4","done"),    ("7","TEMPO","8","done"),  ("8","EASY","3","done"),
         ("9","PROG","8","done"),     ("10","EASY","6","done"),  ("11","LONG","16","done"),
         ("12","RACE","6.5","done")],
        # Week 3 (Apr 13 – 19)
        [("13","EASY","6","done"),    ("14","EASY","6","done"),  ("15","TEMPO","8","done"),
         ("16","EASY","8","done"),    ("17","EASY","6","done"),  ("18","LONG","18","done"),
         ("19","","—","rest")],
        # Week 4 (Apr 20 – 26)
        [("20","EASY","6","done"),    ("21","TEMPO","8","done"),  ("22","","—","rest"),
         ("23","PROG","8","done"),    ("24","EASY","6","done"),  ("25","LONG","12","done"),
         ("26","","—","rest")],
        # Week 5 (Apr 27 – May 3) — current
        [("27","EASY","6","today"),   ("28","TEMPO","8","sched"), ("29","EASY","3","sched"),
         ("30","PROG","8","sched"),   ("1","EASY","6","sched"),   ("2","LONG","20","sched"),
         ("3","","—","rest")],
    ]

    for wi, week in enumerate(weeks_month):
        ry = grid_body_top + wi*cell_h
        if wi > 0:
            hairline(d, inner_l, ry - 2, inner_r, ry - 2, fill=HAIR)
        for di, cell in enumerate(week):
            if cell is None:
                continue
            day_str, label, dist, status = cell
            cx = inner_l + di*col_w + col_w/2
            cell_top = ry + 8
            # Colors
            if status == "today":
                day_color, label_color, dist_color = AMBER, AMBER, AMBER
            elif status == "rest":
                day_color, label_color, dist_color = SLATE_LIGHT, SLATE_LIGHT, SLATE_LIGHT
            elif status == "done":
                day_color, label_color, dist_color = SLATE, SLATE, INK
            else:  # sched (future)
                day_color, label_color, dist_color = INK, INK, INK

            # Day number — small mono in top corner
            text(d, (cx, cell_top), day_str, MONO(10), fill=day_color, anchor="ma")
            # Workout label — bigger mono caps with tracking, the focal text
            if label:
                text(d, (cx, cell_top + 22),
                     label, MONO(10), fill=label_color, anchor="ma")
            # Distance — bottom (serif numeral)
            if dist != "—":
                text(d, (cx, cell_top + 44), dist,
                     DISPLAY_B(18), fill=dist_color, anchor="ma")
                text(d, (cx, cell_top + 70), "MI",
                     MONO(8), fill=SLATE_LIGHT, anchor="ma")
            else:
                text(d, (cx, cell_top + 44), "—", MONO(11), fill=SLATE_LIGHT, anchor="ma")
                text(d, (cx, cell_top + 64), "REST",
                     MONO(8), fill=SLATE_LIGHT, anchor="ma")
            # Today underline
            if status == "today":
                d.line([(cx-22, cell_top + 84),(cx+22, cell_top + 84)],
                       fill=AMBER, width=1)

    # Footer note: tap a day to see the full workout
    foot_y = grid_body_top + 5*cell_h + 14
    hairline(d, inner_l, foot_y, inner_r, foot_y, fill=HAIR)
    text(d, ((inner_l + inner_r)//2, foot_y + 16),
         "TAP A DAY FOR FULL WORKOUT",
         MONO(10), fill=SLATE_LIGHT, anchor="ma")

    # Tab bar — PLAN active (last tab)
    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=4)
    return img

# ---------------------------------------------------------------------------
# PAGE 12 — PLAN TAB (DAILY WORKOUT LIST — "PRESCRIPTION PAD")
# ---------------------------------------------------------------------------
def page_12():
    img, d = new_page()
    page_chrome(d, 12,
                "RE-TUNING",
                "Plan Tab · Workout List",
                ["Each day spells out the workout the way a coach would write it —",
                 "name, distance, pace target, structure. Hairline-divided rows."])
    sx1, sy1, sx2, sy2 = draw_phone(d)

    # Header
    text(d, (sx1+30, sy1+76), "≡", DISPLAY_B(20), fill=SLATE, anchor="la")
    text(d, ((sx1+sx2)//2, sy1+76), "TRAINING PLAN", MONO(11), fill=SLATE, anchor="ma")
    text(d, (sx2-30, sy1+76), "⋯", DISPLAY_B(20), fill=SLATE, anchor="ra")

    inner_l = sx1 + 30
    inner_r = sx2 - 30

    # Compact goal one-liner
    goal_y = sy1 + 110
    text(d, (inner_l, goal_y), "GOAL  ·  MARATHON", MONO(11), fill=AMBER, anchor="la")
    text(d, (inner_l + tw(d, "GOAL  ·  MARATHON  ", MONO(11)), goal_y),
         "Sub-3:10  ·  47 days out",
         MONO(11), fill=INK, anchor="la")
    text(d, (inner_r, goal_y), "EDIT", MONO(11), fill=SLATE, anchor="ra")
    arrow_up_right(d, inner_r - 4, goal_y - 2, size=8, fill=SLATE, width=1)

    # Week header
    wk_y = goal_y + 36
    hairline(d, inner_l, wk_y, inner_r, wk_y, fill=HAIR)
    text(d, (inner_l, wk_y + 14), "WEEK 09 OF 16  ·  APR 27 — MAY 3",
         MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_r, wk_y + 14), "47 MI  PLANNED", MONO(11), fill=SLATE, anchor="ra")

    # Toggle (less prominent — just a quiet eyebrow row)
    rp_x = inner_r
    for label, active in [("MONTH", False), ("WEEK", True)]:
        w = tw(d, label, MONO(10)) + 16
        rx2 = rp_x; rx1 = rp_x - w
        if active:
            rounded_box(d, rx1, wk_y + 36, rx2, wk_y + 56, 6,
                        fill=(248,232,222), outline=None)
        text(d, (rx1 + w/2, wk_y + 42), label, MONO(10),
             fill=AMBER if active else SLATE, anchor="ma")
        rp_x -= (w + 4)
    text(d, (inner_l, wk_y + 42), "DAILY", MONO(10), fill=SLATE, anchor="la")

    # ── DAILY WORKOUT LIST ──────────────────────────────────
    list_y = wk_y + 72
    hairline(d, inner_l, list_y, inner_r, list_y, fill=HAIR)

    # Each day row: eyebrow row (day · date · status), title (serif),
    # distance/pace line (mono), structure line (italic serif).
    days = [
        ("MONDAY",    "APR 27", "TODAY",
         "Easy Run", "6 MI",
         "6:30 – 7:30 / mi  ·  conversational pace",
         "Whole run easy. Recovery focus.", AMBER, "today"),
        ("TUESDAY",   "APR 28", "AHEAD",
         "Tempo", "8 MI",
         "5:55 / mi  ·  threshold pace",
         "2 mi warm-up · 5 mi @ tempo · 1 mi cool-down", SLATE, "sched"),
        ("WEDNESDAY", "APR 29", "AHEAD",
         "Easy Run", "3 MI",
         "6:30 – 7:30 / mi",
         "Short shake-out between hard days.", SLATE, "sched"),
        ("THURSDAY",  "APR 30", "AHEAD",
         "Progression", "8 MI",
         "7:00 → 6:00 / mi  ·  build through",
         "2 mi at easy · 5 mi progressing · 1 mi cool-down", SLATE, "sched"),
        ("SATURDAY",  "MAY 2", "MARQUEE",
         "Long Run", "20 MI",
         "7:30 / mi  ·  long-run pace",
         "4 mi warm-up · 12 mi steady · 4 mi cool-down", AMBER, "sched"),
    ]

    e_y = list_y + 16
    row_h = 130
    for i, (day, date, status, title, dist, pace, structure, accent_col, kind) in enumerate(days):
        ry = e_y + i*row_h

        # Eyebrow row — DAY · DATE · STATUS pill on right
        text(d, (inner_l, ry), day, MONO(10), fill=SLATE, anchor="la")
        date_w = tw(d, day + "   ", MONO(10))
        text(d, (inner_l + date_w, ry), "·  " + date,
             MONO(10), fill=SLATE_LIGHT, anchor="la")
        # Status tag on the right
        status_col = AMBER if status in ("TODAY", "MARQUEE") else SLATE_LIGHT
        text(d, (inner_r, ry), status, MONO(10), fill=status_col, anchor="ra")

        # Workout title (serif) + distance on right
        title_color = AMBER if kind == "today" else INK
        text(d, (inner_l, ry + 22), title, DISPLAY_B(22),
             fill=title_color, anchor="la")
        text(d, (inner_r, ry + 22), dist, DISPLAY_B(22),
             fill=title_color, anchor="ra")

        # Pace target line (mono)
        text(d, (inner_l, ry + 60),
             pace, MONO(10), fill=SLATE, anchor="la")

        # Structure (italic serif)
        text(d, (inner_l, ry + 82),
             structure, SERIF_IT(13), fill=SLATE, anchor="la")

        # Hairline divider
        if i < len(days) - 1:
            hairline(d, inner_l, ry + row_h - 16, inner_r, ry + row_h - 16, fill=HAIR)

    # Tab bar — PLAN active
    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=4)
    return img

# ---------------------------------------------------------------------------
# PAGE 13 — PLAN TAB · MONTH (WEEKLY SUMMARY LIST)
# ---------------------------------------------------------------------------
def page_13():
    img, d = new_page()
    page_chrome(d, 13,
                "RE-TUNING",
                "Plan Tab · Month · Variant B",
                ["Each week as a row — total mileage, key sessions, daily",
                 "intensity strip. The block's shape reads at a glance."])
    sx1, sy1, sx2, sy2 = draw_phone(d)

    # Header
    text(d, (sx1+30, sy1+76), "≡", DISPLAY_B(20), fill=SLATE, anchor="la")
    text(d, ((sx1+sx2)//2, sy1+76), "TRAINING PLAN", MONO(11), fill=SLATE, anchor="ma")
    text(d, (sx2-30, sy1+76), "⋯", DISPLAY_B(20), fill=SLATE, anchor="ra")

    inner_l = sx1 + 30
    inner_r = sx2 - 30

    # Compact goal one-liner
    goal_y = sy1 + 110
    text(d, (inner_l, goal_y), "GOAL  ·  MARATHON", MONO(11), fill=AMBER, anchor="la")
    text(d, (inner_l + tw(d, "GOAL  ·  MARATHON  ", MONO(11)), goal_y),
         "Sub-3:10  ·  47 days out",
         MONO(11), fill=INK, anchor="la")
    text(d, (inner_r, goal_y), "EDIT", MONO(11), fill=SLATE, anchor="ra")
    arrow_up_right(d, inner_r - 4, goal_y - 2, size=8, fill=SLATE, width=1)

    # Calendar header
    cal_y = goal_y + 30
    hairline(d, inner_l, cal_y, inner_r, cal_y, fill=HAIR)
    text(d, (inner_l, cal_y + 14), "APRIL 2026  ·  186 MI THIS BLOCK",
         MONO(11), fill=SLATE, anchor="la")
    # MONTH active
    rp_x = inner_r
    for label, active in [("WEEK", False), ("MONTH", True)]:
        w = tw(d, label, MONO(10)) + 16
        rx2 = rp_x; rx1 = rp_x - w
        if active:
            rounded_box(d, rx1, cal_y + 6, rx2, cal_y + 26, 6,
                        fill=(248,232,222), outline=None)
        text(d, (rx1 + w/2, cal_y + 12), label, MONO(10),
             fill=AMBER if active else SLATE, anchor="ma")
        rp_x -= (w + 4)

    # ── 5 WEEKLY ROWS ────────────────────────────────────────
    # Each row contains:
    #   - Week label + dates  (eyebrow)
    #   - Total mileage (big serif on the right)
    #   - Key sessions line (italic serif): "Long 20 · Tempo 8"
    #   - 7-mini-bar daily intensity strip
    weeks = [
        ("WEEK 05", "MAR 30 — APR 5", 37,
         "Long 14 · Tempo 8 · Easy 6/6/3", "done",
         [3, 4, 2, 5, 3, 7, 0]),
        ("WEEK 06", "APR 6 — 12",     53,
         "Race 6.5 · Long 16 · Tempo 8 · Prog 8", "done",
         [2, 5, 2, 4, 3, 8, 4]),
        ("WEEK 07", "APR 13 — 19",    52,
         "Long 18 · Tempo 8", "done",
         [3, 3, 5, 4, 3, 9, 0]),
        ("WEEK 08", "APR 20 — 26",    44,
         "Long 12 · Tempo 8 · Prog 8 · 2 rest",   "done",
         [3, 5, 0, 4, 3, 6, 0]),
        ("WEEK 09", "APR 27 — MAY 3", 47,
         "Long 20 · Tempo 8 · Prog 8",   "current",
         [3, 4, 2, 4, 3, 10, 0]),
    ]

    list_y = cal_y + 50
    row_h = 122
    for i, (label, dates, miles, sessions, status, intensities) in enumerate(weeks):
        ry = list_y + i*row_h
        if i > 0:
            hairline(d, inner_l, ry - 2, inner_r, ry - 2, fill=HAIR)

        # Eyebrow row
        eyebrow_color = AMBER if status == "current" else SLATE
        text(d, (inner_l, ry + 12), label, MONO(11), fill=eyebrow_color, anchor="la")
        text(d, (inner_l + tw(d, label + "  ", MONO(11)), ry + 12),
             "·  " + dates, MONO(11), fill=SLATE_LIGHT, anchor="la")
        if status == "current":
            text(d, (inner_r, ry + 12), "THIS WEEK", MONO(10), fill=AMBER, anchor="ra")

        # Big mileage
        text(d, (inner_l, ry + 32), str(miles),
             DISPLAY_B(38), fill=AMBER if status == "current" else INK, anchor="la")
        miles_w = tw(d, str(miles), DISPLAY_B(38))
        text(d, (inner_l + miles_w + 8, ry + 60),
             "MI", MONO(11), fill=SLATE, anchor="la")

        # Key sessions
        text(d, (inner_l + miles_w + 36, ry + 38),
             sessions, SERIF_IT(13), fill=SLATE, anchor="la")
        # daily-intensity hint label
        text(d, (inner_l + miles_w + 36, ry + 60),
             "—— daily volume",
             MONO(9), fill=SLATE_LIGHT, anchor="la")

        # 7-bar daily intensity strip on the right
        strip_w = 140
        strip_x1 = inner_r - strip_w
        strip_y = ry + 80
        bar_w = 14
        gap = 4
        max_int = max(max(intensities), 10)
        for j, v in enumerate(intensities):
            bx1 = strip_x1 + j*(bar_w + gap)
            bx2 = bx1 + bar_w
            base = strip_y + 22
            h = (v / max_int) * 22
            col = AMBER if (status == "current" and j == 0) else (
                SLATE_LIGHT if status != "current" else SLATE)
            if v == 0:
                d.line([(bx1+2, base-2),(bx2-2, base-2)], fill=SLATE_LIGHT, width=1)
            else:
                d.rectangle([bx1, base-h, bx2, base], fill=col)

        # Footer: total / type counts on the left under sessions
        # (already conveyed by sessions — skip)

    # Footer hint
    foot_y = list_y + 5*row_h + 6
    hairline(d, inner_l, foot_y, inner_r, foot_y, fill=HAIR)
    text(d, ((inner_l + inner_r)//2, foot_y + 16),
         "TAP A WEEK FOR DAY-BY-DAY DETAIL",
         MONO(10), fill=SLATE_LIGHT, anchor="ma")

    # Tab bar — PLAN active
    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=4)
    return img

# ---------------------------------------------------------------------------
# PAGE 14 — TRAINING TAB · NARRATIVE REDESIGN
# Mileage · Paces · Volume · Mood
# ---------------------------------------------------------------------------
def page_14():
    img, d = new_page()
    page_chrome(d, 14,
                "RE-TUNING",
                "Training Tab · Narrative",
                ["The training tab as a story — this week's mileage trend,",
                 "pace calibration, volume by zone, and the mood arc."])
    sx1, sy1, sx2, sy2 = draw_phone(d)

    # Header (toolbar)
    text(d, (sx1+30, sy1+76), "≡", DISPLAY_B(20), fill=SLATE, anchor="la")
    text(d, ((sx1+sx2)//2, sy1+76), "TRAINING", MONO(11), fill=SLATE, anchor="ma")
    text(d, (sx2-30, sy1+76), "⋯", DISPLAY_B(20), fill=SLATE, anchor="ra")

    inner_l = sx1 + 30
    inner_r = sx2 - 30

    # ── PAGE TITLE — week + sub ─────────────────────────────
    title_y = sy1 + 110
    text(d, (inner_l, title_y), "WEEK 09 OF 16",
         MONO(11), fill=AMBER, anchor="la")
    text(d, (inner_r, title_y), "MON · APR 27",
         MONO(11), fill=SLATE, anchor="ra")
    text(d, (inner_l, title_y + 22), "Marathon block.",
         DISPLAY_B(28), fill=INK, anchor="la")
    text(d, (inner_l, title_y + 56), "47 days to your goal.",
         SERIF_IT(15), fill=SLATE, anchor="la")

    # ── THIS WEEK NARRATIVE ─────────────────────────────────
    nw_y = title_y + 100
    hairline(d, inner_l, nw_y, inner_r, nw_y, fill=HAIR)
    text(d, (inner_l, nw_y + 14), "THIS WEEK",
         MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_r, nw_y + 14), "VIEW THE PLAN",
         MONO(11), fill=SLATE, anchor="ra")
    arrow_up_right(d, inner_r - 4, nw_y + 12, size=8, fill=SLATE, width=1)

    # AI-generated narrative line (italic serif)
    text(d, (inner_l, nw_y + 38),
         "“Up 8% on volume. Mood trending up. Saturday's",
         SERIF_IT(15), fill=INK, anchor="la")
    text(d, (inner_l, nw_y + 60),
         "20-miler is the marquee — execute it and",
         SERIF_IT(15), fill=INK, anchor="la")
    text(d, (inner_l, nw_y + 82),
         "you're on track.”",
         SERIF_IT(15), fill=INK, anchor="la")

    # ── MILEAGE ─────────────────────────────────────────────
    mi_y = nw_y + 118
    hairline(d, inner_l, mi_y, inner_r, mi_y, fill=HAIR)
    text(d, (inner_l, mi_y + 14), "MILEAGE",
         MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_r, mi_y + 14), "8 WEEKS",
         MONO(11), fill=SLATE_LIGHT, anchor="ra")

    # Big number + comparison
    text(d, (inner_l, mi_y + 38), "47.2", DISPLAY_B(48), fill=INK, anchor="la")
    text(d, (inner_l + tw(d, "47.2", DISPLAY_B(48)) + 8, mi_y + 76),
         "MI", MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_l, mi_y + 98),
         "+8%  VS LAST WEEK   ·   188 MI THIS MONTH",
         MONO(11), fill=GREEN_OK, anchor="la")

    # 8-week bar chart on the right
    chart_x1 = inner_r - 180
    chart_x2 = inner_r
    chart_y1 = mi_y + 38
    chart_y2 = mi_y + 100
    weekly_miles = [28, 32, 36, 30, 38, 42, 46, 47.2]
    bw_each = (chart_x2 - chart_x1 - 24) / len(weekly_miles)
    max_v = max(weekly_miles)
    for i, v in enumerate(weekly_miles):
        bx1 = chart_x1 + i*(bw_each + 2)
        bx2 = bx1 + bw_each
        h = (v / max_v) * (chart_y2 - chart_y1 - 8)
        col = AMBER if i == len(weekly_miles)-1 else SLATE_LIGHT
        d.rectangle([bx1, chart_y2 - h, bx2, chart_y2], fill=col)
    text(d, (chart_x1, chart_y2 + 6), "W1", MONO(8), fill=SLATE_LIGHT, anchor="la")
    text(d, (chart_x2, chart_y2 + 6), "NOW", MONO(8), fill=AMBER, anchor="ra")

    # ── PACES · CALIBRATION ────────────────────────────────
    pc_y = mi_y + 138
    hairline(d, inner_l, pc_y, inner_r, pc_y, fill=HAIR)
    text(d, (inner_l, pc_y + 14), "PACES  ·  CALIBRATION",
         MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_r, pc_y + 14), "ARE YOU HITTING TARGETS?",
         MONO(11), fill=SLATE_LIGHT, anchor="ra")

    # 4 pace rows with target vs actual
    paces = [
        ("EASY",      "7:00 – 7:30 / mi", "7:25 / mi avg", "ON TARGET",   GREEN_OK),
        ("MP",        "7:15 / mi",        "7:13 / mi (1 run)", "ON TARGET", GREEN_OK),
        ("THRESHOLD", "5:55 / mi",        "5:58 / mi (1 run)", "ON TARGET", GREEN_OK),
        ("5K",        "5:30 / mi",        "—",                  "NOT HIT YET",   SLATE_LIGHT),
    ]
    pcr_y = pc_y + 44
    row_h = 38
    for i, (zone, target, actual, tag, tag_col) in enumerate(paces):
        ry = pcr_y + i*row_h
        # Zone label (mono caps)
        text(d, (inner_l, ry + 6), zone, MONO(10), fill=INK, anchor="la")
        # Target (mono slate-light, indented)
        text(d, (inner_l + 80, ry + 6), target, MONO(10), fill=SLATE, anchor="la")
        # Actual (display serif numeral)
        text(d, (inner_l + 220, ry + 4), actual, MONO(10), fill=INK, anchor="la")
        # Tag on the right
        text(d, (inner_r, ry + 6), tag, MONO(9), fill=tag_col, anchor="ra")
        # Hairline between rows
        if i < len(paces) - 1:
            hairline(d, inner_l, ry + 24, inner_r, ry + 24, fill=HAIR)

    # ── VOLUME BY ZONE ──────────────────────────────────────
    vz_y = pcr_y + len(paces)*row_h + 12
    hairline(d, inner_l, vz_y, inner_r, vz_y, fill=HAIR)
    text(d, (inner_l, vz_y + 14), "VOLUME  ·  BY ZONE THIS WEEK",
         MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_r, vz_y + 14), "47.2 MI",
         MONO(11), fill=SLATE, anchor="ra")

    # Horizontal bars
    zones = [
        ("EASY",      28.3, 60, GREEN_OK),
        ("STEADY",    11.4, 24, SLATE),
        ("THRESHOLD",  4.2,  9, AMBER),
        ("VO2",        2.1,  4, INK),
        ("RACE",       1.2,  3, INK),
    ]
    bar_y_start = vz_y + 44
    bar_h = 12
    bar_gap = 10
    label_w = 86
    bar_x1 = inner_l + label_w
    bar_x2 = inner_r - 96
    max_miles = max(z[1] for z in zones)

    for i, (name, miles, pct, col) in enumerate(zones):
        ry = bar_y_start + i*(bar_h + bar_gap)
        text(d, (inner_l, ry + bar_h/2 - 6), name, MONO(10), fill=INK, anchor="la")
        d.rectangle([bar_x1, ry, bar_x2, ry + bar_h], fill=BONE, outline=None)
        bw = (miles / max_miles) * (bar_x2 - bar_x1)
        d.rectangle([bar_x1, ry, bar_x1 + bw, ry + bar_h], fill=col, outline=None)
        text(d, (bar_x2 + 6, ry + bar_h/2 - 6),
             f"{miles:.1f}MI", MONO(10), fill=INK, anchor="la")
        text(d, (inner_r, ry + bar_h/2 - 6),
             f"{pct}%", MONO(10), fill=SLATE_LIGHT, anchor="ra")

    # ── MOOD ────────────────────────────────────────────────
    md_y = bar_y_start + len(zones)*(bar_h + bar_gap) + 18
    hairline(d, inner_l, md_y, inner_r, md_y, fill=HAIR)
    text(d, (inner_l, md_y + 14), "MOOD  ·  LAST 14 RUNS",
         MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_r, md_y + 14), "TRENDING UP",
         MONO(11), fill=GREEN_OK, anchor="ra")

    # Strip of 14 mood dots, oldest left → newest right
    moods = [
        "tired", "positive", "positive", "energized",
        "neutral", "tired", "positive", "positive",
        "energized", "tired", "positive", "positive",
        "energized", "positive",
    ]
    mood_colors = {
        "energized": GREEN_OK,
        "positive":  GREEN_OK,
        "neutral":   SLATE,
        "tired":     AMBER,
        "struggling": (175, 79, 79),
    }
    strip_y = md_y + 50
    n = len(moods)
    cw = (inner_r - inner_l) / n
    for i, m in enumerate(moods):
        cx = inner_l + i*cw + cw/2
        col = mood_colors.get(m, SLATE)
        r = 7
        d.ellipse([cx-r, strip_y-r, cx+r, strip_y+r], fill=col)

    # Summary line
    text(d, (inner_l, strip_y + 24),
         "Positive 8  ·  Energized 3  ·  Tired 2  ·  Neutral 1",
         MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_l, strip_y + 44),
         "“Feeling strong” recurring in recent voice memos.",
         SERIF_IT(13), fill=SLATE, anchor="la")

    # Tab bar — TRAIN active
    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=1)
    return img

# ---------------------------------------------------------------------------
# PAGE 15 — TODAY TAB · REDESIGN
# Lead with the next workout, surface goal-vs-fitness mismatch,
# ground every line in real data.
# ---------------------------------------------------------------------------
def page_15():
    img, d = new_page()
    page_chrome(d, 15,
                "RE-TUNING",
                "Today Tab",
                ["What's happening today, did the last one go well, are you",
                 "on track. The three questions a BQ runner actually opens."])
    sx1, sy1, sx2, sy2 = draw_phone(d)

    # Header
    text(d, (sx1+30, sy1+76), "TUESDAY  ·  MAY 5", MONO(11), fill=SLATE, anchor="la")
    text(d, (sx2-30, sy1+76), "⚙", DISPLAY_B(18), fill=SLATE, anchor="ra")

    inner_l = sx1 + 30
    inner_r = sx2 - 30

    # ── TODAY block (most prominent — next workout) ─────────
    today_y = sy1 + 110
    text(d, (inner_l, today_y), "TONIGHT", MONO(11), fill=AMBER, anchor="la")
    text(d, (inner_r, today_y), "REST DAY", MONO(11), fill=SLATE_LIGHT, anchor="ra")
    text(d, (inner_l, today_y + 22),
         "No run today.",
         DISPLAY_B(28), fill=INK, anchor="la")
    text(d, (inner_l, today_y + 60),
         "Tomorrow · Tempo, 8 mi at 7:00/mi.",
         SERIF_IT(15), fill=SLATE, anchor="la")

    # ── CALIBRATION ALERT — the critical missing piece ──────
    cal_y = today_y + 100
    hairline(d, inner_l, cal_y, inner_r, cal_y, fill=HAIR)
    text(d, (inner_l, cal_y + 14), "FITNESS CHECK  ·  GOAL MISMATCH",
         MONO(11), fill=AMBER, anchor="la")
    arrow_up_right(d, inner_r - 4, cal_y + 12, size=8, fill=AMBER, width=1)
    text(d, (inner_l, cal_y + 38),
         "Your training paces suggest a 3:15 marathon.",
         SERIF_IT(14), fill=INK, anchor="la")
    text(d, (inner_l, cal_y + 60),
         "You're targeting 2:20.",
         SERIF_IT(14), fill=INK, anchor="la")

    # Two quiet text actions
    text(d, (inner_l, cal_y + 92), "RECALIBRATE GOAL", MONO(11), fill=AMBER, anchor="la")
    text(d, (inner_l + tw(d, "RECALIBRATE GOAL  ·  ", MONO(11)), cal_y + 92),
         "KEEP CHASING", MONO(11), fill=SLATE, anchor="la")

    # ── LAST RUN — grounded, no metaphors ────────────────────
    lr_y = cal_y + 130
    hairline(d, inner_l, lr_y, inner_r, lr_y, fill=HAIR)
    text(d, (inner_l, lr_y + 14), "LAST RUN  ·  SUN APR 26",
         MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_r, lr_y + 14), "POSITIVE", MONO(11), fill=GREEN_OK, anchor="ra")
    text(d, (inner_l, lr_y + 36),
         "Tempo  ·  6.5 mi",
         DISPLAY_B(22), fill=INK, anchor="la")
    text(d, (inner_r, lr_y + 36),
         "7:25 / mi",
         DISPLAY_B(22), fill=INK, anchor="ra")
    # Grounded coach line — concrete, no metaphor
    text(d, (inner_l, lr_y + 70),
         "“6.5 at 7:25 — solid tempo. Marathon-pace work",
         SERIF_IT(13), fill=SLATE, anchor="la")
    text(d, (inner_l, lr_y + 90),
         "for a 3:15 goal. Easy day tomorrow.”",
         SERIF_IT(13), fill=SLATE, anchor="la")

    # ── THIS WEEK status ────────────────────────────────────
    tw_y = lr_y + 124
    hairline(d, inner_l, tw_y, inner_r, tw_y, fill=HAIR)
    text(d, (inner_l, tw_y + 14), "THIS WEEK", MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_r, tw_y + 14),
         "5 DAYS LEFT", MONO(11), fill=SLATE, anchor="ra")

    # Big number + comparison
    text(d, (inner_l, tw_y + 36), "0.0", DISPLAY_B(38), fill=INK, anchor="la")
    text(d, (inner_l + tw(d, "0.0", DISPLAY_B(38)) + 6, tw_y + 64),
         "/ 47 MI PLANNED", MONO(11), fill=SLATE, anchor="la")

    text(d, (inner_l, tw_y + 86),
         "0 OF 7 RUNS  ·  WEDS TEMPO IS NEXT",
         MONO(11), fill=SLATE, anchor="la")

    # ── PACES · vs TARGETS — the reality check ──────────────
    pc_y = tw_y + 124
    hairline(d, inner_l, pc_y, inner_r, pc_y, fill=HAIR)
    text(d, (inner_l, pc_y + 14), "PACES  ·  vs TARGETS",
         MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_r, pc_y + 14), "LAST 30 DAYS",
         MONO(11), fill=SLATE_LIGHT, anchor="ra")

    # Pace rows — target range vs actual + tag
    paces = [
        ("EASY",       "8:00 – 8:30",      "8:24",  "ON TARGET",        GREEN_OK),
        ("LONG RUN",   "8:30 – 9:00",      "—",     "30 DAYS NO DATA",  AMBER),
        ("TEMPO",      "7:00",             "7:25",  "25s SLOW",         AMBER),
        ("THRESHOLD",  "6:30",             "—",     "NOT HIT YET",      SLATE_LIGHT),
    ]
    pcr_y = pc_y + 44
    row_h = 30
    for i, (zone, target, actual, tag, tag_col) in enumerate(paces):
        ry = pcr_y + i*row_h
        text(d, (inner_l, ry + 6), zone, MONO(10), fill=INK, anchor="la")
        text(d, (inner_l + 90, ry + 6), target + " /MI", MONO(10), fill=SLATE, anchor="la")
        text(d, (inner_l + 200, ry + 6), actual, MONO(10), fill=INK, anchor="la")
        text(d, (inner_r, ry + 6), tag, MONO(9), fill=tag_col, anchor="ra")
        if i < len(paces) - 1:
            hairline(d, inner_l, ry + 18, inner_r, ry + 18, fill=HAIR)

    # ── BOTTOM — race / goal context as a quiet line ────────
    foot_y = pcr_y + len(paces)*row_h + 16
    hairline(d, inner_l, foot_y, inner_r, foot_y, fill=HAIR)
    text(d, (inner_l, foot_y + 16),
         "MARATHON  ·  JUL 25, 2026  ·  11 WEEKS OUT",
         MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_r, foot_y + 16), "VIEW PLAN",
         MONO(11), fill=AMBER, anchor="ra")
    arrow_up_right(d, inner_r - 4, foot_y + 14, size=8, fill=AMBER, width=1)

    # Tab bar — TODAY active (first tab)
    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=0)
    return img

# ---------------------------------------------------------------------------
# PAGE 16 — TODAY TAB · PERFORMANCE COCKPIT
# Heavy data, multi-chart, CTL/ATL/TSB-led. Reads like a control panel.
# ---------------------------------------------------------------------------
def page_16():
    img, d = new_page()
    page_chrome(d, 16,
                "OPTION A",
                "Today · Performance Cockpit",
                ["Information density as personality. Form / Fitness / Load /",
                 "Strain at top. CTL/ATL/TSB curve. Zone shifts vs last 4 weeks."])
    sx1, sy1, sx2, sy2 = draw_phone(d)

    # Header
    text(d, (sx1+30, sy1+76), "TUESDAY  ·  MAY 5", MONO(11), fill=SLATE, anchor="la")
    text(d, (sx2-30, sy1+76), "⚙", DISPLAY_B(18), fill=SLATE, anchor="ra")

    inner_l = sx1 + 30
    inner_r = sx2 - 30

    # ── 4 KPI TILES — Form / Fitness / Load / Strain ─────────
    kpi_y = sy1 + 110
    text(d, (inner_l, kpi_y), "PERFORMANCE", MONO(11), fill=AMBER, anchor="la")
    text(d, (inner_r, kpi_y), "11 WEEKS OUT", MONO(11), fill=SLATE, anchor="ra")
    grid_top = kpi_y + 22
    tile_w = (inner_r - inner_l - 12) / 2
    tile_h = 92

    def kpi_tile(col, row, label, big, sub, sub_color, accent_color=INK, sparkline=None):
        x1 = inner_l + col*(tile_w + 12)
        y1 = grid_top + row*(tile_h + 10)
        # eyebrow
        text(d, (x1 + 12, y1 + 10), label, MONO(9), fill=SLATE, anchor="la")
        # big numeral
        text(d, (x1 + 12, y1 + 28), big, DISPLAY_B(28), fill=accent_color, anchor="la")
        # sub
        text(d, (x1 + 12, y1 + 70), sub, MONO(9), fill=sub_color, anchor="la")
        # tiny sparkline on the right
        if sparkline is not None:
            spx1 = x1 + tile_w - 60
            spx2 = x1 + tile_w - 8
            spy1 = y1 + 26
            spy2 = y1 + 56
            mx = max(sparkline) or 1
            mn = min(sparkline)
            range_ = max(mx - mn, 1)
            pts = []
            for i, v in enumerate(sparkline):
                px = spx1 + (i / (len(sparkline) - 1)) * (spx2 - spx1)
                py = spy2 - ((v - mn) / range_) * (spy2 - spy1)
                pts.append((px, py))
            d.line(pts, fill=accent_color, width=1)
            # endpoint dot
            ex, ey = pts[-1]
            d.ellipse([ex-2, ey-2, ex+2, ey+2], fill=accent_color)
        rounded_box(d, x1, y1, x1+tile_w, y1+tile_h, 10, fill=None, outline=HAIR, width=1)

    # Form (TSB) — fresh
    kpi_tile(0, 0, "FORM  ·  TSB", "+5", "FRESH · READY",
             GREEN_OK, GREEN_OK,
             sparkline=[-12, -8, -4, -2, 1, 3, 4, 5])
    # Fitness (CTL) — 3:15 projected
    kpi_tile(1, 0, "FITNESS  ·  CTL", "3:15", "−47s vs 4 WK",
             GREEN_OK, INK,
             sparkline=[210, 215, 220, 218, 222, 225, 224, 228])
    # Load (ACWR)
    kpi_tile(0, 1, "LOAD  ·  ACWR", "1.18", "PRODUCTIVE",
             GREEN_OK, INK,
             sparkline=[0.95, 1.02, 1.10, 1.05, 1.16, 1.10, 1.20, 1.18])
    # Strain (yesterday)
    kpi_tile(1, 1, "STRAIN", "8.6", "TEMPO +35",
             AMBER, AMBER,
             sparkline=[2, 3, 8.6, 1, 2, 9, 3, 8])

    # ── FITNESS CURVE — CTL / ATL / TSB over 12 weeks ────────
    curve_y = grid_top + 2*tile_h + 10 + 16
    hairline(d, inner_l, curve_y, inner_r, curve_y, fill=HAIR)
    text(d, (inner_l, curve_y + 14), "FITNESS CURVE  ·  12 WEEKS",
         MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_r, curve_y + 14), "CTL · ATL · TSB",
         MONO(11), fill=SLATE_LIGHT, anchor="ra")

    chart_x1 = inner_l
    chart_x2 = inner_r
    chart_y1 = curve_y + 44
    chart_y2 = curve_y + 44 + 130
    rounded_box(d, chart_x1, chart_y1, chart_x2, chart_y2, 8, fill=BONE, outline=HAIR, width=1)

    # CTL line (rising)
    n = 12
    ctl = [40, 42, 44, 46, 48, 50, 52, 54, 56, 58, 60, 62]
    atl = [40, 45, 42, 50, 48, 55, 52, 58, 54, 60, 58, 64]
    tsb = [a - b for a, b in zip(ctl, atl)]   # positive = fresh
    max_v = max(max(ctl), max(atl)) + 5
    min_v = min(tsb) - 2
    range_ = max_v - min_v
    pad = 12
    def y_for(v):
        return chart_y2 - pad - ((v - min_v) / range_) * (chart_y2 - chart_y1 - 2*pad)
    def x_for(i):
        return chart_x1 + 12 + (i / (n - 1)) * (chart_x2 - chart_x1 - 24)
    # zero line for TSB
    zero_y = y_for(0)
    d.line([(chart_x1+12, zero_y),(chart_x2-12, zero_y)], fill=HAIR, width=1)
    text(d, (chart_x2 - 14, zero_y - 12), "0", MONO(8), fill=SLATE_LIGHT, anchor="ra")
    # CTL line (ink)
    pts = [(x_for(i), y_for(ctl[i])) for i in range(n)]
    d.line(pts, fill=INK, width=2)
    # ATL line (slate dashed look)
    pts2 = [(x_for(i), y_for(atl[i])) for i in range(n)]
    d.line(pts2, fill=SLATE, width=1)
    # TSB filled area (amber if positive, slate if negative)
    for i in range(n - 1):
        v1, v2 = tsb[i], tsb[i+1]
        x1, x2 = x_for(i), x_for(i+1)
        y_v1, y_v2 = y_for(v1), y_for(v2)
        col = GREEN_OK if (v1 + v2) / 2 >= 0 else AMBER
        d.polygon([(x1, y_v1),(x2, y_v2),(x2, zero_y),(x1, zero_y)],
                  fill=tuple(int(c + (244 - c)*0.7) for c in col))
    # Legend
    leg_y = chart_y1 + 8
    text(d, (chart_x1 + 12, leg_y), "─ CTL FITNESS", MONO(8), fill=INK, anchor="la")
    text(d, (chart_x1 + 100, leg_y), "─ ATL FATIGUE", MONO(8), fill=SLATE, anchor="la")
    text(d, (chart_x1 + 192, leg_y), "▁ TSB FORM", MONO(8), fill=GREEN_OK, anchor="la")

    # ── ZONE SHIFTS — this week vs last 4-wk avg ──────────
    zs_y = chart_y2 + 18
    hairline(d, inner_l, zs_y, inner_r, zs_y, fill=HAIR)
    text(d, (inner_l, zs_y + 14), "ZONE SHIFTS  ·  WEEK vs 4 WK AVG",
         MONO(11), fill=SLATE, anchor="la")

    # 5 zones, each shows current % and delta
    zones_data = [
        ("EASY",      62, +4, GREEN_OK),
        ("STEADY",    22, -2, SLATE),
        ("THRESHOLD",  9, +1, AMBER),
        ("VO2",        4, -1, INK),
        ("RACE",       3,  0, INK),
    ]
    pcr_y = zs_y + 44
    pcw = (inner_r - inner_l) / len(zones_data)
    for i, (name, pct, delta, col) in enumerate(zones_data):
        cx = inner_l + i*pcw + pcw/2
        text(d, (cx, pcr_y), name, MONO(9), fill=col, anchor="ma")
        text(d, (cx, pcr_y + 16), f"{pct}%", DISPLAY_B(20), fill=INK, anchor="ma")
        sign = "+" if delta > 0 else ""
        delta_col = GREEN_OK if delta > 0 else (SLATE if delta == 0 else AMBER)
        text(d, (cx, pcr_y + 50), f"{sign}{delta}", MONO(9), fill=delta_col, anchor="ma")

    # ── RACE PREDICTIONS — distances with deltas ────────────
    rp_y = pcr_y + 80
    hairline(d, inner_l, rp_y, inner_r, rp_y, fill=HAIR)
    text(d, (inner_l, rp_y + 14), "RACE PREDICTIONS",
         MONO(11), fill=SLATE, anchor="la")
    text(d, (inner_r, rp_y + 14), "MEDIUM CONFIDENCE",
         MONO(11), fill=SLATE_LIGHT, anchor="ra")

    races = [
        ("MILE",  "5:42",   "−4s"),
        ("5K",    "18:52",  "−14s"),
        ("10K",   "39:11",  "−24s"),
        ("HALF",  "1:27",   "−47s"),
        ("FULL",  "3:15",   "−1:24"),
    ]
    rpr_y = rp_y + 44
    rcw = (inner_r - inner_l) / len(races)
    for i,(lab,t,delta) in enumerate(races):
        cx = inner_l + i*rcw + rcw/2
        text(d, (cx, rpr_y), lab, MONO(9), fill=SLATE, anchor="ma")
        text(d, (cx, rpr_y + 16), t, DISPLAY_B(20), fill=INK, anchor="ma")
        text(d, (cx, rpr_y + 50), delta, MONO(9), fill=GREEN_OK, anchor="ma")
    for i in range(1, len(races)):
        x = inner_l + i*rcw
        d.line([(x, rpr_y - 6),(x, rpr_y + 60)], fill=HAIR, width=1)

    # Tab bar — TODAY active (first tab)
    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=0)
    return img

# ---------------------------------------------------------------------------
# PAGE 17 — TODAY TAB · TRAINING DIARY
# Prose-first, marginalia-style data, voice-memo quotes as journal entries.
# ---------------------------------------------------------------------------
def page_17():
    img, d = new_page()
    page_chrome(d, 17,
                "OPTION B",
                "Today · Training Diary",
                ["A page from your training diary. Today's prompt, yesterday's",
                 "entry as prose, the coach's note. Data lives in the margins."])
    sx1, sy1, sx2, sy2 = draw_phone(d)

    # Header — settings only, no toolbar text
    text(d, (sx2-30, sy1+76), "⚙", DISPLAY_B(18), fill=SLATE, anchor="ra")

    inner_l = sx1 + 30
    inner_r = sx2 - 30

    # ── Date as page heading ────────────────────────────────
    date_y = sy1 + 110
    text(d, (inner_l, date_y), "TUESDAY", MONO(11), fill=AMBER, anchor="la")
    text(d, (inner_l, date_y + 22),
         "May 5th.",
         DISPLAY_B(36), fill=INK, anchor="la")
    # Marginalia race countdown
    text(d, (inner_l, date_y + 70),
         "—— eleven weeks to the marathon. ——",
         SERIF_IT(14), fill=SLATE_LIGHT, anchor="la")

    # ── Today's prompt ──────────────────────────────────────
    prompt_y = date_y + 120
    hairline(d, inner_l, prompt_y, inner_r, prompt_y, fill=HAIR)
    text(d, (inner_l, prompt_y + 14), "TODAY", MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_l, prompt_y + 36),
         "How are you feeling?",
         DISPLAY_B(24), fill=INK, anchor="la")
    # Quick mood selectors as one-tap dots
    moods = [
        ("ENERGIZED", GREEN_OK),
        ("POSITIVE",  GREEN_OK),
        ("NEUTRAL",   SLATE),
        ("TIRED",     AMBER),
        ("STRUGGLING",(175, 79, 79)),
    ]
    mp_y = prompt_y + 80
    cw = (inner_r - inner_l) / len(moods)
    for i, (lab, col) in enumerate(moods):
        cx = inner_l + i*cw + cw/2
        r = 8
        d.ellipse([cx-r, mp_y-r, cx+r, mp_y+r], outline=col, width=1)
        text(d, (cx, mp_y + 18), lab, MONO(8), fill=SLATE_LIGHT, anchor="ma")

    # ── Yesterday's entry — JOURNAL STYLE ───────────────────
    y_y = mp_y + 60
    hairline(d, inner_l, y_y, inner_r, y_y, fill=HAIR)
    text(d, (inner_l, y_y + 14), "SUNDAY  ·  APR 26",
         MONO(10), fill=SLATE, anchor="la")
    # Mood color rule on the left of the entry
    rule_x = inner_l
    d.rectangle([rule_x, y_y + 38, rule_x + 2, y_y + 220], fill=GREEN_OK)
    body_l = inner_l + 16
    text(d, (body_l, y_y + 36), "Tempo, 6.5 mi.", DISPLAY_B(22), fill=INK, anchor="la")
    text(d, (body_l, y_y + 66),
         "7:25 / mi   ·   48 min   ·   POSITIVE",
         MONO(10), fill=SLATE, anchor="la")
    # Italic-serif voice-memo prose, full quote
    text(d, (body_l, y_y + 96),
         "“Felt good through the warm-up — legs were heavy",
         SERIF_IT(15), fill=INK, anchor="la")
    text(d, (body_l, y_y + 118),
         "first mile but loosened up. The tempo blocks were",
         SERIF_IT(15), fill=INK, anchor="la")
    text(d, (body_l, y_y + 140),
         "smoother than two weeks ago. Cool-down a little",
         SERIF_IT(15), fill=INK, anchor="la")
    text(d, (body_l, y_y + 162),
         "tight in the right calf — keeping an eye on it.”",
         SERIF_IT(15), fill=INK, anchor="la")
    # Coach's marginal note in italic (different color)
    text(d, (body_l, y_y + 200),
         "—— coach: solid tempo. Hold it for week 11 too.",
         SERIF_IT(13), fill=AMBER, anchor="la")

    # ── Tomorrow's prescription — like a coach's letter ────
    tm_y = y_y + 250
    hairline(d, inner_l, tm_y, inner_r, tm_y, fill=HAIR)
    text(d, (inner_l, tm_y + 14), "TOMORROW", MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_r, tm_y + 14), "FROM YOUR COACH", MONO(10), fill=SLATE_LIGHT, anchor="ra")
    text(d, (inner_l, tm_y + 36),
         "Tempo, 8 miles.",
         DISPLAY_B(22), fill=INK, anchor="la")
    text(d, (inner_l, tm_y + 66),
         "2 mi warm-up · 5 mi at 7:00 / mi · 1 mi cool-down",
         MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_l, tm_y + 92),
         "“The aim is consistent splits, not negative — let",
         SERIF_IT(13), fill=SLATE, anchor="la")
    text(d, (inner_l, tm_y + 112),
         "the rhythm settle. Don't chase the last mile.”",
         SERIF_IT(13), fill=SLATE, anchor="la")

    # ── Marginalia / quick stats at the bottom ─────────────
    foot_y = tm_y + 152
    hairline(d, inner_l, foot_y, inner_r, foot_y, fill=HAIR)
    # Three small stats inline, like footnotes
    stats = [
        ("THIS WEEK", "0.0 / 47 MI"),
        ("EASY PACE", "8:24 /MI"),
        ("LONG RUN",  "—  ·  30 d"),
    ]
    sw = (inner_r - inner_l) / len(stats)
    for i, (lab, val) in enumerate(stats):
        cx = inner_l + i*sw + sw/2
        text(d, (cx, foot_y + 14), lab, MONO(9), fill=SLATE_LIGHT, anchor="ma")
        text(d, (cx, foot_y + 30), val, MONO(11), fill=SLATE, anchor="ma")

    # Tab bar — TODAY active
    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=0)
    return img

# ---------------------------------------------------------------------------
# PAGE 18 — TODAY TAB · DIARY (top of 17) + COCKPIT BOTTOM (bottom of 16)
# Diary spine: date / mood prompt / yesterday entry / tomorrow prescription.
# Cockpit charts: fitness curve / zone shifts / race predictions.
# Strain & TSB tiles INTENTIONALLY DROPPED — those data sources don't exist
# yet, would require shipping fake numbers.
# ---------------------------------------------------------------------------
def page_18():
    img, d = new_page()
    page_chrome(d, 18,
                "BLENDED",
                "Today · Diary + Charts",
                ["Diary spine on top (Plate 17), cockpit's bottom half on the",
                 "bottom (Plate 16). Strain/TSB tiles dropped — data not honest yet."])
    sx1, sy1, sx2, sy2 = draw_phone(d)

    # Settings at top right
    text(d, (sx2-30, sy1+76), "⚙", DISPLAY_B(18), fill=SLATE, anchor="ra")

    inner_l = sx1 + 30
    inner_r = sx2 - 30

    # ── Date heading ────────────────────────────────────────
    date_y = sy1 + 110
    text(d, (inner_l, date_y), "TUESDAY", MONO(11), fill=AMBER, anchor="la")
    text(d, (inner_l, date_y + 22), "May 5th.",
         DISPLAY_B(32), fill=INK, anchor="la")
    text(d, (inner_l, date_y + 64),
         "—— eleven weeks to the marathon. ——",
         SERIF_IT(13), fill=SLATE_LIGHT, anchor="la")

    # ── Today's prompt ──────────────────────────────────────
    prompt_y = date_y + 100
    hairline(d, inner_l, prompt_y, inner_r, prompt_y, fill=HAIR)
    text(d, (inner_l, prompt_y + 14), "TODAY", MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_l, prompt_y + 32), "How are you feeling?",
         DISPLAY_B(20), fill=INK, anchor="la")
    moods = [
        ("ENERGIZED", GREEN_OK),
        ("POSITIVE",  GREEN_OK),
        ("NEUTRAL",   SLATE),
        ("TIRED",     AMBER),
        ("STRUGGLING",(175, 79, 79)),
    ]
    mp_y = prompt_y + 76
    cw = (inner_r - inner_l) / len(moods)
    for i, (lab, col) in enumerate(moods):
        cx = inner_l + i*cw + cw/2
        r = 7
        d.ellipse([cx-r, mp_y-r, cx+r, mp_y+r], outline=col, width=1)
        text(d, (cx, mp_y + 16), lab, MONO(8), fill=SLATE_LIGHT, anchor="ma")

    # ── Yesterday's journal entry ───────────────────────────
    y_y = mp_y + 50
    hairline(d, inner_l, y_y, inner_r, y_y, fill=HAIR)
    text(d, (inner_l, y_y + 14), "SUNDAY  ·  APR 26",
         MONO(10), fill=SLATE, anchor="la")
    rule_x = inner_l
    d.rectangle([rule_x, y_y + 38, rule_x + 2, y_y + 178], fill=GREEN_OK)
    body_l = inner_l + 16
    text(d, (body_l, y_y + 36), "Tempo, 6.5 mi.",
         DISPLAY_B(22), fill=INK, anchor="la")
    text(d, (body_l, y_y + 66),
         "7:25 / mi   ·   48 min   ·   POSITIVE",
         MONO(10), fill=SLATE, anchor="la")
    text(d, (body_l, y_y + 96),
         "“Felt good through the warm-up — legs were heavy",
         SERIF_IT(14), fill=INK, anchor="la")
    text(d, (body_l, y_y + 116),
         "first mile but loosened up. Tempo blocks smoother",
         SERIF_IT(14), fill=INK, anchor="la")
    text(d, (body_l, y_y + 136),
         "than two weeks ago.”",
         SERIF_IT(14), fill=INK, anchor="la")

    # ── Tomorrow's prescription ────────────────────────────
    tm_y = y_y + 200
    hairline(d, inner_l, tm_y, inner_r, tm_y, fill=HAIR)
    text(d, (inner_l, tm_y + 14), "TOMORROW", MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_r, tm_y + 14), "FROM YOUR COACH",
         MONO(10), fill=SLATE_LIGHT, anchor="ra")
    text(d, (inner_l, tm_y + 36), "Tempo, 8 miles.",
         DISPLAY_B(22), fill=INK, anchor="la")
    text(d, (inner_l, tm_y + 66),
         "2 mi WU · 5 mi at 7:00 / mi · 1 mi CD",
         MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_l, tm_y + 92),
         "“Consistent splits, not negative. Let the rhythm settle.”",
         SERIF_IT(13), fill=SLATE, anchor="la")

    # ════════════════════════════════════════════════════════
    # COCKPIT BOTTOM — fitness curve, zone shifts, race predictions
    # ════════════════════════════════════════════════════════

    # ── FITNESS · 12-week trend (single line, honest data) ─
    fc_y = tm_y + 130
    hairline(d, inner_l, fc_y, inner_r, fc_y, fill=HAIR)
    text(d, (inner_l, fc_y + 14), "FITNESS  ·  12 WEEKS",
         MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_r, fc_y + 14), "PREDICTED MARATHON",
         MONO(10), fill=SLATE_LIGHT, anchor="ra")

    # Single-line curve (predicted marathon time descending = fitness up)
    chart_x1 = inner_l
    chart_x2 = inner_r
    chart_y1 = fc_y + 38
    chart_y2 = fc_y + 38 + 90
    rounded_box(d, chart_x1, chart_y1, chart_x2, chart_y2, 8,
                fill=BONE, outline=HAIR, width=1)
    n = 24
    pts = []
    for i in range(n):
        t = i / (n - 1)
        v = 209 - t*15 - 1.0*math.sin(t*4.5) + (random.random()-0.5)*0.5
        x = chart_x1 + 14 + t*(chart_x2 - chart_x1 - 28)
        # map: 200 (3:20) bottom, 215 (3:35) top
        y = chart_y2 - 14 - ((215 - v) / 15) * (chart_y2 - chart_y1 - 28)
        pts.append((x, y))
    d.line(pts, fill=INK, width=2, joint="curve")
    cx, cy = pts[-1]
    d.ellipse([cx-4, cy-4, cx+4, cy+4], fill=AMBER, outline=PAPER, width=1)
    # Axis labels (just two points)
    text(d, (chart_x1 + 14, chart_y2 - 12), "12W AGO",
         MONO(8), fill=SLATE_LIGHT, anchor="la")
    text(d, (chart_x2 - 14, chart_y2 - 12), "NOW",
         MONO(8), fill=AMBER, anchor="ra")
    # Headline numbers above the chart
    text(d, (chart_x1 + 14, chart_y1 + 12), "3:15  →  fitness up",
         MONO(10), fill=GREEN_OK, anchor="la")

    # ── ZONE SHIFTS · this week vs 4-wk avg ────────────────
    zs_y = chart_y2 + 18
    hairline(d, inner_l, zs_y, inner_r, zs_y, fill=HAIR)
    text(d, (inner_l, zs_y + 14), "ZONE SHIFTS  ·  WEEK vs 4 WK AVG",
         MONO(10), fill=SLATE, anchor="la")

    # 4 zones — only what workout_features actually has
    zones_data = [
        ("EASY",       62, +4, GREEN_OK),
        ("MODERATE",   22, -2, SLATE),
        ("THRESHOLD",   9, +1, AMBER),
        ("HARD",        7, -3, INK),
    ]
    pcr_y = zs_y + 44
    pcw = (inner_r - inner_l) / len(zones_data)
    for i, (name, pct, delta, col) in enumerate(zones_data):
        cx = inner_l + i*pcw + pcw/2
        text(d, (cx, pcr_y), name, MONO(9), fill=col, anchor="ma")
        text(d, (cx, pcr_y + 16), f"{pct}%", DISPLAY_B(20), fill=INK, anchor="ma")
        sign = "+" if delta > 0 else ""
        delta_col = GREEN_OK if delta > 0 else (SLATE if delta == 0 else AMBER)
        text(d, (cx, pcr_y + 50), f"{sign}{delta}", MONO(9), fill=delta_col, anchor="ma")

    # ── RACE PREDICTIONS · 5 distances + deltas ────────────
    rp_y = pcr_y + 80
    hairline(d, inner_l, rp_y, inner_r, rp_y, fill=HAIR)
    text(d, (inner_l, rp_y + 14), "RACE PREDICTIONS",
         MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_r, rp_y + 14), "MEDIUM CONFIDENCE",
         MONO(10), fill=SLATE_LIGHT, anchor="ra")

    races = [
        ("MILE",  "5:42",   "−4s"),
        ("5K",    "18:52",  "−14s"),
        ("10K",   "39:11",  "−24s"),
        ("HALF",  "1:27",   "−47s"),
        ("FULL",  "3:15",   "−1:24"),
    ]
    rpr_y = rp_y + 44
    rcw = (inner_r - inner_l) / len(races)
    for i,(lab,t,delta) in enumerate(races):
        cx = inner_l + i*rcw + rcw/2
        text(d, (cx, rpr_y), lab, MONO(9), fill=SLATE, anchor="ma")
        text(d, (cx, rpr_y + 16), t, DISPLAY_B(18), fill=INK, anchor="ma")
        text(d, (cx, rpr_y + 48), delta, MONO(9), fill=GREEN_OK, anchor="ma")
    for i in range(1, len(races)):
        x = inner_l + i*rcw
        d.line([(x, rpr_y - 6),(x, rpr_y + 60)], fill=HAIR, width=1)

    # Tab bar — TODAY active
    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=0)
    return img

# ---------------------------------------------------------------------------
# PAGE 19 — TRAINING TAB · "KPI TILE GRID"
# Notion/Linear analytics aesthetic. 6 stat tiles in a 3×2 grid, each tile is
# big number + tiny sparkline + delta vs prior period. Hero 12-week mileage
# stack chart anchors the bottom. Variant A — most number-forward.
# ---------------------------------------------------------------------------
def page_19():
    img, d = new_page()
    page_chrome(d, 19,
                "TRAINING · VARIANT A",
                "KPI Tile Grid",
                ["Six stat tiles, each anchored by a big number, supported by a 12-week",
                 "sparkline and a delta vs prior period. Hero stack chart at the bottom."])
    sx1, sy1, sx2, sy2 = draw_phone(d)

    # ── Header ─────────────────────────────────────────────
    head_y = sy1 + 90
    text(d, (sx1+30, head_y), "TRAINING  ·  12-WK BLOCK",
         MONO(11), fill=AMBER, anchor="la")
    text(d, (sx1+30, head_y+22), "Block 2 · Week 8 / 12",
         DISPLAY_B(28), fill=INK, anchor="la")
    text(d, (sx1+30, head_y+62), "Base phase. Four weeks to peak.",
         SERIF_IT(13), fill=SLATE, anchor="la")
    hairline(d, sx1+30, head_y+96, sx2-30, head_y+96, fill=HAIR)

    inner_l = sx1 + 30
    inner_r = sx2 - 30
    inner_w = inner_r - inner_l

    # ── KPI Grid 3×2 ───────────────────────────────────────
    grid_top = head_y + 116
    col_gap = 14
    col_w = (inner_w - col_gap*2) / 3
    row_h = 130
    row_gap = 10

    def spark_line(d, x, y, w, h, points, current_idx=None, color=INK):
        """Tiny line sparkline. points: list of floats, normalized to plot area."""
        if len(points) < 2: return
        mn, mx = min(points), max(points)
        rng = max(mx - mn, 0.001)
        coords = []
        for i, v in enumerate(points):
            px = x + (i / (len(points)-1)) * w
            py = y + h - ((v - mn)/rng) * h
            coords.append((px, py))
        for i in range(len(coords)-1):
            d.line([coords[i], coords[i+1]], fill=color, width=2)
        if current_idx is not None and 0 <= current_idx < len(coords):
            cx, cy = coords[current_idx]
            r = 3
            d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=AMBER)

    def spark_bars(d, x, y, w, h, values, current_idx=None, color=INK):
        """Tiny bar sparkline."""
        if not values: return
        mx = max(values) or 1
        bw = w / len(values) * 0.7
        gap = (w / len(values)) * 0.3
        for i, v in enumerate(values):
            bh = (v / mx) * h
            bx = x + i * (bw + gap)
            by = y + h - bh
            fill = AMBER if (current_idx is not None and i == current_idx) else color
            d.rectangle([bx, by, bx+bw, y+h], fill=fill)

    def kpi_tile(col, row, eyebrow, value, value_unit, delta, delta_color, spark_kind, spark_data, spark_idx=None):
        x = inner_l + col*(col_w + col_gap)
        y = grid_top + row*(row_h + row_gap)
        # eyebrow
        text(d, (x, y), eyebrow, MONO(9), fill=SLATE, anchor="la")
        # main number
        text(d, (x, y+18), value, DISPLAY_B(28), fill=INK, anchor="la")
        # unit
        if value_unit:
            vw = tw(d, value, DISPLAY_B(28))
            text(d, (x + vw + 4, y+38), value_unit, MONO(10), fill=SLATE, anchor="la")
        # sparkline (mid)
        sp_y = y + 60
        sp_h = 28
        if spark_kind == "line":
            spark_line(d, x, sp_y, col_w-4, sp_h, spark_data, current_idx=spark_idx)
        else:
            spark_bars(d, x, sp_y, col_w-4, sp_h, spark_data, current_idx=spark_idx)
        # baseline rule
        hairline(d, x, sp_y+sp_h+4, x+col_w-4, sp_y+sp_h+4, fill=HAIR)
        # delta line
        text(d, (x, sp_y+sp_h+12), delta, MONO(10), fill=delta_color, anchor="la")

    # Demo data — illustrative for mockup, not pulled from db
    mileage_12w = [38, 42, 41, 45, 48, 44, 49, 50, 47, 49, 52, 50.4]
    fitness_12w = [199*60+30, 198*60, 196*60+45, 195*60+15, 194*60, 193*60+10,
                   191*60+30, 191*60, 190*60+15, 189*60+45, 188*60+50, 188*60+42]
    fitness_norm = [(f - min(fitness_12w))/(max(fitness_12w)-min(fitness_12w)+0.001) for f in fitness_12w]
    # invert (lower seconds = higher fitness = up)
    fitness_norm = [1 - v for v in fitness_norm]
    acwr_12w = [0.95, 1.02, 1.08, 1.12, 1.10, 1.05, 1.14, 1.18, 1.16, 1.20, 1.22, 1.18]
    easy_12w = [8.65, 8.60, 8.55, 8.55, 8.50, 8.48, 8.45, 8.40, 8.42, 8.38, 8.35, 8.40]
    thresh_12w = [7.05, 7.00, 6.95, 6.92, 6.90, 6.88, 6.85, 6.82, 6.78, 6.75, 6.70, 6.70]
    long_12w = [12, 14, 13, 15, 16, 14, 17, 16, 18, 17, 20, 18]

    kpi_tile(0, 0, "VOLUME · WEEK", "50.4", "mi",  "+4.2 vs 4wk avg", GREEN_OK,
             "bars", mileage_12w, spark_idx=11)
    kpi_tile(1, 0, "FITNESS · MARATHON", "3:08:42", "",  "−2:15 since wk 1", GREEN_OK,
             "line", fitness_norm, spark_idx=11)
    kpi_tile(2, 0, "LOAD · ACWR", "1.18", "",  "OPTIMAL  (0.8–1.3)", SLATE,
             "line", acwr_12w, spark_idx=11)
    kpi_tile(0, 1, "EASY · 30D AVG", "8:24", "/mi", "−0:14 since wk 1", GREEN_OK,
             "line", [-v for v in easy_12w], spark_idx=11)
    kpi_tile(1, 1, "THRESHOLD · 30D",  "6:42", "/mi", "−0:23 since wk 1", GREEN_OK,
             "line", [-v for v in thresh_12w], spark_idx=11)
    kpi_tile(2, 1, "LONG RUN · BLOCK", "20.0", "mi", "+8 vs wk 1",      GREEN_OK,
             "bars", long_12w, spark_idx=10)

    # ── Hero: 12-week stacked mileage by zone ──────────────
    hero_y = grid_top + row_h*2 + row_gap*2 + 14
    hairline(d, inner_l, hero_y, inner_r, hero_y, fill=HAIR)
    text(d, (inner_l, hero_y+12), "VOLUME BY INTENSITY  ·  12 WEEKS",
         MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_r, hero_y+12), "EASY  MOD  THR  HARD",
         MONO(9), fill=SLATE_LIGHT, anchor="ra")

    # stacked bars (illustrative weekly composition) — capped height so the
    # six stat tiles above keep their breathing room
    h_top = hero_y + 36
    h_bot = h_top + 240
    h_h = h_bot - h_top
    n = 12
    bar_w = (inner_w / n) * 0.7
    bar_gap = (inner_w / n) * 0.3
    # zones per week (easy, mod, thresh, hard) — sum ≈ mileage
    zone_data = [
        (30,5,2,1), (32,6,3,1), (32,5,3,1), (34,6,3,2),
        (36,6,4,2), (32,7,4,1), (36,7,4,2), (37,7,4,2),
        (35,6,4,2), (37,6,4,2), (38,7,5,2), (37,7,4,2.4),
    ]
    mx_total = max(sum(z) for z in zone_data) or 1
    zone_colors = [SLATE_LIGHT, SLATE, AMBER, INK]
    for i, zones in enumerate(zone_data):
        bx = inner_l + i*(bar_w + bar_gap)
        cum = 0
        total = sum(zones)
        bar_total_h = (total / mx_total) * h_h
        # draw segments bottom-up
        seg_y = h_bot
        for zi, zv in enumerate(zones):
            seg_h = (zv / total) * bar_total_h if total else 0
            d.rectangle([bx, seg_y - seg_h, bx + bar_w, seg_y], fill=zone_colors[zi])
            seg_y -= seg_h
        # current-week emphasis
        if i == n-1:
            text(d, (bx + bar_w/2, seg_y - 14), "NOW", MONO(8), fill=AMBER, anchor="ma")
    # baseline
    hairline(d, inner_l, h_bot+1, inner_r, h_bot+1, fill=SLATE_LIGHT)
    # week labels (just first/middle/last)
    text(d, (inner_l, h_bot+8), "12W AGO", MONO(9), fill=SLATE_LIGHT, anchor="la")
    text(d, (inner_r, h_bot+8), "THIS WEEK", MONO(9), fill=SLATE_LIGHT, anchor="ra")

    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=1)
    return img


# ---------------------------------------------------------------------------
# PAGE 20 — TRAINING TAB · "TRENDS GRID"
# Most chart-forward. A 3×2 grid of small line/bar charts — every metric
# rendered as a trend over time. Variant B — least decorative, max signal.
# ---------------------------------------------------------------------------
def page_20():
    img, d = new_page()
    page_chrome(d, 20,
                "TRAINING · VARIANT B",
                "Trends Grid",
                ["Every metric is a chart, every chart is a trend over time. Six small",
                 "panels — line for continuous metrics, bars for episodic ones."])
    sx1, sy1, sx2, sy2 = draw_phone(d)

    # ── Header ─────────────────────────────────────────────
    head_y = sy1 + 90
    text(d, (sx1+30, head_y), "TRAINING  ·  TRENDS",
         MONO(11), fill=AMBER, anchor="la")
    text(d, (sx1+30, head_y+22), "12 weeks",
         DISPLAY_B(28), fill=INK, anchor="la")
    text(d, (sx2-30, head_y+30), "BLOCK 2  ·  W 8 / 12",
         MONO(10), fill=SLATE, anchor="ra")
    hairline(d, sx1+30, head_y+72, sx2-30, head_y+72, fill=HAIR)

    inner_l = sx1 + 30
    inner_r = sx2 - 30
    inner_w = inner_r - inner_l

    # ── Six chart panels in 2 rows × 3 cols ────────────────
    panel_top = head_y + 92
    col_gap = 12
    col_w = (inner_w - col_gap*2) / 3
    panel_h = 160
    row_gap = 18

    def gridded_line(d, px, py, pw, ph, values, lo_label="", hi_label="",
                     show_band=False, band_lo=None, band_hi=None,
                     current_color=AMBER):
        """A small line chart with one horizontal gridline mid-height + axis labels.
        For ACWR: re-anchor mn/mx around the band so it doesn't dominate."""
        if len(values) < 2: return
        if show_band and band_lo is not None and band_hi is not None:
            mn = min(min(values), band_lo) - 0.05
            mx = max(max(values), band_hi) + 0.05
        else:
            mn, mx = min(values), max(values)
        rng = max(mx - mn, 0.001)
        # plot area
        plot_l = px + 4
        plot_r = px + pw - 4
        plot_t = py + 4
        plot_b = py + ph - 4
        plot_w = plot_r - plot_l
        plot_h = plot_b - plot_t
        # band (e.g. ACWR optimal range) — clamped to plot area
        if show_band and band_lo is not None and band_hi is not None:
            by_lo = plot_b - ((band_lo - mn)/rng) * plot_h
            by_hi = plot_b - ((band_hi - mn)/rng) * plot_h
            by_lo = max(plot_t, min(plot_b, by_lo))
            by_hi = max(plot_t, min(plot_b, by_hi))
            d.rectangle([plot_l, by_hi, plot_r, by_lo], fill=(232,228,218))
        # mid gridline
        mid_y = plot_t + plot_h/2
        for x in range(int(plot_l), int(plot_r), 6):
            d.line([(x, mid_y), (x+3, mid_y)], fill=HAIR)
        # line
        coords = []
        for i, v in enumerate(values):
            cx = plot_l + (i / (len(values)-1)) * plot_w
            cy = plot_b - ((v - mn)/rng) * plot_h
            coords.append((cx, cy))
        for i in range(len(coords)-1):
            d.line([coords[i], coords[i+1]], fill=INK, width=2)
        # current point
        cx, cy = coords[-1]
        r = 3
        d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=current_color)
        # range labels (left side)
        if lo_label:
            text(d, (plot_l, plot_b+2), lo_label, MONO(8), fill=SLATE_LIGHT, anchor="la")
        if hi_label:
            text(d, (plot_l, plot_t-12), hi_label, MONO(8), fill=SLATE_LIGHT, anchor="la")

    def gridded_bars(d, px, py, pw, ph, values, current_idx=None):
        if not values: return
        mx = max(values) or 1
        plot_l = px + 4
        plot_r = px + pw - 4
        plot_t = py + 4
        plot_b = py + ph - 4
        plot_w = plot_r - plot_l
        plot_h = plot_b - plot_t
        # mid gridline
        mid_y = plot_t + plot_h/2
        for x in range(int(plot_l), int(plot_r), 6):
            d.line([(x, mid_y), (x+3, mid_y)], fill=HAIR)
        bw = plot_w / len(values) * 0.7
        gap = plot_w / len(values) * 0.3
        for i, v in enumerate(values):
            bh = (v / mx) * plot_h
            bx = plot_l + i*(bw+gap)
            by = plot_b - bh
            fill = AMBER if (current_idx is not None and i == current_idx) else INK
            d.rectangle([bx, by, bx+bw, plot_b], fill=fill)

    def panel(col, row, eyebrow, current_value, kind, data,
              meta=None, **kwargs):
        px = inner_l + col*(col_w + col_gap)
        py = panel_top + row*(panel_h + row_gap)
        # eyebrow
        text(d, (px, py), eyebrow, MONO(9), fill=SLATE, anchor="la")
        # current value (compact)
        text(d, (px, py+16), current_value, DISPLAY_B(20), fill=INK, anchor="la")
        # meta sits BELOW the value, on its own row — avoids overlapping
        # both the eyebrow and the chart
        if meta:
            text(d, (px, py+42), meta, MONO(8),
                 fill=SLATE_LIGHT, anchor="la")
        # chart fills the rest
        chart_y = py + 60
        chart_h = panel_h - 70
        if kind == "line":
            gridded_line(d, px, chart_y, col_w, chart_h, data, **kwargs)
        else:
            gridded_bars(d, px, chart_y, col_w, chart_h, data,
                         current_idx=kwargs.get("current_idx"))

    # Demo data
    mileage_12w = [38, 42, 41, 45, 48, 44, 49, 50, 47, 49, 52, 50.4]
    # fitness in seconds, rendered inverted so up = better
    fit_secs = [11970, 11880, 11805, 11715, 11640, 11590, 11490, 11460, 11415, 11385, 11330, 11322]
    fit_inv = [-v for v in fit_secs]
    acwr = [0.95, 1.02, 1.08, 1.12, 1.10, 1.05, 1.14, 1.18, 1.16, 1.20, 1.22, 1.18]
    easy = [519, 516, 513, 513, 510, 508, 507, 504, 505, 503, 501, 504]
    easy_inv = [-v for v in easy]
    thresh = [425, 420, 417, 415, 414, 412, 410, 408, 405, 403, 401, 402]
    thresh_inv = [-v for v in thresh]
    long_run = [12, 14, 13, 15, 16, 14, 17, 16, 18, 17, 20, 18]

    panel(0, 0, "WEEKLY MILEAGE", "50.4 mi",     "bars", mileage_12w,
          meta="THIS WEEK", current_idx=11)
    panel(1, 0, "PREDICTED MARATHON",   "3:08:42",     "line", fit_inv,
          meta="↓ 0:11 / wk", hi_label="2:55", lo_label="3:20")
    panel(2, 0, "ACWR",   "1.18",        "line", acwr,
          meta="OPTIMAL",  hi_label="1.5", lo_label="0.8",
          show_band=True, band_lo=0.8, band_hi=1.3)
    panel(0, 1, "EASY PACE · AVG", "8:24/mi",     "line", easy_inv,
          meta="↓ 0:01 / wk", hi_label="8:00", lo_label="8:45")
    panel(1, 1, "THRESHOLD PACE", "6:42/mi",     "line", thresh_inv,
          meta="↓ 0:02 / wk", hi_label="6:30", lo_label="7:05")
    panel(2, 1, "LONGEST RUN",    "20.0 mi",      "bars", long_run,
          meta="WEEK 11",   current_idx=10)

    # ── Bottom strip: zone composition over 12 weeks ───────
    strip_y = panel_top + panel_h*2 + row_gap*2 + 14
    hairline(d, inner_l, strip_y, inner_r, strip_y, fill=HAIR)
    text(d, (inner_l, strip_y+10), "ZONE MIX  ·  12 WEEKS",
         MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_r, strip_y+10), "EASY  MOD  THR  HARD",
         MONO(8), fill=SLATE_LIGHT, anchor="ra")
    # 100%-stacked horizontal slabs per week — height capped so the strip
    # stays a strip, not a 60%-of-screen slab
    s_top = strip_y + 32
    s_h = 70
    s_bot = s_top + s_h
    n = 12
    bw = (inner_w / n) * 0.78
    bg = (inner_w / n) * 0.22
    zones_pct = [
        (78,12,7,3), (76,14,7,3), (78,12,7,3), (76,12,9,3),
        (76,12,9,3), (80,11,6,3), (76,11,9,4), (74,12,10,4),
        (75,12,9,4), (74,11,10,5), (73,12,10,5), (74,12,9,5),
    ]
    z_colors = [SLATE_LIGHT, SLATE, AMBER, INK]
    for i, pcts in enumerate(zones_pct):
        bx = inner_l + i*(bw + bg)
        cy = s_top
        for zi, p in enumerate(pcts):
            seg_h = (p / 100) * s_h
            d.rectangle([bx, cy, bx + bw, cy + seg_h], fill=z_colors[zi])
            cy += seg_h
    text(d, (inner_l, s_bot+8), "12W AGO", MONO(8), fill=SLATE_LIGHT, anchor="la")
    text(d, (inner_r, s_bot+8), "THIS WEEK", MONO(8), fill=SLATE_LIGHT, anchor="ra")

    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=1)
    return img


# ---------------------------------------------------------------------------
# PAGE 21 — TRAINING TAB · "HERO + TILES"
# Balance — one anchor chart at the top (block-aware mileage), then a 4-tile
# row of compact stat+sparkline cards, then a "vs last 4 weeks" comparison
# row. Variant C — most narrative, still chart-heavy.
# ---------------------------------------------------------------------------
def page_21():
    img, d = new_page()
    page_chrome(d, 21,
                "TRAINING · VARIANT C",
                "Hero + Tiles",
                ["One anchor chart on top (block-aware stack), four supporting tiles",
                 "below, a comparison row at the bottom. Most narrative of the three."])
    sx1, sy1, sx2, sy2 = draw_phone(d)

    # ── Header w/ block context ────────────────────────────
    head_y = sy1 + 90
    text(d, (sx1+30, head_y), "TRAINING  ·  BLOCK 2",
         MONO(11), fill=AMBER, anchor="la")
    text(d, (sx1+30, head_y+22), "Base phase",
         DISPLAY_B(26), fill=INK, anchor="la")
    text(d, (sx1+30, head_y+58), "Week 8 of 12  ·  4 weeks to peak.",
         SERIF_IT(13), fill=SLATE, anchor="la")
    # phase progress bar
    pb_x1 = sx2 - 180
    pb_x2 = sx2 - 30
    pb_y  = head_y + 28
    text(d, (pb_x2, pb_y - 14), "PHASE PROGRESS", MONO(8),
         fill=SLATE_LIGHT, anchor="ra")
    hairline(d, pb_x1, pb_y, pb_x2, pb_y, fill=HAIR, width=3)
    progress_w = (pb_x2 - pb_x1) * (8/12)
    d.rectangle([pb_x1, pb_y - 1, pb_x1 + progress_w, pb_y + 2], fill=AMBER)
    text(d, (pb_x1, pb_y + 8), "BASE", MONO(8), fill=AMBER, anchor="la")
    text(d, (pb_x1 + (pb_x2-pb_x1)*0.5, pb_y + 8), "BUILD",
         MONO(8), fill=SLATE_LIGHT, anchor="ma")
    text(d, (pb_x2, pb_y + 8), "PEAK", MONO(8), fill=SLATE_LIGHT, anchor="ra")
    hairline(d, sx1+30, head_y+92, sx2-30, head_y+92, fill=HAIR)

    inner_l = sx1 + 30
    inner_r = sx2 - 30
    inner_w = inner_r - inner_l

    # ── Hero chart: 12-week mileage stack with intensity ──
    hero_y = head_y + 110
    text(d, (inner_l, hero_y), "WEEKLY VOLUME  ·  STACKED BY ZONE",
         MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_r, hero_y), "EASY  MOD  THR  HARD",
         MONO(9), fill=SLATE_LIGHT, anchor="ra")

    h_top = hero_y + 28
    h_bot = h_top + 220
    n = 12
    bar_w = (inner_w / n) * 0.7
    bar_gap = (inner_w / n) * 0.3

    zone_data = [
        (30,5,2,1), (32,6,3,1), (32,5,3,1), (34,6,3,2),
        (36,6,4,2), (32,7,4,1), (36,7,4,2), (37,7,4,2),
        (35,6,4,2), (37,6,4,2), (38,7,5,2), (37,7,4,2.4),
    ]
    mx = max(sum(z) for z in zone_data) or 1
    zone_colors = [SLATE_LIGHT, SLATE, AMBER, INK]
    for i, zones in enumerate(zone_data):
        bx = inner_l + i*(bar_w + bar_gap)
        total = sum(zones)
        bar_total_h = (total / mx) * (h_bot - h_top - 8)
        seg_y = h_bot
        for zi, zv in enumerate(zones):
            seg_h = (zv / total) * bar_total_h
            d.rectangle([bx, seg_y - seg_h, bx + bar_w, seg_y], fill=zone_colors[zi])
            seg_y -= seg_h
        if i == n-1:
            # value label above current
            text(d, (bx + bar_w/2, seg_y - 16), "50.4",
                 DISPLAY_B(13), fill=AMBER, anchor="ma")
    hairline(d, inner_l, h_bot+1, inner_r, h_bot+1, fill=SLATE_LIGHT)
    # x-axis week labels (sparse)
    text(d, (inner_l, h_bot+8), "W1", MONO(8), fill=SLATE_LIGHT, anchor="la")
    text(d, (inner_l + inner_w*0.5, h_bot+8), "W6",
         MONO(8), fill=SLATE_LIGHT, anchor="ma")
    text(d, (inner_r, h_bot+8), "W12  ·  NOW",
         MONO(8), fill=SLATE_LIGHT, anchor="ra")

    # ── 4-tile sparkline row ───────────────────────────────
    tile_top = h_bot + 40
    tile_h = 92
    tile_w = (inner_w - 12*3) / 4

    def small_spark(d, x, y, w, h, values, color=INK):
        if len(values) < 2: return
        mn, mx = min(values), max(values)
        rng = max(mx - mn, 0.001)
        coords = []
        for i, v in enumerate(values):
            px = x + (i / (len(values)-1)) * w
            py = y + h - ((v - mn)/rng) * h
            coords.append((px, py))
        for i in range(len(coords)-1):
            d.line([coords[i], coords[i+1]], fill=color, width=2)
        cx, cy = coords[-1]
        r = 3
        d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=AMBER)

    def mini_tile(idx, eyebrow, value, sub, spark_data):
        x = inner_l + idx*(tile_w + 12)
        y = tile_top
        text(d, (x, y), eyebrow, MONO(9), fill=SLATE, anchor="la")
        text(d, (x, y+16), value, DISPLAY_B(20), fill=INK, anchor="la")
        text(d, (x, y+44), sub, MONO(9), fill=SLATE, anchor="la")
        small_spark(d, x, y+58, tile_w-4, 24, spark_data)

    fit_inv = [-v for v in [11970, 11880, 11805, 11715, 11640, 11590, 11490, 11460, 11415, 11385, 11330, 11322]]
    acwr = [0.95, 1.02, 1.08, 1.12, 1.10, 1.05, 1.14, 1.18, 1.16, 1.20, 1.22, 1.18]
    consistency = [0.85, 0.92, 0.95, 0.88, 1.00, 0.95, 0.92, 0.95, 0.98, 1.00, 0.95, 0.96]
    long_run = [12, 14, 13, 15, 16, 14, 17, 16, 18, 17, 20, 18]

    mini_tile(0, "FITNESS",     "3:08:42",  "−2:15 / 12wk",  fit_inv)
    mini_tile(1, "ACWR",        "1.18",     "OPTIMAL",       acwr)
    mini_tile(2, "PLAN HIT",    "96%",      "47 / 49 runs",  consistency)
    mini_tile(3, "LONG RUN",    "20 mi",    "+8 since wk 1", long_run)

    # ── "vs last 4 weeks" comparison row ───────────────────
    cmp_y = tile_top + tile_h + 8
    hairline(d, inner_l, cmp_y, inner_r, cmp_y, fill=HAIR)
    text(d, (inner_l, cmp_y+12), "THIS WEEK  vs  4-WK AVG",
         MONO(10), fill=SLATE, anchor="la")

    cmp_top = cmp_y + 36
    cmp_w = inner_w / 4
    comparisons = [
        ("VOLUME",      "50.4",   "mi",    "+4.2",  GREEN_OK),
        ("EASY PACE",   "8:24",   "/mi",   "−0:04", GREEN_OK),
        ("THRESHOLD",   "6:42",   "/mi",   "−0:03", GREEN_OK),
        ("LONG",        "20.0",   "mi",    "+2.5",  GREEN_OK),
    ]
    for i, (lab, val, unit, dlt, dcol) in enumerate(comparisons):
        cx = inner_l + i*cmp_w
        text(d, (cx, cmp_top), lab, MONO(9), fill=SLATE, anchor="la")
        text(d, (cx, cmp_top+14), val, DISPLAY_B(20), fill=INK, anchor="la")
        if unit:
            vw = tw(d, val, DISPLAY_B(20))
            text(d, (cx + vw + 4, cmp_top+30), unit,
                 MONO(9), fill=SLATE, anchor="la")
        text(d, (cx, cmp_top+42), dlt, MONO(10), fill=dcol, anchor="la")

    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=1)
    return img


# ---------------------------------------------------------------------------
# PAGE 22 — DAY DETAIL SHEET · "Editorial workout"
# Replaces the existing card-based day-detail with the Negative Splits
# aesthetic — Crimson Pro display, monospaced caption, editorial rules,
# journal-style step list. Surfaces the new weighted-load metric in the
# stat strip alongside distance + duration.
# ---------------------------------------------------------------------------
def page_22():
    img, d = new_page()
    page_chrome(d, 22,
                "PLAN · DAY DETAIL",
                "Workout, in voice",
                ["The day-detail sheet redesigned in the trend-mockup voice.",
                 "Cards out, editorial rules in. Coach voice in the body."])
    sx1, sy1, sx2, sy2 = draw_phone(d)

    # ── Sheet drag handle (signals modal) ──────────────────
    handle_y = sy1 + 60
    d.rectangle([sx1 + (sx2-sx1)/2 - 18, handle_y, sx1 + (sx2-sx1)/2 + 18, handle_y + 4],
                fill=SLATE_LIGHT)

    # ── Top bar: Edit · Title · Done ───────────────────────
    bar_y = sy1 + 92
    text(d, (sx1+30, bar_y), "Edit", MONO(11), fill=AMBER, anchor="la")
    text(d, (sx2-30, bar_y), "Done", MONO(11), fill=AMBER, anchor="ra")

    inner_l = sx1 + 30
    inner_r = sx2 - 30
    inner_w = inner_r - inner_l

    # ── Header: date + workout type eyebrow ────────────────
    head_y = bar_y + 32
    text(d, (inner_l, head_y), "TUESDAY  ·  PLAN", MONO(11), fill=AMBER, anchor="la")
    text(d, (inner_l, head_y + 22), "May 5", DISPLAY_B(40), fill=INK, anchor="la")
    text(d, (inner_l, head_y + 76), "MP rhythm session  ·  11 mi.",
         SERIF_IT(15), fill=SLATE, anchor="la")

    # ── Stat strip (NSStatStrip pattern) — Distance · Duration · Load
    strip_y = head_y + 116
    hairline(d, inner_l, strip_y, inner_r, strip_y, fill=HAIR)
    strip_top = strip_y + 16
    n = 2
    cell_w = inner_w / n
    stats = [
        ("DISTANCE", "11.0", "mi"),
        ("DURATION", "75",  "min"),
    ]
    for i, (lab, val, unit) in enumerate(stats):
        cx = inner_l + i*cell_w + cell_w/2
        text(d, (cx, strip_top), lab, MONO(10), fill=SLATE, anchor="ma")
        text(d, (cx, strip_top + 14), val, DISPLAY_B(28), fill=INK, anchor="ma")
        if unit:
            vw = tw(d, val, DISPLAY_B(28))
            text(d, (cx + vw/2 + 4, strip_top + 32), unit, MONO(10), fill=SLATE, anchor="la")
        # vertical divider between cells
        if i > 0:
            divx = inner_l + i*cell_w
            d.line([(divx, strip_top + 2), (divx, strip_top + 52)], fill=HAIR, width=1)
    hairline(d, inner_l, strip_top + 64, inner_r, strip_top + 64, fill=HAIR)

    # ── Heat compensation row ──────────────────────────────
    heat_y = strip_top + 86
    text(d, (inner_l, heat_y), "HEAT", MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_l + 60, heat_y), "·", MONO(10), fill=SLATE_LIGHT, anchor="la")
    text(d, (inner_l + 80, heat_y), "Compensation",
         DISPLAY_B(15), fill=INK, anchor="la")
    # toggle (off — pill outlined, knob left)
    tog_x = inner_r - 38
    tog_y = heat_y - 1
    rounded_box(d, tog_x, tog_y, tog_x + 32, tog_y + 16, 8,
                fill=BONE, outline=SLATE_LIGHT, width=1)
    d.ellipse([tog_x + 2, tog_y + 2, tog_x + 14, tog_y + 14], fill=SLATE_LIGHT)
    text(d, (inner_l, heat_y + 24),
         "Off. Targets stay at coach's prescription.",
         SERIF_IT(13), fill=SLATE, anchor="la")
    hairline(d, inner_l, heat_y + 56, inner_r, heat_y + 56, fill=HAIR)

    # ── Workout steps — journal-style ──────────────────────
    steps_y = heat_y + 78
    text(d, (inner_l, steps_y), "STRUCTURE", MONO(10), fill=SLATE, anchor="la")

    # Each step: a small marker dot + name + pace target + intent quote.
    step_top = steps_y + 24
    step_h = 92
    steps = [
        ("Warm-up",   "2.0 mi",   "6:24–6:56 / mi  ·  EASY",
         "Conversational pace. Settle in.",                        SLATE_LIGHT),
        ("Active",    "7.0 mi",   "5:29 / mi  ·  MP",
         "Goal marathon rhythm — your MP 5:32, −1% today.",        AMBER),
        ("Cool-down", "2.0 mi",   "6:24–6:56 / mi  ·  EASY",
         "Easy jog. Drop the heart rate.",                         SLATE_LIGHT),
    ]
    for i, (name, dist, target, intent, dot_color) in enumerate(steps):
        y = step_top + i*step_h
        # marker dot
        cx, cy = inner_l + 6, y + 12
        r = 5
        d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=dot_color)
        # connector line down to next step
        if i < len(steps) - 1:
            d.line([(cx, cy + r + 2), (cx, y + step_h + 4)],
                   fill=HAIR, width=1)
        body_l = inner_l + 28
        text(d, (body_l, y), name, DISPLAY_B(20), fill=INK, anchor="la")
        text(d, (inner_r, y + 4), dist, DISPLAY_B(18), fill=INK, anchor="ra")
        text(d, (body_l, y + 28), target, MONO(10), fill=SLATE, anchor="la")
        text(d, (body_l, y + 50), intent, SERIF_IT(13), fill=SLATE, anchor="la")
        # divider between steps (skip last)
        if i < len(steps) - 1:
            hairline(d, body_l, y + step_h - 8, inner_r,
                     y + step_h - 8, fill=HAIR)

    # ── Coach note (fills the dead space, gives the sheet a soul) ──
    note_y = step_top + len(steps)*step_h + 20
    text(d, (inner_l, note_y), "FROM YOUR COACH",
         MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_l, note_y + 22),
         "“The 7-mile MP block — second of three this cycle.",
         SERIF_IT(14), fill=INK, anchor="la")
    text(d, (inner_l, note_y + 44),
         "Hold splits, don't chase them. Negative is fine, positive is not.”",
         SERIF_IT(14), fill=INK, anchor="la")

    # ── Bottom actions: editorial text links, not pills ────
    actions_y = sy2 - 162
    hairline(d, inner_l, actions_y, inner_r, actions_y, fill=HAIR)
    # Primary — "Mark complete" set in serif, AMBER, with custom polygon arrow
    primary_y = actions_y + 24
    label = "Mark complete"
    text(d, (inner_l, primary_y), label, DISPLAY_B(20), fill=AMBER, anchor="la")
    # custom polygon up-right arrow (font-independent)
    label_w = tw(d, label, DISPLAY_B(20))
    arrow_up_right(d, inner_l + label_w + 10, primary_y + 4,
                   size=10, fill=AMBER, width=2)
    # underline accent
    d.rectangle([inner_l, primary_y + 28, inner_l + label_w + 24, primary_y + 30],
                fill=AMBER)

    # Secondary actions — small mono links separated by middots
    sec_y = primary_y + 56
    secondary = ["Skip", "Swap", "Replace", "Reschedule", "Export"]
    sec_text = "   ·   ".join(secondary)
    text(d, (inner_l, sec_y), sec_text, MONO(11), fill=SLATE, anchor="la")

    # No tab bar — this is a modal sheet over Plan.
    return img


# ---------------------------------------------------------------------------
# Shared header + stat strip helper for plates 23–25 (workout detail).
# Each variant differs in its chart treatment but uses the same date/stat/
# splits/HR/map structure.
# ---------------------------------------------------------------------------
def _wd_draw_header(d, sx1, sy1, sx2, *, weekday="THURSDAY", date_str="May 7",
                    source_label="Strava"):
    """Editorial header — eyebrow, display date, italic-serif source/distance."""
    handle_y = sy1 + 60
    d.rectangle([sx1 + (sx2-sx1)/2 - 18, handle_y, sx1 + (sx2-sx1)/2 + 18,
                 handle_y + 4], fill=SLATE_LIGHT)
    bar_y = sy1 + 92
    text(d, (sx1+30, bar_y), "Back", MONO(11), fill=AMBER, anchor="la")
    text(d, (sx2-30, bar_y), "Share", MONO(11), fill=AMBER, anchor="ra")
    head_y = bar_y + 30
    text(d, (sx1+30, head_y), f"{weekday}  ·  LOG", MONO(11), fill=AMBER,
         anchor="la")
    text(d, (sx1+30, head_y + 22), date_str, DISPLAY_B(40), fill=INK,
         anchor="la")
    text(d, (sx1+30, head_y + 76),
         f"5.01 mi  ·  35:59  ·  {source_label}",
         SERIF_IT(15), fill=SLATE, anchor="la")
    return head_y + 116  # next y position


def _wd_stat_strip(d, sx1, sx2, y, *, with_load=True, sharpened=False):
    """4-slot stat strip. When sharpened=True, the cells include sub-context
    (elevation alongside distance, GAP alongside pace, delta-vs-typical
    alongside load). Bumps each cell up from a single number to "metric +
    one extra signal" so the strip earns its space."""
    inner_l, inner_r = sx1+30, sx2-30
    inner_w = inner_r - inner_l
    hairline(d, inner_l, y, inner_r, y, fill=HAIR)
    strip_top = y + 16
    if sharpened:
        cells = [
            ("DISTANCE", "5.01",  "mi",   "+55 ft elev"),
            ("DURATION", "35:59", "",     "7:11 avg"),
            ("GAP",      "7:09",  "/mi",  "grade-adjusted"),
            ("LOAD",     "127",   "",     "+12 vs typ"),
        ]
    elif with_load:
        cells = [
            ("DISTANCE", "5.01",  "mi",   None),
            ("DURATION", "35:59", "",     None),
            ("AVG PACE", "7:11",  "/mi",  None),
            ("LOAD",     "127",   "",     None),
        ]
    else:
        cells = [
            ("DISTANCE", "5.01",  "mi",   None),
            ("DURATION", "35:59", "",     None),
            ("AVG PACE", "7:11",  "/mi",  None),
        ]
    n = len(cells)
    cw = inner_w / n
    for i, item in enumerate(cells):
        lab, val, unit, sub = item if len(item) == 4 else (*item, None)
        cx = inner_l + i*cw + cw/2
        text(d, (cx, strip_top), lab, MONO(9), fill=SLATE, anchor="ma")
        text(d, (cx, strip_top + 14), val, DISPLAY_B(24), fill=INK, anchor="ma")
        if unit:
            vw = tw(d, val, DISPLAY_B(24))
            text(d, (cx + vw/2 + 4, strip_top + 30), unit,
                 MONO(9), fill=SLATE, anchor="la")
        if sub:
            text(d, (cx, strip_top + 50), sub, MONO(8),
                 fill=SLATE_LIGHT, anchor="ma")
        if i > 0:
            divx = inner_l + i*cw
            d.line([(divx, strip_top + 2), (divx, strip_top + 60)],
                   fill=HAIR, width=1)
    bottom_y = strip_top + (74 if sharpened else 60)
    hairline(d, inner_l, bottom_y, inner_r, bottom_y, fill=HAIR)
    return bottom_y + 16


def _wd_secondary_stats(d, sx1, sx2, y):
    """Single-row of 5 small secondary stats. Mono labels, mono values.
    Sits below the main stat strip and adds the sharper signals — cadence,
    cardiac drift, efficiency factor, week context."""
    inner_l, inner_r = sx1+30, sx2-30
    inner_w = inner_r - inner_l
    items = [
        ("CADENCE", "178",   "spm"),
        ("DRIFT",   "+2.8%", "Pa:Hr"),
        ("EF",      "1.05",  "pace/HR"),
        ("HR AVG",  "143",   "Z2"),
        ("WEEK",    "4 / 5", "24 mi"),
    ]
    n = len(items)
    cw = inner_w / n
    for i, (lab, val, sub) in enumerate(items):
        cx = inner_l + i*cw + cw/2
        text(d, (cx, y), lab, MONO(8), fill=SLATE, anchor="ma")
        text(d, (cx, y + 14), val, MONO_B(13), fill=INK, anchor="ma")
        text(d, (cx, y + 32), sub, MONO(8), fill=SLATE_LIGHT, anchor="ma")
    return y + 52


def _wd_editorial_rule(d, sx1, sx2, y):
    inner_l, inner_r = sx1+30, sx2-30
    mid = (inner_l + inner_r) / 2
    d.line([(inner_l, y), (mid - 8, y)], fill=HAIR, width=1)
    r = 2
    d.ellipse([mid - r, y - r, mid + r, y + r], fill=HAIR)
    d.line([(mid + 8, y), (inner_r, y)], fill=HAIR, width=1)


def _wd_splits_table(d, sx1, sx2, y, *, highlight_idx=4, sharpened=False):
    """Compact splits table — mi / pace / (GAP) / HR / LOAD / mini bar.

    `sharpened=True` adds two columns (GAP for grade-adjusted pace and
    LOAD per split). The mini bar shrinks to make room.
    """
    inner_l, inner_r = sx1+30, sx2-30
    inner_w = inner_r - inner_l
    text(d, (inner_l, y), "SPLITS", MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_r, y), "fastest 6:34  ·  slowest 7:36",
         MONO(9), fill=SLATE_LIGHT, anchor="ra")

    if sharpened:
        # 6 columns: mi · pace · GAP · HR · LOAD · bar
        col_x = {
            "mi":   inner_l,
            "pace": inner_l + 50,
            "gap":  inner_l + 130,
            "hr":   inner_l + 220,
            "load": inner_l + 280,
            "bar1": inner_l + 340,
            "bar2": inner_r,
        }
    else:
        col_x = {
            "mi":   inner_l,
            "pace": inner_l + 80,
            "bar1": inner_l + 180,
            "bar2": inner_r - 80,
            "hr":   inner_r,
        }

    hr_y = y + 22
    if sharpened:
        text(d, (col_x["mi"],   hr_y), "MI",   MONO(9), fill=SLATE_LIGHT, anchor="la")
        text(d, (col_x["pace"], hr_y), "PACE", MONO(9), fill=SLATE_LIGHT, anchor="la")
        text(d, (col_x["gap"],  hr_y), "GAP",  MONO(9), fill=SLATE_LIGHT, anchor="la")
        text(d, (col_x["hr"],   hr_y), "HR",   MONO(9), fill=SLATE_LIGHT, anchor="la")
        text(d, (col_x["load"], hr_y), "LOAD", MONO(9), fill=SLATE_LIGHT, anchor="la")
    else:
        text(d, (col_x["mi"],   hr_y), "MI",   MONO(9), fill=SLATE_LIGHT, anchor="la")
        text(d, (col_x["pace"], hr_y), "PACE", MONO(9), fill=SLATE_LIGHT, anchor="la")
        text(d, (col_x["hr"],   hr_y), "HR",   MONO(9), fill=SLATE_LIGHT, anchor="ra")
    hairline(d, inner_l, hr_y + 14, inner_r, hr_y + 14, fill=HAIR)

    # mi · pace · gap · hr · load · rel-bar
    splits = [
        (1, "7:36", "7:34", 133, 21, 0.45),
        (2, "7:10", "7:08", 142, 22, 0.62),
        (3, "7:25", "7:24", 143, 21, 0.51),
        (4, "7:11", "7:09", 148, 23, 0.61),
        (5, "6:34", "6:32", 157, 27, 1.00),
        (6, "7:04", "7:01", 155, 13, 0.66),
    ]
    row_h = 30
    for i, (mi, pace, gap, hr, load, rel) in enumerate(splits):
        ry = hr_y + 22 + i*row_h
        is_hi = (i == highlight_idx)
        col = AMBER if is_hi else INK
        text(d, (col_x["mi"],   ry), str(mi),     DISPLAY_B(15), fill=col, anchor="la")
        text(d, (col_x["pace"], ry), pace,        DISPLAY_B(15), fill=col, anchor="la")
        if sharpened:
            text(d, (col_x["gap"], ry),  gap,         MONO(11),      fill=SLATE if not is_hi else AMBER, anchor="la")
            text(d, (col_x["hr"],  ry),  str(hr),     MONO(11),      fill=col, anchor="la")
            text(d, (col_x["load"],ry),  str(load),   MONO_B(11),    fill=col, anchor="la")
            bar_x1 = col_x["bar1"]
            bar_x2 = col_x["bar2"]
        else:
            text(d, (col_x["hr"], ry), str(hr), MONO(11), fill=col, anchor="ra")
            bar_x1 = col_x["bar1"]
            bar_x2 = col_x["bar2"]
        bar_w = (bar_x2 - bar_x1) * rel
        d.rectangle([bar_x1, ry + 8, bar_x1 + bar_w, ry + 14],
                    fill=AMBER if is_hi else SLATE_LIGHT)
        hairline(d, inner_l, ry + row_h - 4,
                 inner_r, ry + row_h - 4, fill=HAIR)
    return hr_y + 22 + len(splits) * row_h + 8


# ---------------------------------------------------------------------------
# PAGE 23 — WORKOUT DETAIL · "Pace, narrated" (sharpened)
# Headline chart: pace × HR dual-line over distance. Sharpened stat strip
# (DISTANCE+elev, DURATION+avg, GAP, LOAD+delta) with a secondary row of
# advanced signals (CADENCE, DRIFT, EF, HR AVG, WEEK). Splits get GAP +
# per-mile LOAD columns. HR-zone distribution bar at the bottom. Closes
# with a single italic-serif weekly-context line.
# ---------------------------------------------------------------------------
def page_23():
    img, d = new_page()
    page_chrome(d, 23,
                "WORKOUT DETAIL · A · sharpened",
                "Pace, narrated",
                ["Workout-detail redesigned in editorial voice — sharpened.",
                 "Pace × HR overlay anchors. GAP, drift, EF in the strip."])
    sx1, sy1, sx2, sy2 = draw_phone(d)
    inner_l, inner_r = sx1 + 30, sx2 - 30
    inner_w = inner_r - inner_l

    y = _wd_draw_header(d, sx1, sy1, sx2)
    y = _wd_stat_strip(d, sx1, sx2, y, sharpened=True)
    y = _wd_secondary_stats(d, sx1, sx2, y)

    _wd_editorial_rule(d, sx1, sx2, y); y += 18

    # ── Pace × HR dual-line chart ──
    text(d, (inner_l, y), "PACE × HR  ·  OVER DISTANCE",
         MONO(10), fill=SLATE, anchor="la")
    # legend right
    legend_x = inner_r - 110
    d.line([(legend_x, y+6), (legend_x+12, y+6)], fill=INK, width=2)
    text(d, (legend_x+16, y), "PACE", MONO(8), fill=SLATE, anchor="la")
    d.line([(legend_x+50, y+6), (legend_x+62, y+6)], fill=AMBER, width=2)
    text(d, (legend_x+66, y), "HR", MONO(8), fill=AMBER, anchor="la")

    chart_top = y + 22
    chart_bot = chart_top + 110
    chart_l = inner_l + 6
    chart_r = inner_r - 6
    chart_w = chart_r - chart_l
    chart_h = chart_bot - chart_top
    # gridline at avg pace
    avg_y = chart_top + chart_h * 0.45
    for x in range(int(chart_l), int(chart_r), 6):
        d.line([(x, avg_y), (x+3, avg_y)], fill=HAIR)
    text(d, (chart_l, avg_y - 12), "AVG 7:11", MONO(8),
         fill=SLATE_LIGHT, anchor="la")
    # pace data — lower = faster = visually higher (inverted scale)
    paces = [7.6, 7.17, 7.42, 7.18, 6.57, 7.07]
    p_mn, p_mx = min(paces) - 0.2, max(paces) + 0.2
    p_pts = []
    for i, p in enumerate(paces):
        px = chart_l + (i / (len(paces) - 1)) * chart_w
        py = chart_top + ((p - p_mn) / (p_mx - p_mn)) * chart_h
        p_pts.append((px, py))
    # HR data — overlaid on same chart, separate scale, ghost line
    hr_per_split = [133, 142, 143, 148, 157, 155]
    h_mn, h_mx = 125, 165
    h_pts = []
    for i, h in enumerate(hr_per_split):
        px = chart_l + (i / (len(hr_per_split) - 1)) * chart_w
        # higher HR = visually higher (top of chart)
        py = chart_top + chart_h - ((h - h_mn) / (h_mx - h_mn)) * chart_h
        h_pts.append((px, py))
    # Draw HR (ghost) BEHIND pace
    for i in range(len(h_pts)-1):
        d.line([h_pts[i], h_pts[i+1]], fill=AMBER, width=1)
    for hx, hy in h_pts:
        d.ellipse([hx-2, hy-2, hx+2, hy+2], fill=AMBER)
    # Draw PACE (foreground)
    for i in range(len(p_pts)-1):
        d.line([p_pts[i], p_pts[i+1]], fill=INK, width=2)
    for i, (px, py) in enumerate(p_pts):
        col = AMBER if i == 4 else INK
        d.ellipse([px-3, py-3, px+3, py+3], fill=col)
    # x-axis labels
    text(d, (chart_l, chart_bot+4), "MI 1", MONO(8),
         fill=SLATE_LIGHT, anchor="la")
    text(d, (chart_r, chart_bot+4), "MI 5", MONO(8),
         fill=SLATE_LIGHT, anchor="ra")
    y = chart_bot + 28

    # italic-serif read — sharper, multi-signal
    text(d, (inner_l, y),
         "Mile 5 at 6:34 — fastest of the run, HR 157 (Z3).",
         SERIF_IT(13), fill=INK, anchor="la")
    text(d, (inner_l, y+18),
         "Negative split −0:30 from mile 1. Cardiac drift +2.8% — aerobic-strong.",
         SERIF_IT(13), fill=SLATE, anchor="la")
    y += 46

    _wd_editorial_rule(d, sx1, sx2, y); y += 14
    y = _wd_splits_table(d, sx1, sx2, y, highlight_idx=4, sharpened=True)

    _wd_editorial_rule(d, sx1, sx2, y); y += 14

    # ── HR Zone distribution ──
    text(d, (inner_l, y), "HR ZONES  ·  TIME IN ZONE",
         MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_r, y), "AVG 143  ·  MAX 162",
         MONO(9), fill=SLATE_LIGHT, anchor="ra")
    zb_y = y + 24
    zb_h = 14
    # Z1 (recovery) → Z5 (max). Demo distribution.
    zones = [
        ("Z1", 0.05, (180,183,187)),    # very light, ~2 min
        ("Z2", 0.40, GREEN_OK),          # easy aerobic
        ("Z3", 0.45, AMBER),             # tempo / aerobic-threshold
        ("Z4", 0.08, (212, 96, 50)),     # threshold
        ("Z5", 0.02, INK),               # max
    ]
    cum = 0
    for lab, pct, col in zones:
        seg_w = inner_w * pct
        d.rectangle([inner_l + cum, zb_y, inner_l + cum + seg_w, zb_y + zb_h],
                    fill=col)
        cum += seg_w
    # tick labels under
    cum = 0
    for lab, pct, col in zones:
        seg_w = inner_w * pct
        cx = inner_l + cum + seg_w/2
        if pct >= 0.04:
            text(d, (cx, zb_y + zb_h + 6), lab, MONO(8),
                 fill=col, anchor="ma")
            mins = round(pct * 36)
            if mins >= 1:
                text(d, (cx, zb_y + zb_h + 20),
                     f"{mins}m", MONO(8), fill=SLATE_LIGHT, anchor="ma")
        cum += seg_w
    y = zb_y + zb_h + 38

    _wd_editorial_rule(d, sx1, sx2, y); y += 14

    # ── Route (editorial map) ──
    text(d, (inner_l, y), "ROUTE", MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_r, y), "GALVESTON  ·  SEAWALL BLVD",
         MONO(9), fill=SLATE_LIGHT, anchor="ra")
    map_top = y + 18
    map_h = 110
    map_bot = map_top + map_h
    # Stylized map background — soft bone fill (slightly different than page
    # bg so the panel reads as a map without using a heavy card).
    d.rectangle([inner_l, map_top, inner_r, map_bot], fill=(238, 234, 224))
    # Sparse grid suggesting streets. Two horizontals + three verticals,
    # all in HAIR — implies a map without simulating one literally.
    for gx_pct in (0.18, 0.42, 0.66, 0.86):
        gx = inner_l + (inner_r - inner_l) * gx_pct
        d.line([(gx, map_top + 4), (gx, map_bot - 4)],
               fill=HAIR, width=1)
    for gy_pct in (0.30, 0.62):
        gy = map_top + map_h * gy_pct
        d.line([(inner_l + 4, gy), (inner_r - 4, gy)],
               fill=HAIR, width=1)
    # Coastline hint — a soft diagonal slate band along the bottom-right
    # to read as water (Galveston Bay analog).
    coast_pts = [
        (inner_l + (inner_r-inner_l)*0.18, map_bot),
        (inner_l + (inner_r-inner_l)*0.45, map_bot - 18),
        (inner_l + (inner_r-inner_l)*0.72, map_bot - 28),
        (inner_r, map_bot - 36),
        (inner_r, map_bot),
    ]
    d.polygon(coast_pts, fill=(225, 224, 220))
    # The route — AMBER line, traced as a wavy out-and-back along the
    # coast. Editorial restraint: no fill, no labels on the map itself.
    route = [
        (0.20, 0.52), (0.30, 0.55), (0.40, 0.58),
        (0.52, 0.62), (0.62, 0.68), (0.72, 0.72),
        (0.80, 0.74),
    ]
    rpts = [(inner_l + (inner_r-inner_l)*x,
             map_top + map_h * y_) for (x, y_) in route]
    for i in range(len(rpts)-1):
        d.line([rpts[i], rpts[i+1]], fill=AMBER, width=3)
    # Start marker (filled green-ok dot)
    sx, sy_ = rpts[0]
    d.ellipse([sx-5, sy_-5, sx+5, sy_+5], fill=GREEN_OK)
    text(d, (sx + 10, sy_ - 6), "START", MONO(8), fill=GREEN_OK, anchor="la")
    # Highlight mile-5 location — a slightly-bigger AMBER dot near
    # the route end so the chart's mile-5 marker is geographically anchored
    ex, ey = rpts[-1]
    d.ellipse([ex-6, ey-6, ex+6, ey+6], fill=AMBER)
    text(d, (ex - 10, ey - 16), "MI 5", MONO(8), fill=AMBER, anchor="ra")
    # Map sub-line — context not chrome
    text(d, (inner_l, map_bot + 8),
         "Out-and-back  ·  +55 ft elev  ·  12 turns",
         MONO(9), fill=SLATE_LIGHT, anchor="la")
    y = map_bot + 30

    _wd_editorial_rule(d, sx1, sx2, y); y += 14

    # ── Weekly context (single italic-serif line) ──
    text(d, (inner_l, y), "WEEKLY CONTEXT", MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_l, y+22),
         "Run 4 of 5 this week. 24.3 mi banked.",
         SERIF_IT(13), fill=INK, anchor="la")
    text(d, (inner_l, y+40),
         "This run added +9% to your chronic load — bringing ACWR to 1.18.",
         SERIF_IT(13), fill=SLATE, anchor="la")
    return img


# ---------------------------------------------------------------------------
# PAGE 24 — WORKOUT DETAIL · "Time in zone"
# Headline chart: stacked-bar of time in each intensity zone, with mini
# pace progression below. Foregrounds the WHAT KIND OF EFFORT question.
# ---------------------------------------------------------------------------
def page_24():
    img, d = new_page()
    page_chrome(d, 24,
                "WORKOUT DETAIL · B",
                "Effort, distributed",
                ["Time-in-zone foregrounds intensity. The same data the new",
                 "load metric is computed from — surfaced honestly."])
    sx1, sy1, sx2, sy2 = draw_phone(d)
    inner_l, inner_r = sx1 + 30, sx2 - 30
    inner_w = inner_r - inner_l

    y = _wd_draw_header(d, sx1, sy1, sx2)
    y = _wd_stat_strip(d, sx1, sx2, y, with_load=True)

    _wd_editorial_rule(d, sx1, sx2, y); y += 24

    # ── Time-in-zone bars ──
    text(d, (inner_l, y), "TIME IN ZONE", MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_r, y), "TOTAL 35:59", MONO(10), fill=SLATE_LIGHT, anchor="ra")
    zones = [
        ("EASY",       72, 26.0, SLATE_LIGHT),     # 26 min
        ("MODERATE",   20, 7.2,  SLATE),
        ("THRESHOLD",  6,  2.2,  AMBER),
        ("HARD",       2,  0.6,  INK),
    ]
    bar_y = y + 24
    bar_h = 28
    bar_x = inner_l
    bar_w_full = inner_w
    cum = 0
    for lab, pct, mins, col in zones:
        seg_w = bar_w_full * (pct / 100)
        d.rectangle([bar_x + cum, bar_y, bar_x + cum + seg_w, bar_y + bar_h],
                    fill=col)
        cum += seg_w
    # zone labels under bar
    cum = 0
    label_y = bar_y + bar_h + 6
    for lab, pct, mins, col in zones:
        seg_w = bar_w_full * (pct / 100)
        cx = bar_x + cum + seg_w/2
        text(d, (cx, label_y), lab, MONO(8), fill=col, anchor="ma")
        text(d, (cx, label_y + 14), f"{int(mins)}min",
             DISPLAY_B(13), fill=INK, anchor="ma")
        text(d, (cx, label_y + 32), f"{pct}%", MONO(8),
             fill=SLATE_LIGHT, anchor="ma")
        cum += seg_w
    y = bar_y + bar_h + 64

    # italic-serif read
    text(d, (inner_l, y),
         "Mostly aerobic. One short threshold push at mile 5.",
         SERIF_IT(13), fill=INK, anchor="la")
    text(d, (inner_l, y+18),
         "127 weighted-min adds 9% to this week's chronic load.",
         SERIF_IT(13), fill=SLATE, anchor="la")
    y += 48

    _wd_editorial_rule(d, sx1, sx2, y); y += 16

    # ── Mini pace progression below ──
    text(d, (inner_l, y), "PACE PROGRESSION", MONO(10), fill=SLATE, anchor="la")
    chart_top = y + 18
    chart_h = 60
    chart_l = inner_l + 6
    chart_r = inner_r - 6
    chart_w = chart_r - chart_l
    paces = [7.6, 7.17, 7.42, 7.18, 6.57, 7.07]
    mn, mx = min(paces) - 0.2, max(paces) + 0.2
    pts = []
    for i, p in enumerate(paces):
        px = chart_l + (i / (len(paces) - 1)) * chart_w
        py = chart_top + ((p - mn) / (mx - mn)) * chart_h
        pts.append((px, py))
    for i in range(len(pts)-1):
        d.line([pts[i], pts[i+1]], fill=INK, width=2)
    for i, (px, py) in enumerate(pts):
        col = AMBER if i == 4 else INK
        d.ellipse([px-3, py-3, px+3, py+3], fill=col)
    y = chart_top + chart_h + 16

    _wd_editorial_rule(d, sx1, sx2, y); y += 16
    y = _wd_splits_table(d, sx1, sx2, y, highlight_idx=4)
    return img


# ---------------------------------------------------------------------------
# PAGE 25 — WORKOUT DETAIL · "Vs your typical"
# Headline chart: pace progression with TYPICAL band overlay (your average
# at this distance), plus a comparison-row at the top. Most analytical of
# the three — for athletes who want context.
# ---------------------------------------------------------------------------
def page_25():
    img, d = new_page()
    page_chrome(d, 25,
                "WORKOUT DETAIL · C",
                "Compared to typical",
                ["Compares this run against your last 4 similar-distance runs.",
                 "Pace band, HR drift, load contribution — context as data."])
    sx1, sy1, sx2, sy2 = draw_phone(d)
    inner_l, inner_r = sx1 + 30, sx2 - 30
    inner_w = inner_r - inner_l

    y = _wd_draw_header(d, sx1, sy1, sx2)
    y = _wd_stat_strip(d, sx1, sx2, y, with_load=True)

    _wd_editorial_rule(d, sx1, sx2, y); y += 24

    # ── "Vs your typical" delta row ──
    text(d, (inner_l, y), "VS YOUR LAST 4 SIMILAR RUNS",
         MONO(10), fill=SLATE, anchor="la")
    cmp_top = y + 22
    cmp_w = inner_w / 4
    deltas = [
        ("PACE",     "−0:14", GREEN_OK,  "faster"),
        ("HR DRIFT", "+5%",   AMBER,     "moderate"),
        ("LOAD",     "+12",   AMBER,     "above"),
        ("EFFORT",   "1.05",  AMBER,     "EF · efficiency factor"),
    ]
    for i, (lab, val, col, sub) in enumerate(deltas):
        cx = inner_l + i*cmp_w
        text(d, (cx, cmp_top), lab, MONO(9), fill=SLATE, anchor="la")
        text(d, (cx, cmp_top + 14), val,
             DISPLAY_B(20), fill=col, anchor="la")
        text(d, (cx, cmp_top + 40), sub, MONO(8),
             fill=SLATE_LIGHT, anchor="la")
    y = cmp_top + 64

    _wd_editorial_rule(d, sx1, sx2, y); y += 16

    # ── Pace progression with typical-band overlay ──
    text(d, (inner_l, y), "PACE  ·  YOU vs TYPICAL",
         MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_r, y), "TYPICAL: 7:25 ± 0:18",
         MONO(9), fill=SLATE_LIGHT, anchor="ra")
    chart_top = y + 20
    chart_bot = chart_top + 110
    chart_l = inner_l + 6
    chart_r = inner_r - 6
    chart_w = chart_r - chart_l
    chart_h = chart_bot - chart_top
    # typical band — shaded rectangle representing 7:25 ± 0:18
    typ_lo = 7.12
    typ_hi = 7.72
    # paces inverted so faster = higher
    all_paces = [7.6, 7.17, 7.42, 7.18, 6.57, 7.07, typ_lo, typ_hi]
    mn = min(all_paces) - 0.15
    mx = max(all_paces) + 0.15
    band_top_y = chart_top + ((typ_lo - mn) / (mx - mn)) * chart_h
    band_bot_y = chart_top + ((typ_hi - mn) / (mx - mn)) * chart_h
    d.rectangle([chart_l, band_top_y, chart_r, band_bot_y],
                fill=(232, 228, 218))
    text(d, (chart_l + 4, band_top_y + 2), "TYPICAL BAND",
         MONO(8), fill=SLATE_LIGHT, anchor="la")
    # actual run
    paces = [7.6, 7.17, 7.42, 7.18, 6.57, 7.07]
    pts = []
    for i, p in enumerate(paces):
        px = chart_l + (i / (len(paces) - 1)) * chart_w
        py = chart_top + ((p - mn) / (mx - mn)) * chart_h
        pts.append((px, py))
    for i in range(len(pts)-1):
        d.line([pts[i], pts[i+1]], fill=INK, width=2)
    for i, (px, py) in enumerate(pts):
        col = AMBER if i == 4 else INK
        d.ellipse([px-3, py-3, px+3, py+3], fill=col)
    text(d, (chart_l, chart_bot+4), "MI 1", MONO(8), fill=SLATE_LIGHT, anchor="la")
    text(d, (chart_r, chart_bot+4), "MI 5", MONO(8), fill=SLATE_LIGHT, anchor="ra")
    y = chart_bot + 28

    text(d, (inner_l, y),
         "Faster than typical the whole way — meaningfully so at mile 5.",
         SERIF_IT(13), fill=INK, anchor="la")
    text(d, (inner_l, y+18),
         "HR drift +5% — within normal aerobic range.",
         SERIF_IT(13), fill=SLATE, anchor="la")
    y += 48

    _wd_editorial_rule(d, sx1, sx2, y); y += 16
    y = _wd_splits_table(d, sx1, sx2, y, highlight_idx=4)
    return img


# ---------------------------------------------------------------------------
# PAGE 26 — TRAINING TAB · DAILY INTENSITY EXPANDED
# Demonstrates the daily-cell tap interaction. The 28-day grid stays in
# place, the tapped day gets an AMBER ring, and an editorial expansion
# panel slides in below showing that day's workout in full — type,
# pace, mile splits, coach insight, link to full detail.
# ---------------------------------------------------------------------------
def page_26():
    img, d = new_page()
    page_chrome(d, 26,
                "TRAINING · INTERACTIVE",
                "Day, expanded",
                ["Daily-intensity grid stays put. Tapped cell gets the ring,",
                 "the day's workout slides in below. Tap again to collapse."])
    sx1, sy1, sx2, sy2 = draw_phone(d)
    inner_l = sx1 + 30
    inner_r = sx2 - 30
    inner_w = inner_r - inner_l

    # ── Header ─────────────────────────────────────────────
    head_y = sy1 + 90
    text(d, (inner_l, head_y), "TRAINING  ·  28-DAY VIEW",
         MONO(11), fill=AMBER, anchor="la")
    text(d, (inner_l, head_y + 22), "Daily intensity",
         DISPLAY_B(28), fill=INK, anchor="la")
    hairline(d, inner_l, head_y + 64, inner_r, head_y + 64, fill=HAIR)

    # ── Grid ───────────────────────────────────────────────
    grid_top = head_y + 80
    text(d, (inner_l, grid_top),
         "DAILY INTENSITY  ·  28 DAYS  ·  TAP A DAY",
         MONO(10), fill=SLATE, anchor="la")
    # Day-of-week column headers
    label_y = grid_top + 22
    week_label_w = 36
    cell_gap = 4
    cell_w = (inner_w - week_label_w - 6 * cell_gap) / 7
    cell_h = 30
    days = ["M", "T", "W", "Th", "F", "Sa", "Su"]
    for i, day in enumerate(days):
        cx = inner_l + week_label_w + i * (cell_w + cell_gap) + cell_w / 2
        text(d, (cx, label_y), day, MONO(9), fill=SLATE_LIGHT, anchor="ma")
    # 4 rows × 7 cols
    week_labels = ["Wk-3", "Wk-2", "Wk-1", "This"]
    # Each cell: (load_value or None, color category)
    # Categories → colors. Easy/Long = greens, Tempo/Intervals = corals, Rest/empty = bone
    GREEN_LIGHT = (180, 215, 195)
    GREEN_OK  = (90, 138, 109)
    CORAL_LIGHT = (242, 198, 175)
    CORAL_DARK  = (213, 105, 60)
    BONE_FAINT  = (235, 232, 222)

    grid_data = [
        # Wk-3
        [(8, CORAL_LIGHT), (19, CORAL_LIGHT), (14, CORAL_LIGHT),
         (16, GREEN_OK),    # ← clicked Thursday (long run)
         (7, GREEN_LIGHT), (12, GREEN_OK), (14, CORAL_LIGHT)],
        # Wk-2
        [(12, CORAL_LIGHT), (17, CORAL_LIGHT), (8, CORAL_LIGHT),
         (18, CORAL_LIGHT), (None, BONE_FAINT), (None, BONE_FAINT), (12, CORAL_LIGHT)],
        # Wk-1
        [(4, GREEN_LIGHT), (9, GREEN_LIGHT), (None, BONE_FAINT),
         (4, GREEN_LIGHT), (None, BONE_FAINT), (1, GREEN_LIGHT), (4, GREEN_LIGHT)],
        # This week
        [(7, GREEN_LIGHT), (10, GREEN_LIGHT), (8, GREEN_LIGHT),
         (10, GREEN_LIGHT), (None, BONE_FAINT), (None, BONE_FAINT), (None, BONE_FAINT)],
    ]

    SELECTED_ROW, SELECTED_COL = 0, 3   # Wk-3 Thursday
    grid_top_cells = label_y + 18
    for r, row in enumerate(grid_data):
        ry = grid_top_cells + r * (cell_h + cell_gap)
        text(d, (inner_l, ry + cell_h/2 - 5), week_labels[r],
             MONO(9), fill=SLATE_LIGHT, anchor="la")
        for c, (val, color) in enumerate(row):
            cx1 = inner_l + week_label_w + c * (cell_w + cell_gap)
            cx2 = cx1 + cell_w
            cy1 = ry
            cy2 = cy1 + cell_h
            rounded_box(d, cx1, cy1, cx2, cy2, 4, fill=color)
            if val is not None:
                text(d, ((cx1+cx2)/2, (cy1+cy2)/2 - 5), str(val),
                     DISPLAY_B(12),
                     fill=INK if color in (GREEN_LIGHT, CORAL_LIGHT, BONE_FAINT)
                             else (250, 245, 235),
                     anchor="ma")
            else:
                text(d, ((cx1+cx2)/2, (cy1+cy2)/2 - 4), "·",
                     MONO(8), fill=SLATE_LIGHT, anchor="ma")
            # Selected cell gets an AMBER 2px ring
            if r == SELECTED_ROW and c == SELECTED_COL:
                d.rectangle([cx1-2, cy1-2, cx2+2, cy2+2],
                            outline=AMBER, width=3)

    grid_bot = grid_top_cells + 4 * (cell_h + cell_gap)

    # ── Expansion panel ────────────────────────────────────
    # The workout is *embedded* here — pace × HR chart, full splits,
    # HR zones, route — same shape as the workout-detail page (Plate 23)
    # but folded into the Training-tab flow. No "View full workout" drill
    # out; this IS the workout view, with the 28-day grid still visible
    # above for context-switching.
    exp_top = grid_bot + 18
    panel_h = 600
    panel_bg = (238, 234, 224)
    rounded_box(d, inner_l - 4, exp_top, inner_r + 4,
                exp_top + panel_h, 8, fill=panel_bg)
    pad = 16
    px_l = inner_l - 4 + pad
    px_r = inner_r + 4 - pad
    panel_w = px_r - px_l

    # Top bar — date eyebrow + close hint
    text(d, (px_l, exp_top + pad), "THURSDAY  ·  APR 30",
         MONO(10), fill=AMBER, anchor="la")
    text(d, (px_r, exp_top + pad), "TAP TO COLLAPSE",
         MONO(8), fill=SLATE_LIGHT, anchor="ra")
    # Headline
    text(d, (px_l, exp_top + pad + 22), "Long run, 16 mi.",
         DISPLAY_B(24), fill=INK, anchor="la")
    text(d, (px_l, exp_top + pad + 56),
         "1:55:32  ·  7:13 / mi  ·  LOAD 135  ·  POSITIVE",
         MONO(10), fill=SLATE, anchor="la")

    # ── Pace × HR chart (embedded from workout detail) ──
    chart_eyebrow_y = exp_top + pad + 90
    text(d, (px_l, chart_eyebrow_y), "PACE × HR  ·  OVER DISTANCE",
         MONO(9), fill=SLATE, anchor="la")
    text(d, (px_r, chart_eyebrow_y), "AVG 7:13  ·  HR 142",
         MONO(8), fill=SLATE_LIGHT, anchor="ra")
    chart_top = chart_eyebrow_y + 18
    chart_h = 90
    chart_l_x = px_l + 4
    chart_r_x = px_r - 4
    chart_w = chart_r_x - chart_l_x
    # avg pace gridline
    avg_y = chart_top + chart_h * 0.5
    for x in range(int(chart_l_x), int(chart_r_x), 6):
        d.line([(x, avg_y), (x+3, avg_y)], fill=HAIR)
    # 16 mile pace points (lower=faster=visually higher)
    paces = [7.20, 7.10, 7.18, 7.12, 7.05, 7.22, 7.15, 7.08,
             7.14, 7.10, 7.18, 7.20, 7.16, 7.14, 7.18, 7.10]
    p_mn, p_mx = min(paces) - 0.10, max(paces) + 0.10
    p_pts = []
    for i, p in enumerate(paces):
        x = chart_l_x + (i / (len(paces) - 1)) * chart_w
        y = chart_top + ((p - p_mn) / (p_mx - p_mn)) * chart_h
        p_pts.append((x, y))
    # HR over the run (overlaid as ghost AMBER line)
    hr = [128, 134, 138, 140, 141, 143, 144, 142, 145, 144, 146, 148,
          147, 145, 148, 142]
    h_mn, h_mx = 125, 152
    h_pts = []
    for i, hv in enumerate(hr):
        x = chart_l_x + (i / (len(hr) - 1)) * chart_w
        y = chart_top + chart_h - ((hv - h_mn) / (h_mx - h_mn)) * chart_h
        h_pts.append((x, y))
    for i in range(len(h_pts) - 1):
        d.line([h_pts[i], h_pts[i+1]], fill=AMBER, width=1)
    # pace foreground
    for i in range(len(p_pts) - 1):
        d.line([p_pts[i], p_pts[i+1]], fill=INK, width=2)
    for px_dot, py_dot in p_pts:
        d.ellipse([px_dot-2, py_dot-2, px_dot+2, py_dot+2], fill=INK)
    # tiny axis labels
    text(d, (chart_l_x, chart_top + chart_h + 4), "MI 1",
         MONO(8), fill=SLATE_LIGHT, anchor="la")
    text(d, (chart_r_x, chart_top + chart_h + 4), "MI 16",
         MONO(8), fill=SLATE_LIGHT, anchor="ra")

    # ── HR Zones inline strip ──
    hz_y = chart_top + chart_h + 28
    text(d, (px_l, hz_y), "HR ZONES",
         MONO(9), fill=SLATE, anchor="la")
    text(d, (px_r, hz_y), "MAX 152",
         MONO(8), fill=SLATE_LIGHT, anchor="ra")
    hz_bar_y = hz_y + 16
    hz_h = 10
    zones = [
        (0.06, (180, 183, 187)),    # Z1
        (0.62, GREEN_OK),           # Z2
        (0.28, AMBER),              # Z3
        (0.04, (212, 96, 50)),      # Z4
    ]
    cum = 0
    for pct, col in zones:
        seg_w = panel_w * pct
        d.rectangle([px_l + cum, hz_bar_y, px_l + cum + seg_w, hz_bar_y + hz_h],
                    fill=col)
        cum += seg_w
    text(d, (px_l, hz_bar_y + hz_h + 6),
         "Z1 · 7m   Z2 · 71m   Z3 · 32m   Z4 · 5m",
         MONO(8), fill=SLATE_LIGHT, anchor="la")

    # ── Route mini-strip + IN CONTEXT comparison ──
    # Route stays a small editorial map snippet, IN CONTEXT continues to
    # do the comparison work that justifies inlining (vs full page).
    route_y = hz_bar_y + hz_h + 32
    text(d, (px_l, route_y), "ROUTE",
         MONO(9), fill=SLATE, anchor="la")
    text(d, (px_r, route_y), "GALVESTON  ·  +112 ft",
         MONO(8), fill=SLATE_LIGHT, anchor="ra")
    map_top_y = route_y + 14
    map_h_inset = 50
    # neutral basemap inset
    rounded_box(d, px_l, map_top_y, px_r, map_top_y + map_h_inset, 4,
                fill=(232, 228, 218))
    # subtle grid
    for gx_pct in (0.20, 0.42, 0.66, 0.86):
        gx = px_l + panel_w * gx_pct
        d.line([(gx, map_top_y + 2), (gx, map_top_y + map_h_inset - 2)],
               fill=HAIR, width=1)
    # route line
    rpts = [
        (0.10, 0.40), (0.20, 0.45), (0.32, 0.55),
        (0.46, 0.62), (0.60, 0.66), (0.74, 0.62),
        (0.86, 0.50), (0.90, 0.40),
    ]
    rcoords = [(px_l + panel_w*x, map_top_y + map_h_inset*y)
               for (x, y) in rpts]
    for i in range(len(rcoords)-1):
        d.line([rcoords[i], rcoords[i+1]], fill=AMBER, width=2)
    sx_dot, sy_dot = rcoords[0]
    d.ellipse([sx_dot-3, sy_dot-3, sx_dot+3, sy_dot+3], fill=GREEN_OK)
    ex_dot, ey_dot = rcoords[-1]
    d.ellipse([ex_dot-3, ey_dot-3, ex_dot+3, ey_dot+3], fill=AMBER)

    # In-context comparison lines
    insight_y = map_top_y + map_h_inset + 24
    text(d, (px_l, insight_y), "IN CONTEXT",
         MONO(9), fill=SLATE, anchor="la")
    text(d, (px_l, insight_y + 18),
         "Heaviest day of the block. +6 mi over the next-longest.",
         SERIF_IT(13), fill=INK, anchor="la")
    text(d, (px_l, insight_y + 36),
         "Splits within 0:08 of average — strong rhythm, no fade.",
         SERIF_IT(13), fill=INK, anchor="la")
    text(d, (px_l, insight_y + 54),
         "—— biggest single-session load of the 28-day block.",
         SERIF_IT(13), fill=SLATE, anchor="la")

    # ── Legend ──────────────────────────────────
    leg_y = exp_top + panel_h + 18
    legend = [
        ("Easy", GREEN_LIGHT),
        ("Long", GREEN_OK),
        ("Tempo", CORAL_LIGHT),
        ("Intervals", CORAL_DARK),
        ("Rest", BONE_FAINT),
    ]
    lx = inner_l
    for label, color in legend:
        d.ellipse([lx, leg_y, lx+10, leg_y+10], fill=color)
        text(d, (lx+16, leg_y-2), label, MONO(9),
             fill=SLATE, anchor="la")
        lx += 16 + tw(d, label, MONO(9)) + 16

    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=1)
    return img


# ---------------------------------------------------------------------------
# PAGE 27 — TRAINING TAB · WEEKLY LOAD EXPANDED
# Demonstrates the weekly-bar tap interaction. The four weekly mileage
# bars stay; the tapped week gets a darker AMBER fill and an expansion
# panel below shows breakdown — zone composition, day-by-day, key
# session, comparison to plan, link through to a week detail screen.
# ---------------------------------------------------------------------------
def page_27():
    img, d = new_page()
    page_chrome(d, 27,
                "TRAINING · INTERACTIVE",
                "Week, expanded",
                ["Weekly bars stay. Tapped week fills, breakdown drops in",
                 "below — zone mix, day-by-day, key session, vs plan."])
    sx1, sy1, sx2, sy2 = draw_phone(d)
    inner_l = sx1 + 30
    inner_r = sx2 - 30
    inner_w = inner_r - inner_l

    # ── Header ─────────────────────────────────────────────
    head_y = sy1 + 90
    text(d, (inner_l, head_y), "TRAINING  ·  28-DAY VIEW",
         MONO(11), fill=AMBER, anchor="la")
    text(d, (inner_l, head_y + 22), "Weekly load",
         DISPLAY_B(28), fill=INK, anchor="la")
    hairline(d, inner_l, head_y + 64, inner_r, head_y + 64, fill=HAIR)

    # ── Bars ───────────────────────────────────────────────
    bar_top = head_y + 80
    text(d, (inner_l, bar_top),
         "WEEKLY LOAD  ·  TAP A WEEK",
         MONO(10), fill=SLATE, anchor="la")

    week_data = [
        ("Wk-3", 91, "APR 21 – APR 27", True),    # ← selected
        ("Wk-2", 68, "APR 28 – MAY 4", False),
        ("Wk-1", 21, "MAY 5 – MAY 11", False),
        ("This", 35, "THIS WEEK", False),
    ]
    bar_h = 26
    bar_gap = 8
    bar_y = bar_top + 22
    label_w = 50
    bar_x1 = inner_l + label_w
    bar_x2 = inner_r
    bar_w_full = bar_x2 - bar_x1
    max_miles = 100  # scale ceiling

    for i, (label, miles, date_range, is_sel) in enumerate(week_data):
        ry = bar_y + i * (bar_h + bar_gap)
        text(d, (inner_l, ry + bar_h/2 - 6), label,
             MONO(10), fill=SLATE if not is_sel else AMBER, anchor="la")
        # background track
        rounded_box(d, bar_x1, ry, bar_x2, ry + bar_h, 4,
                    fill=(238, 234, 224))
        # filled portion
        fill_w = bar_w_full * (miles / max_miles)
        col = AMBER if is_sel else (242, 198, 175)
        rounded_box(d, bar_x1, ry, bar_x1 + fill_w, ry + bar_h, 4,
                    fill=col)
        # miles label inside or right of fill
        if fill_w > 100:
            text(d, (bar_x1 + fill_w - 8, ry + bar_h/2 - 6),
                 f"{miles} mi", MONO_B(11),
                 fill=(250, 245, 235), anchor="ra")
        else:
            text(d, (bar_x1 + fill_w + 8, ry + bar_h/2 - 6),
                 f"{miles} mi", MONO(11),
                 fill=INK, anchor="la")
    bars_bot = bar_y + 4 * (bar_h + bar_gap)

    # ── Expansion panel ────────────────────────────────────
    exp_top = bars_bot + 18
    panel_h = 360
    panel_bg = (238, 234, 224)
    rounded_box(d, inner_l - 4, exp_top, inner_r + 4,
                exp_top + panel_h, 8, fill=panel_bg)
    pad = 16
    px_l = inner_l - 4 + pad
    px_r = inner_r + 4 - pad

    # Top bar — date eyebrow + close hint
    text(d, (px_l, exp_top + pad), "WEEK 17  ·  APR 21 – APR 27",
         MONO(10), fill=AMBER, anchor="la")
    text(d, (px_r, exp_top + pad), "TAP TO COLLAPSE",
         MONO(8), fill=SLATE_LIGHT, anchor="ra")
    # Headline
    text(d, (px_l, exp_top + pad + 22), "91 mi  ·  7 runs",
         DISPLAY_B(24), fill=INK, anchor="la")
    # Sub: load + vs plan + ACWR
    text(d, (px_l, exp_top + pad + 56),
         "LOAD 612  ·  Plan was 88 mi, +3 over  ·  ACWR 1.18.",
         MONO(10), fill=SLATE, anchor="la")

    # Zone composition stacked bar
    zone_y = exp_top + pad + 90
    text(d, (px_l, zone_y), "ZONE MIX  ·  WEEK TOTAL",
         MONO(9), fill=SLATE, anchor="la")
    zb_y = zone_y + 18
    zb_h = 16
    zones = [
        ("EASY",      0.68, (180, 215, 195)),
        ("MODERATE",  0.18, SLATE),
        ("THRESHOLD", 0.10, AMBER),
        ("HARD",      0.04, INK),
    ]
    cum = 0
    band_w = px_r - px_l
    for lab, pct, col in zones:
        seg_w = band_w * pct
        d.rectangle([px_l + cum, zb_y, px_l + cum + seg_w, zb_y + zb_h],
                    fill=col)
        cum += seg_w
    # zone % labels
    cum = 0
    for lab, pct, col in zones:
        seg_w = band_w * pct
        cx = px_l + cum + seg_w / 2
        if pct >= 0.06:
            text(d, (cx, zb_y + zb_h + 4), lab, MONO(8),
                 fill=col, anchor="ma")
        cum += seg_w

    # 7-day timeline
    tl_y = zb_y + zb_h + 38
    text(d, (px_l, tl_y), "DAY BY DAY",
         MONO(9), fill=SLATE, anchor="la")
    tl_top = tl_y + 18
    days = ["M", "T", "W", "Th", "F", "Sa", "Su"]
    miles_by_day = [12, 18, 8, 15, 6, 12, 20]
    workout_type_by_day = ["EASY", "TEMPO", "EASY", "INTERVALS", "EASY", "EASY", "LONG"]
    type_color = {
        "EASY": (180, 215, 195),
        "LONG": GREEN_OK,
        "TEMPO": (242, 198, 175),
        "INTERVALS": AMBER,
        "REST": (235, 232, 222),
    }
    n_days = 7
    day_cell_w = (band_w - 6 * 4) / 7
    day_cell_h = 50
    for i, day in enumerate(days):
        cx1 = px_l + i * (day_cell_w + 4)
        cy1 = tl_top
        cy2 = cy1 + day_cell_h
        miles = miles_by_day[i]
        type_lab = workout_type_by_day[i]
        rounded_box(d, cx1, cy1, cx1 + day_cell_w, cy2, 4,
                    fill=type_color.get(type_lab, (235, 232, 222)))
        text(d, (cx1 + day_cell_w/2, cy1 + 4), day, MONO(8),
             fill=SLATE, anchor="ma")
        text(d, (cx1 + day_cell_w/2, cy1 + 18), str(miles),
             DISPLAY_B(14), fill=INK, anchor="ma")
        text(d, (cx1 + day_cell_w/2, cy1 + 36), "mi",
             MONO(7), fill=SLATE, anchor="ma")

    # Key session callout
    key_y = tl_top + day_cell_h + 24
    text(d, (px_l, key_y), "KEY SESSION",
         MONO(9), fill=SLATE, anchor="la")
    text(d, (px_l, key_y + 18),
         "Sun · 20 mi long with 8 mi at MP — 158 weighted-min.",
         SERIF_IT(13), fill=INK, anchor="la")

    # Action link
    action_y = key_y + 50
    arrow_up_right(d, px_l + 100, action_y + 4, size=10, fill=AMBER, width=2)
    text(d, (px_l, action_y), "View week",
         DISPLAY_B(15), fill=AMBER, anchor="la")
    label_w_v = tw(d, "View week", DISPLAY_B(15))
    d.rectangle([px_l, action_y + 22, px_l + label_w_v + 22, action_y + 23],
                fill=AMBER)

    tab_bar(d, sx1, sy1, sx2, sy2, active_idx=1)
    return img


# ---------------------------------------------------------------------------
# PAGE 28 — INJURY LIST · editorial redesign
# Replaces the icon-heavy card list with an editorial injury ledger.
# Each entry surfaces voice-log mentions correlated to training context
# (volume, pace, load when the ache came up). Disclaimer becomes a quiet
# italic-serif line — still legally present, not visually shouting.
# ---------------------------------------------------------------------------
def page_28():
    img, d = new_page()
    page_chrome(d, 28,
                "INJURY · LIVING LOG",
                "Active aches",
                ["Voice-log mentions correlated to volume, pace, and load.",
                 "Liability disclaimer present, never shouting."])
    sx1, sy1, sx2, sy2 = draw_phone(d)
    inner_l = sx1 + 30
    inner_r = sx2 - 30
    inner_w = inner_r - inner_l

    # Sheet handle + dismiss
    handle_y = sy1 + 60
    d.rectangle([sx1 + (sx2-sx1)/2 - 18, handle_y, sx1 + (sx2-sx1)/2 + 18,
                 handle_y + 4], fill=SLATE_LIGHT)
    bar_y = sy1 + 92
    text(d, (inner_l, bar_y), "Close", MONO(11), fill=AMBER, anchor="la")
    text(d, ((sx1+sx2)/2, bar_y), "INJURIES",
         MONO(11), fill=SLATE, anchor="ma")
    text(d, (inner_r, bar_y), "+ ADD",
         MONO(11), fill=AMBER, anchor="ra")

    # ── Header (editorial) ──
    head_y = bar_y + 30
    text(d, (inner_l, head_y), "TRACKING NOW  ·  2",
         MONO(11), fill=AMBER, anchor="la")
    text(d, (inner_l, head_y + 22), "Active aches",
         DISPLAY_B(28), fill=INK, anchor="la")
    text(d, (inner_l, head_y + 60),
         "Not medical advice. If anything gets sharper, see a clinician.",
         SERIF_IT(13), fill=SLATE, anchor="la")
    hairline(d, inner_l, head_y + 96, inner_r, head_y + 96, fill=HAIR)

    def _wd_rule(d, y):
        mid = (inner_l + inner_r) / 2
        d.line([(inner_l, y), (mid - 6, y)], fill=HAIR, width=1)
        d.ellipse([mid-2, y-2, mid+2, y+2], fill=HAIR)
        d.line([(mid + 6, y), (inner_r, y)], fill=HAIR, width=1)

    # ── Injury entry helper ──
    def injury_entry(y, *, name, side, severity, first_mentioned,
                     days_active, mention_count, avg_vol, avg_load,
                     trend, quote, mention_dots, severity_color=AMBER):
        # Top row — name + severity + side + status
        text(d, (inner_l, y), name, DISPLAY_B(22), fill=INK, anchor="la")
        # severity number AMBER pill-like
        sev_x = inner_r - 60
        text(d, (sev_x, y + 6), f"{severity} / 10",
             MONO_B(12), fill=severity_color, anchor="la")
        # side line
        text(d, (inner_l, y + 28),
             f"{side}  ·  ACTIVE  ·  {days_active}d",
             MONO(10), fill=SLATE, anchor="la")

        # Data strip — small mono-stat row
        strip_y = y + 56
        items = [
            ("MENTIONS",  f"{mention_count}×"),
            ("AVG VOL",   f"{avg_vol} mi"),
            ("AVG LOAD",  f"{avg_load}"),
            ("TREND",     trend),
        ]
        cw = inner_w / len(items)
        for i, (lab, val) in enumerate(items):
            cx = inner_l + i*cw
            text(d, (cx, strip_y), lab, MONO(8), fill=SLATE_LIGHT, anchor="la")
            color = INK
            if i == 3:  # trend
                color = AMBER if "easing" in val.lower() else (
                    INK if "steady" in val.lower() else
                    (212, 96, 50)
                )
            text(d, (cx, strip_y + 14), val, MONO_B(12), fill=color, anchor="la")

        # Mention dots — last 14 days, dot per day, AMBER on mentioned days
        dots_y = strip_y + 42
        text(d, (inner_l, dots_y), "MENTIONS  ·  LAST 14 DAYS",
             MONO(8), fill=SLATE_LIGHT, anchor="la")
        dy = dots_y + 16
        dot_gap = inner_w / 14
        dot_r = 3
        for di in range(14):
            cx = inner_l + dot_gap * di + dot_gap/2
            mentioned = di in mention_dots
            color = AMBER if mentioned else SLATE_LIGHT
            if mentioned:
                d.ellipse([cx-dot_r, dy-dot_r, cx+dot_r, dy+dot_r], fill=color)
            else:
                d.ellipse([cx-1, dy-1, cx+1, dy+1], fill=color)

        # Italic-serif quote — most recent log mention
        quote_y = dy + 22
        text(d, (inner_l, quote_y), "LAST MENTIONED",
             MONO(8), fill=SLATE_LIGHT, anchor="la")
        text(d, (inner_l, quote_y + 16),
             f"“{quote}”",
             SERIF_IT(13), fill=INK, anchor="la")
        text(d, (inner_l, quote_y + 36), first_mentioned,
             MONO(9), fill=SLATE_LIGHT, anchor="la")

        # Action links (small mono)
        action_y = quote_y + 60
        text(d, (inner_l, action_y), "View detail  ·  Update  ·  Mark resolved",
             MONO(10), fill=SLATE, anchor="la")
        return action_y + 24

    # ── Entry 1: Knee ──
    y = head_y + 116
    y = injury_entry(y,
        name="Knee",
        side="LEFT",
        severity=3,
        first_mentioned="First came up — Sat May 3, after 8mi long.",
        days_active=5,
        mention_count=4,
        avg_vol=7,
        avg_load=92,
        trend="EASING",
        quote="Knee a little tweaky toward the end of the run today.",
        mention_dots={0, 3, 6, 13},        # 4 mentions in 14d
    )
    _wd_rule(d, y); y += 20

    # ── Entry 2: Achilles ──
    y = injury_entry(y,
        name="Achilles",
        side="LEFT",
        severity=3,
        first_mentioned="First mentioned — Apr 19, after a tempo session.",
        days_active=18,
        mention_count=7,
        avg_vol=9,
        avg_load=104,
        trend="STEADY",
        quote="Felt it warming up. Eased after the first mile.",
        mention_dots={0, 1, 4, 5, 8, 11, 13},
    )

    return img


# ---------------------------------------------------------------------------
# PAGE 29 — INJURY DETAIL · timeline correlated to training
# Drill-in from a single injury entry. Severity sparkline at the top,
# every voice mention chronologically below — each row shows the workout
# context the mention was attached to (type, distance, pace, load).
# Closes with a flagged at-risk pattern derived from the data.
# ---------------------------------------------------------------------------
def page_29():
    img, d = new_page()
    page_chrome(d, 29,
                "INJURY · DETAIL",
                "Knee, in context",
                ["Severity over time + every mention with the workout that",
                 "preceded it. At-risk patterns surfaced honestly."])
    sx1, sy1, sx2, sy2 = draw_phone(d)
    inner_l = sx1 + 30
    inner_r = sx2 - 30
    inner_w = inner_r - inner_l

    # Sheet handle + back
    handle_y = sy1 + 60
    d.rectangle([sx1 + (sx2-sx1)/2 - 18, handle_y, sx1 + (sx2-sx1)/2 + 18,
                 handle_y + 4], fill=SLATE_LIGHT)
    bar_y = sy1 + 92
    text(d, (inner_l, bar_y), "← Back", MONO(11), fill=AMBER, anchor="la")
    text(d, (inner_r, bar_y), "Resolve", MONO(11), fill=AMBER, anchor="ra")

    # Header
    head_y = bar_y + 30
    text(d, (inner_l, head_y), "KNEE  ·  LEFT",
         MONO(11), fill=AMBER, anchor="la")
    text(d, (inner_l, head_y + 22), "5 days active",
         DISPLAY_B(28), fill=INK, anchor="la")
    text(d, (inner_l, head_y + 60),
         "Not medical advice. Watch the trend, talk to a clinician if it sharpens.",
         SERIF_IT(13), fill=SLATE, anchor="la")
    hairline(d, inner_l, head_y + 96, inner_r, head_y + 96, fill=HAIR)

    # ── Severity sparkline (last 14 days) ──
    sev_y = head_y + 116
    text(d, (inner_l, sev_y), "SEVERITY  ·  14 DAYS",
         MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_r, sev_y), "PEAK 5 / 10",
         MONO(9), fill=SLATE_LIGHT, anchor="ra")
    chart_top = sev_y + 22
    chart_h = 80
    chart_l_x = inner_l + 6
    chart_r_x = inner_r - 6
    chart_w = chart_r_x - chart_l_x
    # mid gridline
    avg_y = chart_top + chart_h * 0.5
    for x in range(int(chart_l_x), int(chart_r_x), 6):
        d.line([(x, avg_y), (x+3, avg_y)], fill=HAIR)
    # severity values for last 14 days (None = not mentioned that day)
    sev_data = [None, None, 4, 4, 5, None, None, 3, 3, None, None, 2, None, 2]
    pts = []
    for i, s in enumerate(sev_data):
        if s is None: continue
        x = chart_l_x + (i / 13) * chart_w
        # higher severity = higher on chart
        y_norm = (s - 1) / 5  # severity 1-6 mapped to 0-1
        y = chart_top + chart_h - y_norm * chart_h
        pts.append((x, y, s))
    # connecting line through points
    for i in range(len(pts)-1):
        d.line([(pts[i][0], pts[i][1]), (pts[i+1][0], pts[i+1][1])],
               fill=AMBER, width=2)
    # points themselves
    for x, y, s in pts:
        d.ellipse([x-3, y-3, x+3, y+3], fill=AMBER)
    text(d, (chart_l_x, chart_top + chart_h + 4), "14d ago",
         MONO(8), fill=SLATE_LIGHT, anchor="la")
    text(d, (chart_r_x, chart_top + chart_h + 4), "today",
         MONO(8), fill=SLATE_LIGHT, anchor="ra")
    y = chart_top + chart_h + 28

    # italic read
    text(d, (inner_l, y),
         "Trending down. Peak of 5 fifteen days ago — currently 2.",
         SERIF_IT(13), fill=INK, anchor="la")
    y += 28

    # ── Mention timeline ──
    mid_y = y
    d.line([(inner_l, mid_y), ((inner_l+inner_r)/2 - 6, mid_y)],
           fill=HAIR, width=1)
    d.ellipse([(inner_l+inner_r)/2 - 2, mid_y-2,
               (inner_l+inner_r)/2 + 2, mid_y+2], fill=HAIR)
    d.line([((inner_l+inner_r)/2 + 6, mid_y), (inner_r, mid_y)],
           fill=HAIR, width=1)
    y += 16

    text(d, (inner_l, y), "EVERY MENTION  ·  WITH CONTEXT",
         MONO(10), fill=SLATE, anchor="la")
    y += 22

    mentions = [
        # (date, severity, workout, quote)
        ("MAY 7  ·  TODAY",        2, "Easy 5mi  ·  7:11/mi  ·  load 60",
         "Tweaky toward the end of the run."),
        ("MAY 5  ·  2 DAYS AGO",   2, "Tempo 6mi  ·  5:48/mi  ·  load 88",
         "Faded after the warmup. No issue at speed."),
        ("MAY 3  ·  4 DAYS AGO",   3, "Long 10mi  ·  7:24/mi  ·  load 110",
         "Felt it on the descent — caution after mile 7."),
        ("MAY 1  ·  6 DAYS AGO",   3, "Easy 6mi  ·  7:30/mi  ·  load 70",
         "Slight pinch when the pace dropped under 7:00."),
        ("APR 28 ·  9 DAYS AGO",   4, "Long 12mi  ·  7:08/mi  ·  load 132",
         "Hurt about mile 9. Slowed last 2 to baby it."),
    ]
    for (date, sev, ctx, quote) in mentions:
        # date eyebrow
        text(d, (inner_l, y), date, MONO(9), fill=AMBER, anchor="la")
        text(d, (inner_r, y), f"{sev} / 10",
             MONO_B(11), fill=AMBER, anchor="ra")
        # workout context line (mono)
        text(d, (inner_l, y + 16), ctx,
             MONO(10), fill=SLATE, anchor="la")
        # italic quote
        text(d, (inner_l, y + 32),
             f"“{quote}”",
             SERIF_IT(13), fill=INK, anchor="la")
        y += 60

    # ── At-risk pattern ──
    pat_y = y
    text(d, (inner_l, pat_y), "AT-RISK PATTERNS",
         MONO(10), fill=SLATE, anchor="la")
    text(d, (inner_l, pat_y + 18),
         "Mentioned 3× after sessions over 100 weighted-min.",
         SERIF_IT(13), fill=INK, anchor="la")
    text(d, (inner_l, pat_y + 36),
         "Pace under 7:00 / mi correlated with 2 of 5 mentions.",
         SERIF_IT(13), fill=INK, anchor="la")
    text(d, (inner_l, pat_y + 54),
         "—— surfaced from your logs, not a diagnosis.",
         SERIF_IT(13), fill=SLATE, anchor="la")

    return img


# ---------------------------------------------------------------------------
# Build all
# ---------------------------------------------------------------------------
out_dir = "/sessions/gracious-lucid-heisenberg/mnt/my-running-app/design"
os.makedirs(out_dir, exist_ok=True)

# Plates 1–5 stay numeric. Plates 6A/B/C/D are the four training-tab variants.
# Plate 7 is the four-up chart-options comparison.
core_plates = [
    ("01", page_1()),
    ("02", page_2()),
    ("03", page_3()),
    ("04", page_4()),
    ("05", page_5()),
    ("06A", page_6(chart_style="A", fig_no=6)),
    ("06B", page_6(chart_style="B", fig_no=6)),
    ("06C", page_6(chart_style="C", fig_no=6)),
    ("06D", page_6(chart_style="D", fig_no=6)),
    ("06E", page_6(chart_style="E", fig_no=6)),
    ("07",  page_7()),
    ("08",  page_8()),
    ("09",  page_9()),
    ("10",  page_10()),
    ("11",  page_11()),
    ("12",  page_12()),
    ("13",  page_13()),
    ("14",  page_14()),
    ("15",  page_15()),
    ("16",  page_16()),
    ("17",  page_17()),
    ("18",  page_18()),
    ("19",  page_19()),
    ("20",  page_20()),
    ("21",  page_21()),
    ("22",  page_22()),
    ("23",  page_23()),
    ("24",  page_24()),
    ("25",  page_25()),
    ("26",  page_26()),
    ("27",  page_27()),
    ("28",  page_28()),
    ("29",  page_29()),
]
for label, p in core_plates:
    p.save(f"{out_dir}/trends_mockup_plate_{label}.png", "PNG")

# Combined PDF (in display order)
imgs = [p for _, p in core_plates]
imgs[0].save(f"{out_dir}/trends_mockups.pdf",
             save_all=True, append_images=imgs[1:], resolution=200)

print(f"OK — wrote {len(core_plates)} PNG plates + trends_mockups.pdf to {out_dir}")

# Designer 2a-1 — GUI cleanup (Direction B) Implementation Plan

> Visual refinement of 2a to the approved **Direction B** mock. No new capabilities; the suite stays green at **64**. Verification is the headless suite + xvfb screenshots (controller) + user review.

**Goal:** Refine the Designer layout — capped/centered responsive column, OSC 1/OSC 2 sub-cards with the wav-type pill inline with period+amount, transport on its own full-width row, ENV recolored red→purple, framed cards (already in).

**Design ref:** Direction B full-page mock; `docs/superpowers/specs/2026-06-19-designer-phase2-design.md` (the 2a-1 decomposition bullet).

**Files:** `common/core/designer/designer.gd`, `common/core/designer/source_card.gd`. No test changes (pure layout).

## Global Constraints
- Pure visual refinement; `to_config`/scene round-trip behavior unchanged; suite stays **64/64**.
- Responsive: content column capped (~820px) and **centered**, shrinking to fill below the cap (no fixed width, no letterbox).
- Reuse `mod_sources` for the per-oscillator mini-previews (`MS.osc`).
- Designer-mode only; preview/movie/render paths untouched.

---

### Task 1 — Designer shell: capped column + title/transport rows

**File:** `common/core/designer/designer.gd`

- Add `const CONTENT_CAP := 820.0`, fields `var _outer: MarginContainer`, `var _time: Label`.
- In `_build`, replace the fixed-margin `MarginContainer` with `_outer` (margins set dynamically), and split the title + transport into their own rows; make the seek slider full-width:

```gdscript
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_outer = MarginContainer.new()
	_outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_outer)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	_outer.add_child(col)

	var title := Label.new()
	title.text = "DESIGNER · %s · %s" % [model.model_name(), model.preset_path]
	title.add_theme_color_override("font_color", Color(0.81, 0.88, 1.0))
	col.add_child(title)

	# transport on its own full-width row
	_macro_knobs = {}  # (populated after bases below; keep existing order)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 12)
	var play := Button.new()
	play.text = "▶"
	play.toggle_mode = true
	play.toggled.connect(func(on): _playing = on)
	tr.add_child(play)
	_scrub = HSlider.new()
	_scrub.min_value = 0.0
	_scrub.max_value = 1.0
	_scrub.step = 0.001
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scrub.value_changed.connect(func(f): _t = f * maxf(model.duration_sec, 0.0001))
	tr.add_child(_scrub)
	_time = Label.new()
	_time.text = "0:00 / " + _fmt_time(model.duration_sec)
	_time.add_theme_color_override("font_color", Color(0.68, 0.73, 0.84))
	tr.add_child(_time)
	col.add_child(tr)
```

  Keep the existing Bases + sources block, but they now `col.add_child(_framed(...))` into this `col` (unchanged). The `_bases`/`_macro_knobs`/`_mod` setup stays; just ensure `_macro_knobs = _bases.macro_knobs()` is still assigned after `_bases` is built. Remove the now-duplicated old transport block.

- Add the dynamic-cap + resize handling. In `setup`, after `_build()`:

```gdscript
	get_viewport().size_changed.connect(_update_cap)
	_update_cap()
```

- Add the helpers:

```gdscript
func _update_cap() -> void:
	if _outer == null:
		return
	var w := float(get_viewport().get_visible_rect().size.x)
	var side := int(maxf(16.0, (w - CONTENT_CAP) * 0.5))
	_outer.add_theme_constant_override("margin_left", side)
	_outer.add_theme_constant_override("margin_right", side)
	_outer.add_theme_constant_override("margin_top", 12)
	_outer.add_theme_constant_override("margin_bottom", 12)

static func _fmt_time(secs: float) -> String:
	var s := int(maxf(secs, 0.0))
	return "%d:%02d" % [s / 60, s % 60]
```

- In `_process`, when playing, update the time label:

```gdscript
	if _playing:
		_t = fmod(_t + delta, maxf(model.duration_sec, 0.0001))
		_scrub.set_value_no_signal(_t / maxf(model.duration_sec, 0.0001))
	if _time != null:
		_time.text = _fmt_time(_t) + " / " + _fmt_time(model.duration_sec)
```

- **Verify:** `godot --headless --path radial_burst --script res://core/tests/run_tests.gd` → `TESTS: 64 run, 0 failed`; headless smoke clean. Commit `designer: capped/centered column + transport on its own row`.

---

### Task 2 — Source cards: OSC sub-cards, inline wav-type, purple ENV

**File:** `common/core/designer/source_card.gd`

- ENV color → purple: in `_color()`, `_: return Color(0.69, 0.49, 1.0)`.
- Replace the flat LFO knob row with **OSC sub-cards**. In `_build`'s `match kind` `"lfo"` branch, instead of adding knobs to `ctrl`, build a horizontal row of sub-cards:

```gdscript
		"lfo":
			var oscs := HBoxContainer.new()
			oscs.add_theme_constant_override("separation", 8)
			add_child(oscs)
			for i in src.get("oscillators", []).size():
				oscs.add_child(_osc_subcard(i))
```

  (Keep the `tween`/`env` branches building into `ctrl` as today; for `lfo`, `ctrl` is unused — guard so an empty `ctrl` isn't added, or simply don't create `ctrl` for lfo.)

- Add the sub-card builder + per-oscillator mini preview:

```gdscript
func _osc_subcard(i: int) -> PanelContainer:
	var o = src["oscillators"][i]
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.09)
	sb.border_color = Color(0.16, 0.19, 0.29)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	var hl := Label.new()
	hl.text = "OSC %d" % (i + 1)
	hl.add_theme_font_size_override("font_size", 10)
	hl.add_theme_color_override("font_color", Color(0.74, 0.82, 0.95))
	box.add_child(hl)
	var mini := WavePreview.new()
	mini.custom_minimum_size = Vector2(130, 22)
	box.add_child(mini)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	box.add_child(row)
	var shape_items := ["sine", "triangle", "saw", "square"]
	var shape_opts := OptionButton.new()
	for s_item in shape_items:
		shape_opts.add_item(s_item)
	var si := shape_items.find(str(o.get("shape", "sine")))
	shape_opts.selected = si if si >= 0 else 0
	shape_opts.item_selected.connect(func(idx):
		o["shape"] = shape_items[idx]
		_wire_osc_mini(mini, o)
		_wire_preview(_prev)
		changed.emit())
	row.add_child(shape_opts)
	row.add_child(_osc_knob(o, "period_sec", 1.0, 120.0, mini))
	row.add_child(_osc_knob(o, "amount", 0.0, 1.0, mini))
	_wire_osc_mini(mini, o)
	return panel

func _osc_knob(o: Dictionary, key: String, lo: float, hi: float, mini) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var k = Knob.new()
	k.setup(lo, hi, float(o.get(key, 0.0)), float(o.get(key, 0.0)), _color())
	k.value_changed.connect(func(v):
		o[key] = v
		_wire_osc_mini(mini, o)
		if _prev != null:
			_wire_preview(_prev)
		changed.emit())
	box.add_child(k)
	var l := Label.new()
	l.text = key
	l.add_theme_font_size_override("font_size", 10)
	box.add_child(l)
	return box

func _wire_osc_mini(mini, o: Dictionary) -> void:
	var period: float = maxf(float(o.get("period_sec", 30.0)), 0.0001)
	var shape := str(o.get("shape", "sine"))
	var phase := float(o.get("phase_deg", 0.0))
	var amt := float(o.get("amount", 1.0))
	mini.set_sampler(func(x): return MS.osc(x * period * 2.0, period, shape, phase) * amt, -1.0, 1.0, _color())
```

- Routing as chips: wrap each route item in a styled pill. In the routing loop, give each `item` a PanelContainer-style background (or keep the `HFlowContainer` and add a `StyleBoxFlat` per item via a PanelContainer wrapper). Minimal version — wrap the existing `item` HBox in a chip panel:

```gdscript
	for tg in src.get("targets", []):
		var chip := PanelContainer.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(0.05, 0.065, 0.10)
		csb.border_color = Color(0.14, 0.18, 0.27)
		csb.set_border_width_all(1)
		csb.set_corner_radius_all(13)
		csb.content_margin_left = 12; csb.content_margin_right = 8
		csb.content_margin_top = 3; csb.content_margin_bottom = 3
		chip.add_theme_stylebox_override("panel", csb)
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 6)
		chip.add_child(item)
		var lab := Label.new()
		lab.text = "→ %s" % str(tg.get("to", "?"))
		item.add_child(lab)
		var k = Knob.new()
		k.setup(-10.0, 10.0, float(tg.get("amount", 0.0)), float(tg.get("amount", 0.0)), _color())
		k.set_bipolar(true)
		k.custom_minimum_size = Vector2(30, 30)
		k.value_changed.connect(func(v):
			tg["amount"] = v
			changed.emit())
		item.add_child(k)
		routes.add_child(chip)
```

- **Verify:** suite `64/64`; headless smoke clean; controller xvfb screenshot (capped + a narrow width) → user review. Commit `designer: OSC sub-cards + inline wav-type + purple ENV + routing chips`.

---

## Self-review
- Capped/centered responsive column (Task 1) ✓; transport own full-width row + time (Task 1) ✓; OSC 1/OSC 2 sub-cards with inline wav-type (Task 2) ✓; purple ENV (Task 2) ✓; routing chips (Task 2) ✓; framed cards already in (`_framed`).
- No `to_config`/round-trip change → suite stays 64. New code is draw/layout only (`_osc_subcard`, `_osc_knob`, `_wire_osc_mini`, `_update_cap`, `_fmt_time`).
- Types: `MS.osc(t, period, shape, phase)` matches `mod_sources.osc`; `WavePreview.set_sampler(cb,lo,hi,color)`; `Knob.setup(...)/set_bipolar`. Consistent.

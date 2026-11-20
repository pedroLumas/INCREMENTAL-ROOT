extends Control
## "Vaciar el Vesubio": interfaz, bucle de juego, guardado y progreso offline.
## La interfaz se construye en código; la escena pixel art la dibuja scene_view.gd.

const Core := preload("res://scripts/core.gd")
const State := preload("res://scripts/state.gd")
const Fmt := preload("res://scripts/fmt.gd")
const SceneView := preload("res://scripts/scene_view.gd")

const COL_NIGHT := Color("#1c1521")
const COL_PANEL := Color("#271e2c")
const COL_LINE := Color("#3d3142")
const COL_ASH := Color("#b8aab0")
const COL_BONE := Color("#f4e9dd")
const COL_MAGMA := Color("#ff7b1c")
const COL_MAGMA_DEEP := Color("#b8420c")
const COL_EMBER := Color("#ffc15c")
const COL_OBSIDIAN := Color("#120d16")
const COL_GOOD := Color("#8fd694")
const COL_WARN := Color("#ff9f6b")

const UPGRADES := {
	"spoon": "Cuchara más grande",
	"helper": "Contratar ayudante",
	"speed": "Ayudantes más rápidos",
}

var st: State
var speed := 1.0
var paused := false
var collapse := 0.0         ## 0..1 animación de la caldera
var dip := 0.0              ## animación de la cuchara
var particles: Array = []   ## {lupa, x, y, vx, vy, life, c}
var click_times: Array[float] = []
var shake_t := 0.0
var ui_acc := 0.0
var save_acc := 0.0

var pixel_font: Font
var scene_font: Font
var bold_font: FontVariation
var scene_view: Node2D
var viewport: SubViewport

# Nodos de la interfaz
var lbl_legacy: Label
var lbl_remaining: Label
var lbl_lupa: Label
var lbl_run: Label
var lbl_out: Label
var lbl_in: Label
var chip: PanelContainer
var chip_label: Label
var scoop_btn: Button
var scoop_content: VBoxContainer
var scoop_sub: Label
var stat_values := {}
var upgrades := {}
var pressure_bar: ProgressBar
var pressure_pct: Label
var erupt_btn: Button
var erupt_hint: Label
var caldera_bar: ProgressBar
var caldera_pct: Label
var caldera_hint: Label
var reset_row: HBoxContainer
var dev_row: HBoxContainer
var modal: Control
var modal_title: Label
var modal_body: RichTextLabel
var modal_btn: Button
var on_modal_close := Callable()


func _ready() -> void:
	# Sin ligaduras: en Pixelify Sans la ligadura "fi" parece una "Á".
	var no_liga := {TextServerManager.get_primary_interface().name_to_tag("liga"): 0}
	var raw: FontFile = load("res://fonts/PixelifySans.ttf")
	var ui_font := FontVariation.new()
	ui_font.base_font = raw
	ui_font.opentype_features = no_liga
	pixel_font = ui_font
	var raw_scene: FontFile = raw.duplicate()
	raw_scene.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	raw_scene.hinting = TextServer.HINTING_NONE
	raw_scene.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	var sf := FontVariation.new()
	sf.base_font = raw_scene
	sf.opentype_features = no_liga
	scene_font = sf
	bold_font = FontVariation.new()
	bold_font.base_font = ThemeDB.fallback_font
	bold_font.variation_embolden = 0.7
	theme = _make_theme()
	_build()

	var now := Time.get_unix_time_from_system()
	st = _load()
	if st == null:
		st = State.new(now)
	else:
		_apply_away(now - st.last_seen)
	st.last_seen = now
	if "--prueba" in OS.get_cmdline_user_args():
		dev_row.visible = true
	_update_ui()


# --- Estilo ------------------------------------------------------------------
func _box(bg: Color, border: Color, margin := 12.0, border_w := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_content_margin_all(margin)
	return s


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	t.set_color("font_color", "Label", COL_BONE)
	t.set_stylebox("panel", "PanelContainer", _box(COL_PANEL, COL_LINE, 14))
	for state in ["normal", "disabled"]:
		t.set_stylebox(state, "Button", _box(COL_PANEL, COL_LINE, 8))
	t.set_stylebox("hover", "Button", _box(COL_PANEL.lightened(0.06), COL_EMBER, 8))
	t.set_stylebox("pressed", "Button", _box(COL_PANEL.darkened(0.15), COL_EMBER, 8))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), COL_EMBER, 8, 3))
	t.set_color("font_color", "Button", COL_BONE)
	t.set_color("font_hover_color", "Button", COL_EMBER)
	t.set_color("font_pressed_color", "Button", COL_EMBER)
	t.set_color("font_disabled_color", "Button", Color(COL_ASH, 0.6))
	t.set_stylebox("background", "ProgressBar", _box(COL_OBSIDIAN, COL_LINE, 0))
	var fill := StyleBoxFlat.new()
	fill.bg_color = COL_MAGMA
	t.set_stylebox("fill", "ProgressBar", fill)
	return t


func _label(text: String, size: int, color: Color = COL_BONE, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	return l


func _caps(text: String) -> Label:
	return _label(text.to_upper(), 12, COL_ASH)


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _vbox(sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func _hbox(sep: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## Botón grande de magma con sombra dura (borde inferior).
func _magma_button(title: String, size: int) -> Button:
	var b := Button.new()
	b.text = title
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", pixel_font)
	b.add_theme_font_size_override("font_size", size)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, COL_OBSIDIAN)
	var normal := _box(COL_MAGMA, COL_MAGMA_DEEP, 12, 0)
	normal.border_width_bottom = 6
	var hover := normal.duplicate()
	hover.bg_color = COL_MAGMA.lightened(0.08)
	var pressed := _box(COL_MAGMA.darkened(0.05), COL_MAGMA_DEEP, 12, 0)
	pressed.content_margin_top = 18
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), COL_EMBER, 0, 3))
	return b


# --- Construcción de la interfaz ---------------------------------------------
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = COL_NIGHT
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var cols := _hbox(28)
	margin.add_child(cols)

	var left := _vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.2
	cols.add_child(left)
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(right_scroll)
	var right := _vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right)

	_build_left(left)
	_build_right(right)
	_build_modal()


func _build_left(left: VBoxContainer) -> void:
	var header := _hbox(12)
	var titles := _vbox(2)
	titles.add_child(_label("Vaciar el Vesubio", 40, COL_BONE, pixel_font))
	titles.add_child(_label("con una cuchara", 18, COL_MAGMA, pixel_font))
	header.add_child(titles)
	header.add_child(_spacer())
	lbl_legacy = _label("Calderas: 0", 16, COL_ASH, pixel_font)
	header.add_child(lbl_legacy)
	left.add_child(header)

	var counter := _vbox(0)
	counter.add_child(_caps("Cucharadas que faltan"))
	lbl_remaining = _label("—", 30, COL_BONE, pixel_font)
	counter.add_child(lbl_remaining)
	left.add_child(counter)

	# Escena: SubViewport de 320×180 mostrado ×2 sin suavizado
	viewport = SubViewport.new()
	viewport.size = Vector2i(320, 180)
	viewport.transparent_bg = false
	viewport.snap_2d_vertices_to_pixel = true
	viewport.snap_2d_transforms_to_pixel = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(viewport)
	scene_view = SceneView.new()
	scene_view.game = self
	scene_view.font = scene_font
	viewport.add_child(scene_view)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _box(COL_OBSIDIAN, COL_LINE, 2))
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var tex := TextureRect.new()
	tex.texture = viewport.get_texture()
	tex.custom_minimum_size = Vector2(640, 360)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.mouse_filter = Control.MOUSE_FILTER_STOP
	tex.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tex.tooltip_text = "Toca para sacar una cucharada"
	tex.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_do_scoop())
	frame.add_child(tex)
	left.add_child(frame)

	var caption := _hbox(8)
	lbl_lupa = _label("", 13, COL_ASH)
	lbl_lupa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.add_child(lbl_lupa)
	lbl_run = _label("Vuelta: 0:00", 13, COL_ASH)
	caption.add_child(lbl_run)
	caption.custom_minimum_size.x = 640
	caption.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(caption)

	var race := _hbox(14)
	race.add_child(_label("Sacas", 16, COL_BONE))
	lbl_out = _label("0", 16, COL_BONE, bold_font)
	race.add_child(lbl_out)
	race.add_child(_label("Entra", 16, COL_BONE))
	lbl_in = _label("0", 16, COL_BONE, bold_font)
	race.add_child(lbl_in)
	chip = PanelContainer.new()
	chip_label = _label("Equilibrio", 15, COL_ASH, pixel_font)
	chip.add_child(chip_label)
	race.add_child(chip)
	left.add_child(race)

	scoop_btn = _magma_button("", 26)
	scoop_btn.custom_minimum_size = Vector2(640, 76)
	scoop_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	scoop_btn.focus_mode = Control.FOCUS_NONE
	scoop_btn.clip_contents = true
	scoop_content = _vbox(2)
	scoop_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scoop_content.alignment = BoxContainer.ALIGNMENT_CENTER
	scoop_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t1 := _label("Sacar una cucharada", 26, COL_OBSIDIAN, pixel_font)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoop_content.add_child(t1)
	scoop_sub = _label("+15 mL · o pulsa la barra espaciadora", 14, Color(COL_OBSIDIAN, 0.8))
	scoop_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoop_content.add_child(scoop_sub)
	scoop_btn.add_child(scoop_content)
	scoop_btn.button_down.connect(func() -> void: scoop_content.position.y = 5)
	scoop_btn.button_up.connect(func() -> void: scoop_content.position.y = 0)
	scoop_btn.pressed.connect(_do_scoop)
	left.add_child(scoop_btn)


func _build_right(right: VBoxContainer) -> void:
	var stats := PanelContainer.new()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	for item in [["emptied", "Vaciado"], ["wallet", "Magma enfriado"], ["spoon", "Tu cuchara ≈"], ["mountain", "Tu montaña ≈"]]:
		var cell := _vbox(1)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(_caps(item[1]))
		var v := _wrap(_label("—", 19, COL_EMBER if item[0] == "wallet" else COL_BONE, pixel_font))
		cell.add_child(v)
		stat_values[item[0]] = v
		grid.add_child(cell)
	stats.add_child(grid)
	right.add_child(stats)

	right.add_child(_label("Mejoras", 20, COL_BONE, pixel_font))
	for kind in Core.KINDS:
		right.add_child(_make_upgrade(kind, UPGRADES[kind]))

	# Erupción
	var ep := PanelContainer.new()
	var ev := _vbox(8)
	var erow := _hbox(8)
	erow.add_child(_caps("Presión"))
	erow.add_child(_spacer())
	pressure_pct = _caps("0 %")
	erow.add_child(pressure_pct)
	ev.add_child(erow)
	pressure_bar = ProgressBar.new()
	pressure_bar.show_percentage = false
	pressure_bar.custom_minimum_size.y = 14
	ev.add_child(pressure_bar)
	erupt_btn = Button.new()
	erupt_btn.text = "Provocar erupción"
	erupt_btn.focus_mode = Control.FOCUS_NONE
	erupt_btn.add_theme_font_override("font", pixel_font)
	erupt_btn.add_theme_font_size_override("font_size", 18)
	erupt_btn.pressed.connect(_do_erupt)
	ev.add_child(erupt_btn)
	erupt_hint = _wrap(_label("", 13, COL_ASH))
	ev.add_child(erupt_hint)
	ep.add_child(ev)
	right.add_child(ep)

	# Caldera
	var cp := PanelContainer.new()
	var cv := _vbox(8)
	var crow := _hbox(8)
	crow.add_child(_caps("Camino a la caldera · escala logarítmica"))
	crow.add_child(_spacer())
	caldera_pct = _caps("0 %")
	crow.add_child(caldera_pct)
	cv.add_child(crow)
	caldera_bar = ProgressBar.new()
	caldera_bar.show_percentage = false
	caldera_bar.custom_minimum_size.y = 14
	var cfill := StyleBoxFlat.new()
	cfill.bg_color = COL_EMBER
	caldera_bar.add_theme_stylebox_override("fill", cfill)
	cv.add_child(caldera_bar)
	caldera_hint = _wrap(_label("", 13, COL_ASH))
	cv.add_child(caldera_hint)
	cp.add_child(cv)
	right.add_child(cp)

	# Pie
	right.add_child(_wrap(_label("Volumen del Vesubio: ≈ 66 km³ (cono simplificado de 14 km de base y 1.281 m de alto; no hay una cifra oficial). Las comparaciones son aproximadas. El dibujo exagera la altura ×3.", 12, COL_ASH)))
	right.add_child(_wrap(_label("Prototipo sin arte final. La partida se guarda sola; tus ayudantes siguen trabajando aunque cierres el juego. F1: modo prueba.", 12, COL_ASH)))
	reset_row = _hbox(8)
	right.add_child(reset_row)
	_reset_row_idle()
	dev_row = _hbox(6)
	dev_row.visible = false
	dev_row.add_child(_label("Modo prueba:", 13, COL_ASH))
	for s in [1.0, 10.0, 100.0]:
		var b := Button.new()
		b.text = "Tiempo ×%d" % int(s)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func() -> void: speed = s)
		dev_row.add_child(b)
	var b8 := Button.new()
	b8.text = "Simular 8 h fuera"
	b8.focus_mode = Control.FOCUS_NONE
	b8.add_theme_font_size_override("font_size", 13)
	b8.pressed.connect(func() -> void: _apply_away(8 * 3600.0))
	dev_row.add_child(b8)
	right.add_child(dev_row)


func _make_upgrade(kind: String, title: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 66)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = true
	b.add_theme_stylebox_override("normal", _box(COL_PANEL, COL_MAGMA, 8))
	b.add_theme_stylebox_override("hover", _box(COL_PANEL.lightened(0.06), COL_EMBER, 8))
	var fill := ColorRect.new()
	fill.color = Color(COL_MAGMA, 0.16)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(fill)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 14)
	for side in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 7)
	b.add_child(m)
	var vb := _vbox(3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(vb)
	var row := _hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := _label(title, 17, COL_BONE, bold_font)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)
	var cost_l := _label("—", 17, COL_EMBER, pixel_font)
	row.add_child(cost_l)
	vb.add_child(row)
	var desc := _wrap(_label("", 13, COL_ASH))
	vb.add_child(desc)
	b.pressed.connect(func() -> void:
		if not paused and Core.buy(st, kind):
			_update_ui())
	upgrades[kind] = {"button": b, "fill": fill, "cost": cost_l, "desc": desc, "name": name_l}
	return b


func _build_modal() -> void:
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.visible = false
	add_child(modal)
	var dim := ColorRect.new()
	dim.color = Color(0.047, 0.031, 0.055, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(COL_PANEL, COL_MAGMA, 24))
	center.add_child(panel)
	var vb := _vbox(14)
	vb.custom_minimum_size = Vector2(480, 0)
	panel.add_child(vb)
	modal_title = _wrap(_label("", 30, COL_BONE, pixel_font))
	vb.add_child(modal_title)
	modal_body = RichTextLabel.new()
	modal_body.bbcode_enabled = true
	modal_body.fit_content = true
	modal_body.scroll_active = false
	modal_body.custom_minimum_size = Vector2(480, 0)
	modal_body.add_theme_font_size_override("normal_font_size", 17)
	modal_body.add_theme_font_size_override("bold_font_size", 17)
	modal_body.add_theme_font_override("bold_font", bold_font)
	modal_body.add_theme_color_override("default_color", COL_BONE)
	vb.add_child(modal_body)
	modal_btn = _magma_button("Seguir", 22)
	modal_btn.custom_minimum_size.y = 58
	modal_btn.pressed.connect(_close_modal)
	vb.add_child(modal_btn)


func _reset_row_idle() -> void:
	for c in reset_row.get_children():
		c.queue_free()
	var ask := Button.new()
	ask.text = "Borrar partida"
	ask.flat = true
	ask.focus_mode = Control.FOCUS_NONE
	ask.add_theme_font_size_override("font_size", 13)
	ask.add_theme_color_override("font_color", COL_ASH)
	ask.pressed.connect(_reset_row_confirm)
	reset_row.add_child(ask)


func _reset_row_confirm() -> void:
	for c in reset_row.get_children():
		c.queue_free()
	reset_row.add_child(_label("¿Borrar la partida? Se pierde todo, también las calderas.", 13, COL_WARN))
	var yes := Button.new()
	yes.text = "Sí, borrar"
	yes.focus_mode = Control.FOCUS_NONE
	yes.add_theme_color_override("font_color", COL_WARN)
	yes.pressed.connect(func() -> void:
		st = State.new(Time.get_unix_time_from_system())
		paused = false
		collapse = 0.0
		particles.clear()
		_save()
		_reset_row_idle()
		_update_ui())
	reset_row.add_child(yes)
	var no := Button.new()
	no.text = "Cancelar"
	no.focus_mode = Control.FOCUS_NONE
	no.pressed.connect(_reset_row_idle)
	reset_row.add_child(no)


# --- Modal -------------------------------------------------------------------
func _show_modal(title: String, body: String, button: String, cb := Callable()) -> void:
	modal_title.text = title
	modal_body.text = body
	modal_btn.text = button
	on_modal_close = cb
	modal.visible = true
	modal_btn.grab_focus()


func _close_modal() -> void:
	modal.visible = false
	var cb := on_modal_close
	on_modal_close = Callable()
	if cb.is_valid():
		cb.call()


func _apply_away(seconds: float) -> void:
	if not (seconds > 30.0):
		return
	var r := Core.offline(st, seconds)
	var body: String
	if st.helpers > 0:
		body = "Tus %d ayudantes sacaron [b]%s[/b], que es ≈ %s.\n\nEl agujero no se ha rellenado mientras no estabas." % [st.helpers, Fmt.vol(r.gained), Core.fermi(r.gained)]
	else:
		body = "No tenías ayudantes, así que nadie sacó magma. Contrata uno para que el trabajo siga sin ti."
	_show_modal("Has estado fuera " + Fmt.dur(seconds), body, "Seguir")


# --- Acciones ----------------------------------------------------------------
func _do_scoop() -> void:
	if paused or modal.visible:
		return
	var v := Core.scoop(st)
	click_times.append(Time.get_ticks_msec() / 1000.0)
	dip = 1.0
	_float_text("+" + Fmt.vol(v))
	for i in 5:
		particles.append({"lupa": true, "x": 0.0, "y": 0.0, "vx": randf_range(-30, 30), "vy": randf_range(-90, -40), "life": 0.6, "c": COL_EMBER if randf() < 0.5 else COL_MAGMA})


func _float_text(text: String) -> void:
	var l := _label(text, 16, COL_EMBER, pixel_font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoop_btn.add_child(l)
	# A la derecha del título, para no taparlo
	l.position = Vector2(scoop_btn.size.x * randf_range(0.8, 0.88), scoop_btn.size.y * 0.55)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", 4.0, 0.9).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.9)
	tw.chain().tween_callback(l.queue_free)


func _do_erupt() -> void:
	if paused or not Core.can_erupt(st):
		return
	Core.erupt(st)
	shake_t = 0.45
	var colors := [COL_EMBER, COL_MAGMA, Color("#ff4d2e"), COL_ASH]
	for i in 70:
		particles.append({"lupa": false, "x": 0.0, "y": 0.0, "vx": randf_range(-45, 45), "vy": randf_range(-170, -60), "life": randf_range(1.2, 2.0), "c": colors[i % 4]})
	_update_ui()


func _start_collapse() -> void:
	paused = true
	collapse = 0.0001
	shake_t = 0.6


func _finish_collapse() -> void:
	var bonus := Core.caldera_bonus(st)
	var body := "Has vaciado el volcán y se ha desplomado sobre sí mismo, como Santorini o el Crater Lake.\n\nEn %s sacaste [b]%s[/b], ≈ %s.\n\nBonus permanente: [b]×%s[/b] a todo lo que saques a partir de ahora." % [Fmt.dur(st.run_seconds), Fmt.vol(st.run_total), Core.fermi(st.run_total), Fmt.sig(bonus)]
	_show_modal("¡El Vesubio se ha hundido!", body, "Empezar con un Vesubio nuevo", func() -> void:
		Core.caldera(st, Time.get_unix_time_from_system())
		collapse = 0.0
		paused = false
		particles.clear()
		_save()
		_update_ui())


# --- Bucle -------------------------------------------------------------------
func _process(delta: float) -> void:
	var dt := minf(delta, 0.25)
	if not paused and not modal.visible:
		Core.tick(st, dt * speed)
		if Core.caldera_ready(st):
			_start_collapse()
	if collapse > 0.0 and collapse < 1.0:
		collapse = minf(1.0, collapse + dt / 2.2)
		if collapse >= 1.0:
			_finish_collapse()
	dip = maxf(0.0, dip - dt * 5.0)
	for p in particles:
		p["x"] += p["vx"] * dt
		p["y"] += p["vy"] * dt
		p["vy"] += 140.0 * dt
		p["life"] -= dt
	particles = particles.filter(func(p: Dictionary) -> bool: return p["life"] > 0.0)
	if shake_t > 0.0:
		shake_t -= dt
		scene_view.position = Vector2(randi_range(-2, 2), randi_range(-1, 1)) if shake_t > 0.0 else Vector2.ZERO
	scene_view.queue_redraw()
	ui_acc += dt
	if ui_acc >= 0.1:
		ui_acc = 0.0
		_update_ui()
	save_acc += delta
	if save_acc >= 5.0:
		save_acc = 0.0
		_save()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_do_scoop()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F1:
			dev_row.visible = not dev_row.visible


func _update_ui() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	while not click_times.is_empty() and now - click_times[0] > 2.0:
		click_times.pop_front()
	var cps := click_times.size() / 2.0
	var auto := Core.auto_rate(st)
	var out := auto + cps * Core.click_volume(st)
	var inn := Core.inflow(st)

	lbl_remaining.text = Fmt.big_int(maxf(0.0, (Core.VOLUME - st.hole) / Core.spoon(st)))
	lbl_out.text = Fmt.vol(out) + "/s"
	lbl_in.text = Fmt.vol(inn) + "/s"
	var chip_col := COL_ASH
	if out > inn * 1.05:
		chip_label.text = "El nivel baja"
		chip_col = COL_GOOD
	elif out < inn * 0.95:
		chip_label.text = "Se rellena"
		chip_col = COL_WARN
	else:
		chip_label.text = "Equilibrio"
	chip_label.add_theme_color_override("font_color", chip_col)
	chip.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0), chip_col, 0))
	chip.get_theme_stylebox("panel").content_margin_left = 8
	chip.get_theme_stylebox("panel").content_margin_right = 8

	stat_values["emptied"].text = Fmt.pct(st.hole / Core.VOLUME * 100.0)
	stat_values["wallet"].text = Fmt.vol(st.magma)
	stat_values["spoon"].text = Core.fermi(Core.spoon(st))
	stat_values["mountain"].text = Core.fermi(st.run_total)
	scoop_sub.text = "+%s · o pulsa la barra espaciadora" % Fmt.vol(Core.click_volume(st))

	for kind in Core.KINDS:
		var u: Dictionary = upgrades[kind]
		var c := Core.cost(st, kind)
		var b: Button = u["button"]
		b.disabled = st.magma < c or paused
		var p := clampf(st.magma / c, 0.0, 1.0)
		u["fill"].position = Vector2.ZERO
		u["fill"].size = Vector2(b.size.x * p, b.size.y)
		u["cost"].text = Fmt.vol(c)
		var a := 0.55 if b.disabled else 1.0
		u["name"].modulate.a = a
		u["cost"].modulate.a = a
	upgrades["spoon"]["desc"].text = "Duplica el tamaño de la cuchara. Ahora ≈ %s." % Core.fermi(Core.spoon(st))
	upgrades["helper"]["desc"].text = "Saca media cucharada por segundo, también cuando no estás. Tienes %d." % st.helpers
	upgrades["speed"]["desc"].text = "Tus ayudantes trabajan el doble de rápido. Ritmo ×%s." % Fmt.num(pow(2.0, st.speed_lvl))

	pressure_bar.value = st.pressure * 100.0
	pressure_pct.text = "%d %%" % int(st.pressure * 100.0)
	var final := st.hole * Core.ERUPT_MULT >= Core.VOLUME * 0.999999
	erupt_btn.disabled = not Core.can_erupt(st) or paused
	erupt_btn.text = "Erupción final: hundir el volcán" if final else "Provocar erupción"
	var e_bg := COL_MAGMA if final else Color(0, 0, 0, 0)
	var e_fg := COL_OBSIDIAN if final else COL_MAGMA
	erupt_btn.add_theme_stylebox_override("normal", _box(e_bg, COL_MAGMA, 10))
	erupt_btn.add_theme_stylebox_override("hover", _box(e_bg.lightened(0.1) if final else Color(COL_MAGMA, 0.15), COL_MAGMA, 10))
	erupt_btn.add_theme_stylebox_override("disabled", _box(Color(0, 0, 0, 0), Color(COL_MAGMA, 0.4), 10))
	erupt_btn.add_theme_color_override("font_color", e_fg)
	erupt_btn.add_theme_color_override("font_hover_color", e_fg)
	erupt_btn.add_theme_color_override("font_disabled_color", Color(COL_MAGMA, 0.45))
	erupt_hint.text = "Esta erupción vacía lo que queda y el volcán se hundirá. Si esperas, tu montaña crece y el bonus será mayor." if final else "Multiplica el agujero ×10. Lo que sale vuela por los aires y no va a tu montaña."

	var potential := maxf(st.hole, auto * Core.REFILL_TIME)
	var prog := clampf(log(maxf(potential, Core.S0) / Core.S0) / log(Core.VOLUME / Core.S0), 0.0, 1.0)
	caldera_bar.value = prog * 100.0
	caldera_pct.text = "%d %%" % int(prog * 100.0)
	caldera_hint.text = "Cuando vacías el volcán entero, se hunde en una caldera y empiezas otro. Si se hundiera ahora, el bonus sería ×%s." % Fmt.sig(Core.caldera_bonus(st))

	lbl_legacy.text = "Calderas: %d · bonus ×%s" % [st.calderas, Fmt.sig(st.legacy)] if st.calderas > 0 else "Calderas: 0"
	lbl_run.text = "Vuelta: " + Fmt.dur(st.run_seconds) + (" · récord " + Fmt.dur(st.best_run_seconds) if st.best_run_seconds >= 0.0 else "")
	if collapse > 0.0:
		lbl_lupa.text = "El volcán se está hundiendo"
	elif scene_view.lupa_zoom > 0.0:
		lbl_lupa.text = "Lupa ×%s · la barra blanca mide %s" % [Fmt.num(roundf(scene_view.lupa_zoom)), Fmt.length(scene_view.lupa_bar)]
	else:
		lbl_lupa.text = "Tu cuchara ya se ve sin lupa"


# --- Guardado ----------------------------------------------------------------
func _save() -> void:
	if st == null:
		return
	st.last_seen = Time.get_unix_time_from_system()
	var f := FileAccess.open(Core.SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(st.to_dict(), "", false, true))


func _load() -> State:
	if not FileAccess.file_exists(Core.SAVE_PATH):
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(Core.SAVE_PATH))
	if typeof(d) != TYPE_DICTIONARY or int(d.get("v", 0)) != State.VERSION:
		return null
	return State.from_dict(d)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_save()

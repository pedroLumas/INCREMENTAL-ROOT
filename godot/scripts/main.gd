extends Control
## Interfaz de "Vaciar el Vesubio": escena, barra de construcción, panel lateral, avisos y guardado.
## Toda la lógica vive en Game; aquí solo se muestra y se traducen los clics en órdenes.

const Game := preload("res://scripts/game/game.gd")
const Catalog := preload("res://scripts/machines/catalog.gd")
const M := preload("res://scripts/sim/materials.gd")
const World := preload("res://scripts/sim/world.gd")
const Fmt := preload("res://scripts/fmt.gd")
const SceneView := preload("res://scripts/scene_view.gd")

const CELL_PX := 6  ## píxeles de pantalla por celda (2 px en el SubViewport, mostrado ×3)

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
const COL_BAD := Color("#ff6b5b")
const COL_ENERGY := Color("#7fc8ff")

var game: Game
var tool := ""                   ## máquina que se está construyendo ("" = ninguna)
var hover := Vector2i(-1, -1)    ## celda bajo el ratón
var selected = null              ## máquina seleccionada
var speed := 1.0
var _ui_acc := 0.0
var _save_acc := 0.0
var _toast_t := 0.0

var pixel_font: Font
var bold_font: FontVariation
var scene_view: Node2D
var viewport: SubViewport

var tool_buttons := {}
var lbl_scale: Label
var lbl_cell: Label
var lbl_obs: Label
var lbl_bas: Label
var lbl_energy: Label
var bar_energy: ProgressBar
var bar_drain: ProgressBar
var lbl_drain: Label
var lbl_magma: Label
var lbl_in: Label
var lbl_out: Label
var chip: Label
var bar_pressure: ProgressBar
var lbl_pressure: Label
var zoom_btn: Button
var info_title: Label
var info_body: RichTextLabel
var info_btn1: Button
var info_btn2: Button
var toast: Label
var hover_lbl: Label
var dev_row: HBoxContainer
var modal: Control
var modal_title: Label
var modal_body: RichTextLabel
var modal_btn: Button
var modal_btn2: Button
var _modal_cb := Callable()


func _ready() -> void:
	var no_liga := {TextServerManager.get_primary_interface().name_to_tag("liga"): 0}
	var fv := FontVariation.new()
	fv.base_font = load("res://fonts/PixelifySans.ttf")
	fv.opentype_features = no_liga  # en Pixelify, la ligadura "fi" parece una "Á"
	pixel_font = fv
	bold_font = FontVariation.new()
	bold_font.base_font = ThemeDB.fallback_font
	bold_font.variation_embolden = 0.7
	theme = _make_theme()

	var loaded := Game.load_saved()
	game = loaded[0] if loaded[0] != null else Game.new()
	_build()
	if loaded[0] != null and loaded[1] > 60.0:
		_show_offline(loaded[1])
	if "--prueba" in OS.get_cmdline_user_args():
		dev_row.visible = true
	_update_ui()


# --- Estilo --------------------------------------------------------------------------
func _box(bg: Color, border: Color, margin := 10.0, border_w := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_content_margin_all(margin)
	return s


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	t.set_color("font_color", "Label", COL_BONE)
	t.set_stylebox("panel", "PanelContainer", _box(COL_PANEL, COL_LINE, 10))
	for st in ["normal", "disabled"]:
		t.set_stylebox(st, "Button", _box(COL_PANEL, COL_LINE, 6))
	t.set_stylebox("hover", "Button", _box(COL_PANEL.lightened(0.06), COL_EMBER, 6))
	t.set_stylebox("pressed", "Button", _box(COL_PANEL.darkened(0.15), COL_EMBER, 6))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), COL_EMBER, 6, 2))
	t.set_color("font_color", "Button", COL_BONE)
	t.set_color("font_hover_color", "Button", COL_EMBER)
	t.set_color("font_pressed_color", "Button", COL_EMBER)
	t.set_color("font_disabled_color", "Button", Color(COL_ASH, 0.5))
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
	return _label(text.to_upper(), 11, COL_ASH)


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


func _bar(fill_color: Color, height := 10) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size.y = height
	var f := StyleBoxFlat.new()
	f.bg_color = fill_color
	b.add_theme_stylebox_override("fill", f)
	return b


func _button(text: String, size := 14) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	return b


func _magma_button(text: String, size: int) -> Button:
	var b := _button(text, size)
	b.add_theme_font_override("font", pixel_font)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, COL_OBSIDIAN)
	var normal := _box(COL_MAGMA, COL_MAGMA_DEEP, 10, 0)
	normal.border_width_bottom = 5
	var hover_s := normal.duplicate()
	hover_s.bg_color = COL_MAGMA.lightened(0.08)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover_s)
	b.add_theme_stylebox_override("pressed", _box(COL_MAGMA.darkened(0.05), COL_MAGMA_DEEP, 10, 0))
	return b


# --- Construcción de la interfaz ---------------------------------------------------
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = COL_NIGHT
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Escena: SubViewport de 320×180 mostrado ×3
	viewport = SubViewport.new()
	viewport.size = Vector2i(World.W * 2, World.H * 2)
	viewport.transparent_bg = false
	viewport.snap_2d_vertices_to_pixel = true
	viewport.snap_2d_transforms_to_pixel = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(viewport)
	scene_view = SceneView.new()
	scene_view.game = game
	scene_view.ui = self
	viewport.add_child(scene_view)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _box(COL_OBSIDIAN, COL_LINE, 2))
	frame.position = Vector2(12, 12)
	add_child(frame)
	var tex := TextureRect.new()
	tex.texture = viewport.get_texture()
	tex.custom_minimum_size = Vector2(World.W * CELL_PX, World.H * CELL_PX)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.mouse_filter = Control.MOUSE_FILTER_STOP
	tex.gui_input.connect(_on_scene_input)
	tex.mouse_exited.connect(func() -> void: hover = Vector2i(-1, -1))
	frame.add_child(tex)

	toast = _label("", 15, COL_BONE, bold_font)
	toast.position = Vector2(24, 22)
	var tb_style := _box(Color(0.07, 0.05, 0.08, 0.85), COL_WARN, 8)
	toast.add_theme_stylebox_override("normal", tb_style)
	toast.visible = false
	add_child(toast)

	hover_lbl = _label("", 13, COL_ASH)
	hover_lbl.position = Vector2(14, 562)
	add_child(hover_lbl)

	var toolbar := _hbox(8)
	toolbar.position = Vector2(12, 584)
	add_child(toolbar)
	var n := 1
	for id in Catalog.ORDER:
		toolbar.add_child(_make_tool_button(id, n))
		n += 1

	var right_scroll := ScrollContainer.new()
	right_scroll.position = Vector2(992, 12)
	right_scroll.size = Vector2(276, 696)
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(right_scroll)
	var right := _vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size.x = 262
	right_scroll.add_child(right)
	_build_right(right)
	_build_modal()


func _make_tool_button(id: String, key: int) -> Button:
	var d: Dictionary = Catalog.DEFS[id]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(152, 112)
	b.clip_contents = true
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	b.add_child(m)
	var vb := _vbox(2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(vb)
	vb.add_child(_label("%d  %s" % [key, d.get("short", d["name"])], 17, COL_BONE, pixel_font))
	var cost := _label("", 13, COL_EMBER)
	vb.add_child(cost)
	var owned := _label("", 12, COL_ASH)
	vb.add_child(owned)
	var size_l := _label("%d×%d celdas" % [d["size"].x, d["size"].y], 12, COL_ASH)
	vb.add_child(size_l)
	b.pressed.connect(func() -> void: _select_tool(id))
	tool_buttons[id] = {"button": b, "cost": cost, "owned": owned}
	return b


func _build_right(right: VBoxContainer) -> void:
	right.add_child(_label("Vaciar el Vesubio", 24, COL_BONE, pixel_font))
	lbl_scale = _label("", 15, COL_MAGMA, pixel_font)
	right.add_child(lbl_scale)
	lbl_cell = _wrap(_label("", 12, COL_ASH))
	right.add_child(lbl_cell)

	var rp := PanelContainer.new()
	var rv := _vbox(4)
	var r1 := _hbox(6)
	r1.add_child(_label("Obsidiana", 14, COL_ASH))
	r1.add_child(_spacer())
	lbl_obs = _label("0", 16, COL_EMBER, pixel_font)
	r1.add_child(lbl_obs)
	rv.add_child(r1)
	var r2 := _hbox(6)
	r2.add_child(_label("Basalto", 14, COL_ASH))
	r2.add_child(_spacer())
	lbl_bas = _label("0", 16, COL_BONE, pixel_font)
	r2.add_child(lbl_bas)
	rv.add_child(r2)
	var r3 := _hbox(6)
	r3.add_child(_label("Energía", 14, COL_ASH))
	r3.add_child(_spacer())
	lbl_energy = _label("0", 16, COL_ENERGY, pixel_font)
	r3.add_child(lbl_energy)
	rv.add_child(r3)
	bar_energy = _bar(COL_ENERGY, 8)
	rv.add_child(bar_energy)
	rp.add_child(rv)
	right.add_child(rp)

	var vp := PanelContainer.new()
	var vv := _vbox(5)
	var v1 := _hbox(6)
	v1.add_child(_caps("Vaciado"))
	v1.add_child(_spacer())
	lbl_drain = _caps("")
	v1.add_child(lbl_drain)
	vv.add_child(v1)
	bar_drain = _bar(COL_MAGMA, 10)
	vv.add_child(bar_drain)
	lbl_magma = _label("", 12, COL_ASH)
	vv.add_child(lbl_magma)
	var race := _hbox(8)
	lbl_in = _label("", 13, COL_BONE)
	race.add_child(lbl_in)
	lbl_out = _label("", 13, COL_BONE)
	race.add_child(lbl_out)
	vv.add_child(race)
	chip = _label("", 13, COL_ASH, pixel_font)
	vv.add_child(chip)
	var p1 := _hbox(6)
	p1.add_child(_caps("Presión"))
	p1.add_child(_spacer())
	lbl_pressure = _caps("")
	p1.add_child(lbl_pressure)
	vv.add_child(p1)
	bar_pressure = _bar(COL_BAD, 8)
	vv.add_child(bar_pressure)
	vp.add_child(vv)
	right.add_child(vp)

	zoom_btn = _magma_button("Alejar la cámara", 18)
	zoom_btn.custom_minimum_size.y = 48
	zoom_btn.visible = false
	zoom_btn.pressed.connect(_ask_zoom)
	right.add_child(zoom_btn)

	var ip := PanelContainer.new()
	var iv := _vbox(6)
	info_title = _wrap(_label("", 18, COL_BONE, pixel_font))
	iv.add_child(info_title)
	info_body = RichTextLabel.new()
	info_body.bbcode_enabled = true
	info_body.fit_content = true
	info_body.scroll_active = false
	info_body.custom_minimum_size = Vector2(240, 0)
	info_body.add_theme_font_size_override("normal_font_size", 13)
	info_body.add_theme_font_size_override("bold_font_size", 13)
	info_body.add_theme_font_override("bold_font", bold_font)
	info_body.add_theme_color_override("default_color", COL_BONE)
	iv.add_child(info_body)
	info_btn1 = _button("", 13)
	info_btn1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_btn1.pressed.connect(_on_info_btn1)
	iv.add_child(info_btn1)
	info_btn2 = _button("", 13)
	info_btn2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_btn2.pressed.connect(_on_info_btn2)
	iv.add_child(info_btn2)
	ip.add_child(iv)
	right.add_child(ip)

	right.add_child(_wrap(_label("1–5 construir · clic derecho o Esc: soltar · Supr: quitar · F1: modo prueba", 11, COL_ASH)))

	dev_row = _hbox(4)
	dev_row.visible = false
	var dv := _vbox(4)
	dv.add_child(_caps("Modo prueba"))
	var drow1 := _hbox(4)
	for s in [1.0, 4.0, 8.0]:
		var b := _button("×%d" % int(s), 12)
		b.pressed.connect(func() -> void: speed = s)
		drow1.add_child(b)
	var bres := _button("+500", 12)
	bres.pressed.connect(func() -> void:
		game.res["obsidiana"] += 500.0
		game.res["basalto"] += 500.0)
	drow1.add_child(bres)
	dv.add_child(drow1)
	var drow2 := _hbox(4)
	var b8 := _button("8 h fuera", 12)
	b8.pressed.connect(func() -> void: _show_offline(8 * 3600.0))
	drow2.add_child(b8)
	var bdrain := _button("Vaciar 90 %", 12)
	bdrain.pressed.connect(_debug_drain)
	drow2.add_child(bdrain)
	dv.add_child(drow2)
	dev_row.add_child(dv)
	right.add_child(dev_row)


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
	panel.add_theme_stylebox_override("panel", _box(COL_PANEL, COL_MAGMA, 22))
	center.add_child(panel)
	var vb := _vbox(12)
	vb.custom_minimum_size = Vector2(500, 0)
	panel.add_child(vb)
	modal_title = _wrap(_label("", 28, COL_BONE, pixel_font))
	vb.add_child(modal_title)
	modal_body = RichTextLabel.new()
	modal_body.bbcode_enabled = true
	modal_body.fit_content = true
	modal_body.scroll_active = false
	modal_body.custom_minimum_size = Vector2(500, 0)
	modal_body.add_theme_font_size_override("normal_font_size", 16)
	modal_body.add_theme_font_size_override("bold_font_size", 16)
	modal_body.add_theme_font_override("bold_font", bold_font)
	modal_body.add_theme_color_override("default_color", COL_BONE)
	vb.add_child(modal_body)
	var row := _hbox(10)
	modal_btn = _magma_button("Seguir", 20)
	modal_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_btn.custom_minimum_size.y = 52
	modal_btn.focus_mode = Control.FOCUS_ALL
	modal_btn.pressed.connect(func() -> void: _close_modal(true))
	row.add_child(modal_btn)
	modal_btn2 = _button("Todavía no", 16)
	modal_btn2.custom_minimum_size.y = 52
	modal_btn2.pressed.connect(func() -> void: _close_modal(false))
	row.add_child(modal_btn2)
	vb.add_child(row)


# --- Modal -------------------------------------------------------------------------
func _show_modal(title: String, body: String, ok: String, cancel := "", cb := Callable()) -> void:
	modal_title.text = title
	modal_body.text = body
	modal_btn.text = ok
	modal_btn2.text = cancel
	modal_btn2.visible = cancel != ""
	_modal_cb = cb
	modal.visible = true
	modal_btn.grab_focus()


func _close_modal(accepted: bool) -> void:
	modal.visible = false
	var cb := _modal_cb
	_modal_cb = Callable()
	if accepted and cb.is_valid():
		cb.call()


func _show_offline(seconds: float) -> void:
	var got := game.apply_offline(seconds)
	var body := "Tus máquinas siguieron trabajando a medio ritmo:\n\n[b]+%s obsidiana[/b] · [b]+%s basalto[/b] · +%s energía\n\nEl magma te espera donde lo dejaste." % [
		Fmt.num(got["obsidiana"]), Fmt.num(got["basalto"]), Fmt.num(got["energia"])]
	if got["obsidiana"] + got["basalto"] < 1.0:
		body = "No tenías nada produciendo, así que no ha cambiado nada. El magma te espera donde lo dejaste."
	_show_modal("Has estado fuera " + Fmt.dur(got["seconds"]), body, "Seguir")


func _ask_zoom() -> void:
	var next: int = mini(game.scale_idx + 1, Game.SCALES.size() - 1)
	var cell_next: float = Game.SCALES[next]["cell"]
	var body := "Has vaciado [b]%s[/b]. Al alejar la cámara empiezas de nuevo, pero ahora cada celda es [b]%s[/b] de magma.\n\nTus máquinas se quedan atrás. Te llevas lo aprendido: [b]todo rinde ×%s[/b] para siempre." % [
		game.scale_name().to_lower(), Fmt.vol(cell_next), Fmt.sig(game.knowledge * Game.KNOWLEDGE_PER_SCALE)]
	_show_modal("Alejar la cámara", body, "Alejar", "Todavía no", func() -> void:
		game.zoom_out()
		scene_view.game = game
		tool = ""
		selected = null
		game.save()
		_update_ui())


# --- Interacción -----------------------------------------------------------------------
func placement_origin() -> Vector2i:
	var s: Vector2i = Catalog.DEFS[tool]["size"]
	return Vector2i(hover.x - s.x / 2, hover.y - s.y + 1)


func _select_tool(id: String) -> void:
	tool = "" if tool == id else id
	selected = null
	_update_ui()


func _on_scene_input(ev: InputEvent) -> void:
	if ev is InputEventMouse:
		var p: Vector2 = ev.position / CELL_PX
		hover = Vector2i(clampi(int(p.x), 0, World.W - 1), clampi(int(p.y), 0, World.H - 1))
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			tool = ""
			selected = null
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			if tool != "":
				var o := placement_origin()
				var why := game.place_problem(tool, o.x, o.y)
				if why == "":
					game.place(tool, o.x, o.y)
				else:
					_toast(why)
			else:
				selected = game.machine_at(hover.x, hover.y)
		_update_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or modal.visible:
		return
	var k: int = event.keycode
	if k >= KEY_1 and k < KEY_1 + Catalog.ORDER.size():
		_select_tool(Catalog.ORDER[k - KEY_1])
	elif k == KEY_ESCAPE:
		tool = ""
		selected = null
	elif k == KEY_DELETE and selected:
		_remove_selected()
	elif k == KEY_F1:
		dev_row.visible = not dev_row.visible
	else:
		return
	get_viewport().set_input_as_handled()
	_update_ui()


func _on_info_btn1() -> void:
	var id: String = tool if tool != "" else (selected.id if selected else "")
	if id != "" and game.buy_upgrade(id):
		_toast("Mejorado: %s, nivel %d" % [Catalog.DEFS[id]["upgrade"]["name"].to_lower(), game.level(id)])
	_update_ui()


func _on_info_btn2() -> void:
	_remove_selected()


func _remove_selected() -> void:
	if selected:
		game.remove(selected)
		selected = null
		_update_ui()


func _toast(text: String) -> void:
	toast.text = text
	toast.modulate.a = 1.0
	toast.visible = true
	toast.reset_size()
	_toast_t = 4.0


func _debug_drain() -> void:
	var w = game.world
	var target := int(game.magma_start * 0.08)
	for i in w.mat.size():
		if w.counts[M.MAGMA] <= target:
			break
		if w.mat[i] == M.MAGMA:
			w.set_cell(i, M.AIR)


# --- Bucle ----------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not modal.visible:
		game.advance(delta, speed)
	scene_view.refresh()
	if not game.events.is_empty():
		_toast(game.events[game.events.size() - 1])
		game.events.clear()
	if selected and not game.machines.has(selected):
		selected = null
	if _toast_t > 0.0:
		_toast_t -= delta
		toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
		toast.visible = _toast_t > 0.0
	_ui_acc += delta
	if _ui_acc >= 0.1:
		_ui_acc = 0.0
		_update_ui()
	_save_acc += delta
	if _save_acc >= 5.0:
		_save_acc = 0.0
		game.save()


func _cost_text(cost: Dictionary, short := false) -> String:
	var parts := []
	for k in cost:
		parts.append("%s %s" % [Fmt.num(cost[k]), k.substr(0, 3) + "." if short else k])
	return (" · " if short else " + ").join(parts)


func _update_ui() -> void:
	var w = game.world
	var cell := game.cell_volume()
	lbl_scale.text = "Escala %d · %s" % [game.scale_idx + 1, game.scale_name()]
	lbl_cell.text = "1 celda = %s de magma. Llevas sacado ≈ %s (%s del Vesubio)." % [
		Fmt.vol(cell), Fmt.fermi(game.total_m3), Fmt.pct(game.total_m3 / Fmt.VESUVIUS_M3 * 100.0)]
	if game.knowledge > 1.0:
		lbl_cell.text += " Bonus: ×%s." % Fmt.sig(game.knowledge)
	lbl_obs.text = Fmt.num(game.res["obsidiana"])
	lbl_bas.text = Fmt.num(game.res["basalto"])
	lbl_energy.text = "%s / %s" % [Fmt.num(game.res["energia"]), Fmt.num(game.energy_cap)]
	bar_energy.value = game.res["energia"] / game.energy_cap * 100.0

	var dr := game.drained()
	bar_drain.value = dr / Game.DRAIN_GOAL * 100.0
	lbl_drain.text = "%d %% · meta %d %%" % [int(dr * 100.0), int(Game.DRAIN_GOAL * 100.0)]
	lbl_magma.text = "Magma en la escena: %s celdas" % Fmt.num(w.counts[M.MAGMA])
	lbl_in.text = "Entra %s/s" % Fmt.sig(game.rate_in, 2)
	lbl_out.text = "Sale %s/s" % Fmt.sig(game.rate_out, 2)
	if game.rate_out > game.rate_in * 1.05:
		chip.text = "El nivel baja"
		chip.add_theme_color_override("font_color", COL_GOOD)
	elif game.rate_out < game.rate_in * 0.95:
		chip.text = "El magma sube"
		chip.add_theme_color_override("font_color", COL_WARN)
	else:
		chip.text = "Equilibrio: saca más"
		chip.add_theme_color_override("font_color", COL_ASH)
	var pr := game.pressure / Game.PRESSURE_MAX
	bar_pressure.value = pr * 100.0
	lbl_pressure.text = "¡tapón!" if pr > 0.3 else ("%d %%" % int(pr * 100.0))
	zoom_btn.visible = game.can_zoom_out()

	for id in Catalog.ORDER:
		var tb: Dictionary = tool_buttons[id]
		var c := game.build_cost(id)
		tb["cost"].text = _cost_text(c, true)
		tb["cost"].add_theme_color_override("font_color", COL_EMBER if game.can_afford(c) else COL_BAD)
		tb["owned"].text = "Tienes %d · mejora nv %d" % [game.count_of(id), game.level(id)]
		var b: Button = tb["button"]
		b.add_theme_stylebox_override("normal", _box(COL_PANEL.lightened(0.08), COL_EMBER, 6, 3) if tool == id else _box(COL_PANEL, COL_LINE, 6))

	_update_info()
	_update_hover()


func _update_info() -> void:
	var id: String = tool if tool != "" else (selected.id if selected else "")
	if id == "":
		info_title.text = "Cómo empezar" if game.machines.size() < 3 else "Tu volcán"
		if game.machines.size() >= 3:
			info_body.text = "Haz clic en una máquina para ver qué le pasa y mejorarla.\n\nPara vaciar la grieta tienes que sacar [b]más magma del que entra[/b], cada vez más hondo: las norias y bombas tienen que bajar por la chimenea según baja el nivel.\n\nNo tapes la chimenea: si el magma no puede subir, la presión revienta lo que la tape.\n\nLa [b]dinamita[/b] abre roca: haz sitio, encauza el agua o perfora hasta la cámara."
			info_btn1.visible = false
			info_btn2.visible = false
			return
		info_body.text = "1. Pon un [b]aspersor[/b] encima del magma (tecla 1): el agua lo templa en obsidiana y vapor.\n2. Pon un [b]recolector[/b] justo encima de la superficie para recoger la obsidiana (2). Si no la recoges, se vuelve a fundir.\n3. Con obsidiana, pon [b]norias[/b] en la chimenea para sacar magma (3) y [b]turbinas[/b] donde sube el vapor (4).\n\nEl magma no para de entrar. Para vaciar la grieta tienes que sacar más del que entra, cada vez más hondo. Si tapas la chimenea, la presión revienta lo que la tape.\n\nHaz clic en una máquina para ver qué le pasa."
		info_btn1.visible = false
		info_btn2.visible = false
		return
	var d: Dictionary = Catalog.DEFS[id]
	var u: Dictionary = d["upgrade"]
	var uc := game.upgrade_cost(id)
	info_btn1.visible = true
	info_btn1.text = "Mejorar: %s\n%s" % [u["name"], _cost_text(uc)]
	info_btn1.disabled = not game.can_afford(uc)
	if selected:
		info_title.text = d["name"]
		var state: String = "[color=#8fd694]Trabajando[/color]" if selected.working() else ("[color=#ff9f6b]%s[/color]" % selected.status if selected.status != "" else "Esperando")
		info_body.text = "%s\n\n%s\n\nMejora nivel %d: %s." % [state, d["desc"], game.level(id), u["effect"]]
		info_btn2.visible = true
		var refund := game.build_cost(id)
		for k in refund:
			refund[k] = refund[k] / d["growth"] * 0.5
		info_btn2.text = "Quitar · devuelve %s" % _cost_text(refund)
	else:
		info_title.text = "Construir: " + d["name"]
		var why := ""
		if hover.x >= 0:
			var o := placement_origin()
			why = game.place_problem(id, o.x, o.y)
		info_body.text = "%s\n\nCoste: [b]%s[/b]\nMejora nivel %d: %s.\n\n%s" % [
			d["desc"], _cost_text(game.build_cost(id)), game.level(id), u["effect"],
			"Haz clic en la escena para colocarla. Clic derecho para soltar." if why == "" else "[color=#ff9f6b]%s[/color]" % why]
		info_btn2.visible = false


func _update_hover() -> void:
	if hover.x < 0:
		hover_lbl.text = ""
		return
	var m = game.machine_at(hover.x, hover.y)
	var what: String = Catalog.DEFS[m.id]["name"] if m else M.name_of(game.world.get_mat(hover.x, hover.y))
	hover_lbl.text = "(%d, %d) %s" % [hover.x, hover.y, what]


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if game:
			game.save()

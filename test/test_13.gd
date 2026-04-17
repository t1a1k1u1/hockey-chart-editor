extends SceneTree
## Test: Task 13 — Supabase Upload menu item visible in File menu

var _root_scene: Node = null
var _frame: int = 0

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/ChartEditor.tscn")
	_root_scene = scene.instantiate()
	get_root().add_child(_root_scene)

func _process(_delta: float) -> bool:
	_frame += 1

	if _frame == 3:
		# Try to find the File menu popup and check for the upload item
		var menu_bar = _root_scene.get_node_or_null("RootVBox/MenuBar")
		if menu_bar == null:
			print("ASSERT FAIL: MenuBar not found")
		else:
			var file_menu = menu_bar.get_node_or_null("FileMenu")
			if file_menu == null:
				print("ASSERT FAIL: FileMenu not found")
			else:
				var found_upload = false
				for i in range(file_menu.item_count):
					if file_menu.get_item_text(i) == "Supabase にアップロード":
						found_upload = true
						break
				if found_upload:
					print("ASSERT PASS: 'Supabase にアップロード' menu item found at index with id 5")
				else:
					print("ASSERT FAIL: 'Supabase にアップロード' not found in FileMenu")
					for i in range(file_menu.item_count):
						print("  item[", i, "]: '", file_menu.get_item_text(i), "' id=", file_menu.get_item_id(i))

		# Open the File menu to show it in the screenshot
		if menu_bar:
			var file_popup = menu_bar.get_node_or_null("FileMenu")
			if file_popup:
				file_popup.popup(Rect2i(0, 22, 0, 0))

	return false

extends Control

signal closed
signal tips_requested


func _ready() -> void:
	UiPalette.paint_header(%BackButton, %Title, %Wallet)
	%Title.text = "SETTINGS"
	%BackButton.pressed.connect(func() -> void: closed.emit())
	UiPalette.prepare_scroll(%Scroll)
	if %Settings.has_signal("tips_requested"):
		%Settings.tips_requested.connect(func() -> void: tips_requested.emit())
	SaveManager.currency_changed.connect(_on_currency)
	_on_currency(SaveManager.get_cr())


func _exit_tree() -> void:
	if is_instance_valid(SaveManager) and SaveManager.currency_changed.is_connected(_on_currency):
		SaveManager.currency_changed.disconnect(_on_currency)


func _on_currency(_cr: int) -> void:
	%Wallet.text = UiPalette.money(SaveManager.get_cr())

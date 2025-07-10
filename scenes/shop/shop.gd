class_name Shop
extends Control

const SHOP_CARD = preload("res://scenes/shop/shop_card.tscn")
const SHOP_RELIC = preload("res://scenes/shop/shop_relic.tscn")

@export var shop_relics: Array[Relic]
@export var char_stats: CharacterStats
@export var run_stats: RunStats
@export var relic_handler: RelicHandler

@onready var cards: HBoxContainer = %Cards
@onready var relics: HBoxContainer = %Relics
@onready var shop_keeper_animation: AnimationPlayer = %ShopkeeperAnimation
@onready var blink_timer: Timer = %BlinkTimer
@onready var card_tooltip_popup: CardTooltipPopup = %CardTooltipPopup
@onready var modifier_handler: ModifierHandler = $ModifierHandler

@onready var dialogue_panel: PanelContainer = %DialoguePanel
@onready var response_label: Label = %ResponseLabel
@onready var dialogue_input: LineEdit = %DialogueInput
@onready var back_button: Button = %BackButton
@onready var talk_button: Button = %TalkButton
@onready var http_request: HTTPRequest = $HTTPRequest

func _ready() -> void:
	for shop_card: ShopCard in cards.get_children():
		shop_card.queue_free()
		
	for shop_relic: ShopRelic in relics.get_children():
		shop_relic.queue_free()
		
	Events.shop_card_bought.connect(_on_shop_card_bought)
	Events.shop_relic_bought.connect(_on_shop_relic_bought)

	_blink_timer_setup()
	blink_timer.timeout.connect(_on_blink_timer_timeout)
	
	talk_button.pressed.connect(_start_dialogue)
	back_button.pressed.connect(_end_dialogue)
	dialogue_input.text_submitted.connect(_on_dialogue_submitted)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and card_tooltip_popup.visible:
		card_tooltip_popup.hide_tooltip()


func populate_shop() -> void:
	_generate_shop_cards()
	_generate_shop_relics()


func _blink_timer_setup() -> void:
	blink_timer.wait_time = randf_range(1.0, 5.0)
	blink_timer.start()


func _generate_shop_cards() -> void:
	var shop_card_array: Array[Card] = []
	var available_cards: Array[Card] = char_stats.draftable_cards.duplicate_cards()
	RNG.array_shuffle(available_cards)
	shop_card_array = available_cards.slice(0, 3)
	
	for card: Card in shop_card_array:
		var new_shop_card := SHOP_CARD.instantiate() as ShopCard
		cards.add_child(new_shop_card)
		new_shop_card.card = card
		new_shop_card.current_card_ui.tooltip_requested.connect(card_tooltip_popup.show_tooltip)
		new_shop_card.gold_cost = _get_updated_shop_cost(new_shop_card.gold_cost)
		new_shop_card.update(run_stats)


func _generate_shop_relics() -> void:
	var shop_relics_array: Array[Relic] = []
	var available_relics := shop_relics.filter(
		func(relic: Relic):
			var can_appear := relic.can_appear_as_reward(char_stats)
			var already_had_it := relic_handler.has_relic(relic.id)
			return can_appear and not already_had_it
	)
	
	RNG.array_shuffle(available_relics)
	shop_relics_array = available_relics.slice(0, 3)
	
	for relic: Relic in shop_relics_array:
		var new_shop_relic := SHOP_RELIC.instantiate() as ShopRelic
		relics.add_child(new_shop_relic)
		new_shop_relic.relic = relic
		new_shop_relic.gold_cost = _get_updated_shop_cost(new_shop_relic.gold_cost)
		new_shop_relic.update(run_stats)


func _update_items() -> void:
	for shop_card: ShopCard in cards.get_children():
		shop_card.update(run_stats)

	for shop_relic: ShopRelic in relics.get_children():
		shop_relic.update(run_stats)


func _update_item_costs() -> void:
	for shop_card: ShopCard in cards.get_children():
		shop_card.gold_cost = _get_updated_shop_cost(shop_card.gold_cost)
		shop_card.update(run_stats)

	for shop_relic: ShopRelic in relics.get_children():
		shop_relic.gold_cost = _get_updated_shop_cost(shop_relic.gold_cost)
		shop_relic.update(run_stats)


func _get_updated_shop_cost(original_cost: int) -> int:
	return modifier_handler.get_modified_value(original_cost, Modifier.Type.SHOP_COST)


func _on_back_button_pressed() -> void:
	Events.shop_exited.emit()


func _on_shop_card_bought(card: Card, gold_cost: int) -> void:
	char_stats.deck.add_card(card)
	run_stats.gold -= gold_cost
	_update_items()


func _on_shop_relic_bought(relic: Relic, gold_cost: int) -> void:
	relic_handler.add_relic(relic)
	run_stats.gold -= gold_cost

	if relic is CouponsRelic:
		var coupons_relic := relic as CouponsRelic
		coupons_relic.add_shop_modifier(self)
		_update_item_costs()
	else:
		_update_items()


func _on_blink_timer_timeout() -> void:
	shop_keeper_animation.play("blink")
	_blink_timer_setup()
	
	#=========================================================

func _start_dialogue() -> void:
	# Hide shop elements
	cards.visible = false
	relics.visible = false
	%TalkButton.visible = false
	
	# Show dialogue elements
	dialogue_panel.visible = true
	dialogue_input.grab_focus()
	response_label.text = "Shopkeeper: How can I help you?"

func _end_dialogue() -> void:
	# Show shop elements
	cards.visible = true
	relics.visible = true
	%TalkButton.visible = true
	
	# Hide dialogue elements
	dialogue_panel.visible = false
	response_label.text = ""

func _on_dialogue_submitted(text: String) -> void:
	dialogue_input.text = ""
	response_label.text = "Shopkeeper: Thinking..."
	
	# Here you would make your HTTP request
	_send_dialogue_request(text)

func _send_dialogue_request(text: String) -> void:
	response_label.text = "Shopkeeper: waiting for the spirits"
	var url = "http://localhost:8080/api/chat/completions"  
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer sk-3200bd08bd604af8a95a9859d4eb4e26",
	]
	
	var data = {
		"model": "tinydolphin:latest",
		"messages": [
			{
				"role": "user",
				"content": text
			}
		],
		"stream": false  # Required for non-streamed responses
	}
	var json_data = JSON.stringify(data)


	var err = http_request.request(url, headers, HTTPClient.METHOD_POST, json_data)
	if err != OK:
		print("Request failed to start:", err)
		response_label.text = "Shopkeeper: Can't reach the spirits right now..."

func _on_request_completed(result, response_code, headers, body):
	if result != HTTPRequest.RESULT_SUCCESS:
		response_label.text = "Shopkeeper: The spirits aren't responding..."
		return
	
	var json = JSON.parse_string(body.get_string_from_utf8())
	if not json:
		response_label.text = "Shopkeeper: *mumbles incoherently*"
		return
	
	if json.has("choices") and json["choices"].size() > 0:
		var response = json["choices"][0]["message"]["content"]
		response_label.text = "Shopkeeper: " + response
	else:
		response_label.text = "Shopkeeper: *puzzled look*"

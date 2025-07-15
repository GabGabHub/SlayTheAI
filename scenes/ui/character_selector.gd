extends Control

const RUN_SCENE = preload("res://scenes/run/run.tscn")
const ASSASSIN_STATS := preload("res://characters/assassin/assassin.tres")
const WARRIOR_STATS := preload("res://characters/warrior/warrior.tres")
const WIZARD_STATS := preload("res://characters/wizard/wizard.tres")

@export var run_startup: RunStartup

@onready var title: Label = %Title
@onready var description: Label = %Description
@onready var character_portrait: TextureRect = %CharacterPortrait

@onready var http_request: HTTPRequest = $HTTPRequest

var current_character: CharacterStats : set = set_current_character

var current_image_prefix := ""
var poll_timer := 0.0
const POLL_INTERVAL := 1.0  # Check every 1 second
const MAX_POLL_TIME := 30.0

func _ready() -> void:
	set_current_character(WARRIOR_STATS)
	fetch_prompt("a knight in shining armor")


func set_current_character(new_character: CharacterStats) -> void:
	current_character = new_character
	title.text = current_character.character_name
	description.text = current_character.description
	character_portrait.texture = current_character.portrait


func _on_start_button_pressed() -> void:
	print("Start new Run with %s" % current_character.character_name)
	run_startup.type = RunStartup.Type.NEW_RUN
	run_startup.picked_character = current_character
	get_tree().change_scene_to_packed(RUN_SCENE)


func _on_warrior_button_pressed() -> void:
	current_character = WARRIOR_STATS


func _on_wizard_button_pressed() -> void:
	current_character = WIZARD_STATS


func _on_assassin_button_pressed() -> void:
	current_character = ASSASSIN_STATS

func fetch_prompt(description: String):
	var url = "http://localhost:8080/api/chat/completions"  
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer sk-3200bd08bd604af8a95a9859d4eb4e26",
	]
	
	var data = {
		"model": "phi3:mini",
		"messages": [
			{
				"role": "user",
				"content": description
			}
		],
		"stream": false  # Required for non-streamed responses
	}
	var json_data = JSON.stringify(data)

	print(description)

	var err = http_request.request(url, headers, HTTPClient.METHOD_POST, json_data)
	if err != OK:
		print("Request failed to start:", err)
		
func _on_request_completed(result, response_code, headers, body):
	
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		
		if not json:
			return
			
		var response = json["choices"][0]["message"]["content"]
		_send_to_comfy(response)
	else:
		print("Prompt error: ", response_code)
		
func _send_to_comfy(prompt_text: String):
	current_image_prefix = "godot_sprite_%s" % Time.get_unix_time_from_system()
	var comfy_payload = {
		  "prompt": {
			"1": {
			  "inputs": {
				"ckpt_name": "Public-Prompts-Pixel-Model.ckpt"
			  },
			  "class_type": "CheckpointLoaderSimple"
			},
			"2": {
			  "inputs": {
				"width": 512,
				"height": 512,
				"batch_size": 1
			  },
			  "class_type": "EmptyLatentImage"
			},
			"3": {
			  "inputs": {
				"seed": 265827286759473,
				"steps": 20,
				"cfg": 8,
				"sampler_name": "euler",
				"scheduler": "normal",
				"denoise": 1,
				"model": ["1", 0],
				"positive": ["4", 0],
				"negative": ["8", 0],
				"latent_image": ["2", 0]
			  },
			  "class_type": "KSampler"
			},
			"4": {
			  "inputs": {
				"text": prompt_text,
				"clip": ["1", 1]
			  },
			  "class_type": "CLIPTextEncode"
			},
			"5": {
			  "inputs": {
				"tile_size": 512,
				"overlap": 64,
				"temporal_size": 64,
				"temporal_overlap": 8,
				"samples": ["3", 0],
				"vae": ["1", 2]
			  },
			  "class_type": "VAEDecodeTiled"
			},
			"6": {
			  "inputs": {
				"images": ["5", 0]
			  },
			  "class_type": "PreviewImage"
			},
			"7": {
			  "inputs": {
				"filename_prefix": "knight"
			  },
			  "class_type": "SaveImage"
			},
			"8": {
			  "inputs": {
				"text": "realistic, blurry, photo, high detail, noise, low contrast, background clutter",
				"clip": ["1", 1]
			  },
			  "class_type": "CLIPTextEncode"
			}
		  },
		  "client_id": "GodotGameEngine" 
		}	
		
	var comfy_request = HTTPRequest.new()
	add_child(comfy_request)
	comfy_request.request_completed.connect(_on_prompt_submitted)
	comfy_request.request(
		"http://localhost:8000/prompt",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(comfy_payload)
	)

func _on_prompt_submitted(result, response_code, headers, body):
	if response_code == 200:
		print("Generation started, beginning file polling...")
		var texture = load("res://art/AIart/wizard_00022_.png")
		current_character.portrait = texture
		poll_timer = 0.0
		set_process(true)  # Enable polling
	else:
		print("ComfyUI submission failed: ", response_code)

func _process(delta):
	poll_timer += delta
	
	if poll_timer >= POLL_INTERVAL:
		poll_timer = 0.0
		_check_for_image()
	
	if poll_timer >= MAX_POLL_TIME:
		set_process(false)
		print("Timeout waiting for image")

func _check_for_image():
	var expected_filename = "%s_00001.png" % current_image_prefix
	var url = "http://localhost:8000/view?filename=%s" % expected_filename
	
	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_image_check_completed)
	request.request(url, [], HTTPClient.METHOD_GET)

func _on_image_check_completed(result, response_code, headers, body):
	if response_code == 200:
		set_process(false)  # Stop polling
		_handle_generated_image(body)
	elif response_code == 404:
		# Image not ready yet, continue polling
		pass
	else:
		print("Image check error: ", response_code)
		set_process(false)

func _handle_generated_image(image_data: PackedByteArray):
	var image = Image.new()
	var error = image.load_png_from_buffer(image_data)
	
	if error != OK:
		print("Failed to load image")
		return
	
	# Create texture and display it
	var texture = ImageTexture.create_from_image(image)
	current_character.portrait = texture
	
	# Optional: Save to Godot's user folder
	var save_path = "user://generated/%s.png" % current_image_prefix
	DirAccess.make_dir_recursive_absolute("user://generated/")
	image.save_png(save_path)

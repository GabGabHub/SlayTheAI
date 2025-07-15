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

var current_prompt_id: String = ""

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
		print(response)
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
				"text": response,
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
	else:
		print("Prompt error: ", response_code)

func _on_prompt_submitted(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		current_prompt_id = response["prompt_id"]
		print(current_prompt_id)
		
		# Start polling for completion
		_poll_history()

func _poll_history():
	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_history_checked)
	request.request(
		"http://localhost:8000/history/" + current_prompt_id,
		[],
		HTTPClient.METHOD_GET
	)

func _on_history_checked(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code == 200:
		var history = JSON.parse_string(body.get_string_from_utf8())
		print(history)
		
		if history.has(current_prompt_id):
			var outputs = history[current_prompt_id].get("outputs", {})
			
			# Method 1: Find SaveImage node dynamically
			var image_data = _find_image_output(outputs)
			
			# Method 2: Use known node ID with fallback
			if outputs.has("7"):
				var image_path = outputs["7"]["images"][0]["filename"]
				_download_image(image_path)
			else:
				print("Error: SaveImage node (7) not found in outputs. Full response: ", outputs)
				# Fallback: Scan all nodes for images
				for node_id in outputs:
					if outputs[node_id].has("images"):
						_download_image(outputs[node_id]["images"][0]["filename"])
						return
				
				print("No image nodes found. Still processing?")
				await get_tree().create_timer(1.0).timeout
				_poll_history()
		else:
			print("no such thing")

# Helper function to find the first node with image output
func _find_image_output(outputs: Dictionary):
	for node_id in outputs:
		var node_data = outputs[node_id]
		if node_data.has("images") and node_data["images"].size() > 0:
			return node_data["images"][0]["filename"]
	return ""

func _download_image(filename: String):
	print("it reached download image")
	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_image_downloaded)
	
	# Extract just the filename (remove ComfyUI's output folder path)
	var image_name = filename.get_file()
	request.request(
		"http://localhost:8000/view?filename=" + image_name,
		[],
		HTTPClient.METHOD_GET
	)

func _on_image_downloaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	print("it downloaded image?")
	if response_code == 200:
		var image = Image.new()
		image.load_png_from_buffer(body)
		
		# Save to Godot's user folder
		var save_path = "res://art/AIart/generated_sprite.png"
		DirAccess.make_dir_recursive_absolute("user://")
		image.save_png(save_path)
		
		# Display the image
		var texture = ImageTexture.create_from_image(image)
		current_character.portrait = texture
	else:
		print("Image download failed: ", response_code)

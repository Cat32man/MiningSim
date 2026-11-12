extends SceneTree
## Makes the private co-op key: run once with
##   godot --headless --path . --script res://scripts/tools/make_coop_key.gd
## It writes scripts/net/coop_key.gd, which git ignores (the repo is public). Every build
## made with the same key file can host and join the others; builds without it can't.
## Running it again makes a new key, so everyone needs the new build afterwards.

const OUT := "res://scripts/net/coop_key.gd"


func _init() -> void:
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var cert := crypto.generate_self_signed_certificate(key, "CN=miningsim,O=MiningSim,C=US",
		"20260101000000", "20460101000000")
	var secret := crypto.generate_random_bytes(32).hex_encode()
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("""extends RefCounted
## Private co-op key, made by scripts/tools/make_coop_key.gd. Never commit this file:
## anyone with it can join (and host for) your games.

const SECRET := "%s"
const CERT := \"\"\"%s\"\"\"
const PRIVATE := \"\"\"%s\"\"\"
""" % [secret, cert.save_to_string(), key.save_to_string()])
	f.close()
	print("Wrote ", OUT)
	quit()

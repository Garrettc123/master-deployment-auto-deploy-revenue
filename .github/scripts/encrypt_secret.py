"""Encrypt a secret value using a GitHub repository public key (libsodium/NaCl)."""
import base64
import os

from nacl import encoding, public

public_key_b64 = os.environ["PUBLIC_KEY"]
secret_value = os.environ["SECRET_VALUE"]

key = public.PublicKey(public_key_b64.encode("utf-8"), encoding.Base64Encoder())
box = public.SealedBox(key)
print(base64.b64encode(box.encrypt(secret_value.encode("utf-8"))).decode("utf-8"))

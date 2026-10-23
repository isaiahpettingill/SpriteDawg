#!/usr/bin/env python3
"""Fetch original test-only Aseprite assets, checking immutable Git blob hashes.
These upstream assets are not included in the MIT application or APK.
"""
import base64
import concurrent.futures
import hashlib
import json
from pathlib import Path
import urllib.request

FIXTURES = {'1empty3.aseprite': 'c28079f683328ac9640b0c7bd88486be85feaedb', '2f-index-3x3.aseprite': '55d2ce4101e9a7a2150337e935f059fe78208dc1', '2x2tilemap2x2tile.aseprite': '7f215ac5afe296996ed9f9cf0b5a16d7b58ea355', '2x3tilemap-indexed.aseprite': '714b0abe3ce5c3e80cee79c1d32366e37416165a', '3x2tilemap-grayscale.aseprite': '3a4293388e368b06716c04813baa74d7366e3e39', '4f-index-4x4.aseprite': 'e98a603e0297feb7512f2933aeb10f72766844dc', 'abcd.aseprite': '6926af49416e042048075438af440614a5159beb', 'bg-index-3.aseprite': 'f36d2b4990f22bd5ccf7edcad9186555c3552722', 'cut_paste.aseprite': '9007d941edab286b8d4680a187df5e8911916de4', 'file-tests-props.aseprite': 'dd26e60a3a2e9ba65f4b2fe0fabf4bd180f19f6b', 'groups2.aseprite': '4310c50f4c5d273aafa254440447c7fc92f735e6', 'groups3abc.aseprite': 'baced93490dbfcc9c191db909510af39d73e26ef', 'link.aseprite': '461eba73e91e4b5e084337189943ebe88c1a4c26', 'point2frames.aseprite': '1e97da0fb950068d413d6e500a2f425db8ac6060', 'point4frames.aseprite': 'a888f17342bb0285f16abf75f8a055a4b6a0a985', 'slices-moving.aseprite': '42d2a3f1f3cdbc4634320c53ea0d69a1d18197e9', 'slices.aseprite': '84dc342e17f8c351b3d708736ecb2c29893f57a4', 'tags3.aseprite': 'dd9368965dadcda8f0c210ad7ab5738e49ea6432', 'tags3x123reps.aseprite': '1e8d950c575f2f4cc7a73a8feaf0196b3f5d1aec', 'z-order.aseprite': 'd7c3e3975956bd8ac7cc0ca8bd27352cfd3b3fc0'}
ROOT = Path(__file__).resolve().parents[1] / "app/src/test/resources/upstream"

def fetch(item):
    name, sha = item
    target = ROOT / name
    def valid(data):
        return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest() == sha
    if target.exists() and valid(target.read_bytes()):
        return
    url = "https://api.github.com/repos/aseprite/aseprite/git/blobs/" + sha
    request = urllib.request.Request(url, headers={"User-Agent": "PocketPixel-fixture-tests"})
    response = json.loads(urllib.request.urlopen(request, timeout=60).read())
    data = base64.b64decode(response["content"])
    if not valid(data):
        raise RuntimeError("Fixture hash mismatch: " + name)
    target.write_bytes(data)

if __name__ == "__main__":
    ROOT.mkdir(parents=True, exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(fetch, FIXTURES.items()))
    print("Verified", len(FIXTURES), "upstream test sprites")

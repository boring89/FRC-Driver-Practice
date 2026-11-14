#!/usr/bin/env python3
"""Small Onshape API client for pulling field and robot CAD.

Reads ONSHAPE_ACCESS_KEY / ONSHAPE_SECRET_KEY from .env. Every API call counts
against the account's allocation, so JSON responses are cached under
cad/export/cache and reused on later runs.

  scripts/onshape.py info <onshape url>          list the document's elements
  scripts/onshape.py get <onshape url> <path>    GET an element sub-path as JSON
  scripts/onshape.py gltf <onshape url> <out>    export the element as .glb or .gltf
"""

import argparse
import hashlib
import json
import re
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

import requests

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "cad" / "export" / "cache"
API = "/api/v10"


def load_keys():
    keys = {}
    for line in (ROOT / ".env").read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            name, value = line.split("=", 1)
            keys[name.strip()] = value.strip().strip("\"'")
    return keys["ONSHAPE_ACCESS_KEY"], keys["ONSHAPE_SECRET_KEY"]


class Element:
    """An Onshape document URL split into host, document, workspace/version and element."""

    def __init__(self, url):
        parsed = urlparse(url)
        match = re.match(r"/documents/(\w+)/([wvm])/(\w+)(?:/e/(\w+))?", parsed.path)
        if not match:
            sys.exit(f"Not an Onshape document URL: {url}")
        self.host = f"{parsed.scheme}://{parsed.netloc}"
        self.did, self.wvm, self.wvmid, self.eid = match.groups()

    def document_path(self):
        return f"d/{self.did}/{self.wvm}/{self.wvmid}"

    def path(self):
        return f"{self.document_path()}/e/{self.eid}"


class Client:
    def __init__(self):
        self.session = requests.Session()
        self.auth = load_keys()
        self.calls = 0

    def request(self, method, url, **kwargs):
        """Sends one request, following redirects by hand so auth survives a host change."""
        for _ in range(5):
            self.calls += 1
            response = self.session.request(
                method, url, auth=self.auth, allow_redirects=False, timeout=600, **kwargs)
            if response.status_code not in (301, 302, 303, 307, 308):
                return response
            url = response.headers["Location"]
            if method != "GET" and response.status_code == 303:
                method = "GET"
                kwargs.pop("json", None)
        sys.exit("Too many redirects")

    def get_json(self, host, path, params=None):
        """GETs JSON from the API, served from the on-disk cache when available."""
        key = hashlib.sha1(json.dumps([host, path, params], sort_keys=True).encode()).hexdigest()
        cached = CACHE / f"{key}.json"
        if cached.exists():
            return json.loads(cached.read_text())
        response = self.request(
            "GET", f"{host}{API}{path}", params=params, headers={"Accept": "application/json"})
        if response.status_code != 200:
            sys.exit(f"GET {path} -> {response.status_code}: {response.text[:500]}")
        CACHE.mkdir(parents=True, exist_ok=True)
        cached.write_text(response.text)
        return response.json()


def cmd_info(client, args):
    element = Element(args.url)
    document = client.get_json(element.host, f"/documents/{element.did}")
    print(f"Document: {document['name']} (owner: {document.get('owner', {}).get('name')})")
    elements = client.get_json(element.host, f"/documents/{element.document_path()}/elements")
    for item in elements:
        marker = "->" if item["id"] == element.eid else "  "
        print(f"{marker} {item['id']}  {item['elementType']:<12} {item['name']}")


def cmd_get(client, args):
    element = Element(args.url)
    params = dict(pair.split("=", 1) for pair in args.param)
    data = client.get_json(element.host, f"/{args.kind}/{element.path()}/{args.path}".rstrip("/"), params)
    text = json.dumps(data, indent=1)
    if args.out:
        Path(args.out).write_text(text)
        print(f"wrote {args.out} ({len(text)} bytes)")
    else:
        print(text[:args.limit])


def cmd_gltf(client, args):
    element = Element(args.url)
    out = Path(args.out)
    if out.exists():
        print(f"{out} already exists; not exporting again")
        return
    body = {
        "formatName": "GLB" if out.suffix == ".glb" else "GLTF",
        "storeInDocument": False,
        "angularTolerance": args.angle,
        "distanceTolerance": args.chord,
        "maximumChordLength": 10,
    }
    response = client.request(
        "POST", f"{element.host}{API}/{args.kind}/{element.path()}/translations", json=body)
    if response.status_code != 200:
        sys.exit(f"translation request -> {response.status_code}: {response.text[:500]}")
    job = response.json()
    while job["requestState"] == "ACTIVE":
        time.sleep(args.poll)
        job = client.request(
            "GET", f"{element.host}{API}/translations/{job['id']}",
            headers={"Accept": "application/json"}).json()
        print(f"  translation {job['requestState']}", flush=True)
    if job["requestState"] != "DONE":
        sys.exit(f"translation failed: {job.get('failureReason')}")
    out.parent.mkdir(parents=True, exist_ok=True)
    for index, data_id in enumerate(job["resultExternalDataIds"]):
        response = client.request(
            "GET", f"{element.host}{API}/documents/d/{element.did}/externaldata/{data_id}",
            headers={"Accept": "application/octet-stream"})
        if response.status_code != 200:
            sys.exit(f"download -> {response.status_code}: {response.text[:500]}")
        target = out if index == 0 else out.with_name(f"{out.stem}_{index}{out.suffix}")
        target.write_bytes(response.content)
        print(f"wrote {target} ({len(response.content) / 1e6:.1f} MB)")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    info = commands.add_parser("info")
    info.add_argument("url")
    info.set_defaults(run=cmd_info)

    get = commands.add_parser("get")
    get.add_argument("url")
    get.add_argument("path")
    get.add_argument("--kind", default="assemblies", choices=["assemblies", "partstudios"])
    get.add_argument("--param", action="append", default=[], help="query parameter as name=value")
    get.add_argument("--out")
    get.add_argument("--limit", type=int, default=3000)
    get.set_defaults(run=cmd_get)

    gltf = commands.add_parser("gltf")
    gltf.add_argument("url")
    gltf.add_argument("out")
    gltf.add_argument("--kind", default="assemblies", choices=["assemblies", "partstudios"])
    gltf.add_argument("--angle", type=float, default=0.35, help="angular tolerance, rad")
    gltf.add_argument("--chord", type=float, default=0.002, help="chord tolerance, m")
    gltf.add_argument("--poll", type=float, default=10.0, help="seconds between status checks")
    gltf.set_defaults(run=cmd_gltf)

    args = parser.parse_args()
    client = Client()
    args.run(client, args)
    print(f"[{client.calls} API call(s)]")


if __name__ == "__main__":
    main()

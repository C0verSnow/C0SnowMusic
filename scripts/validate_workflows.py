# -*- coding: utf-8 -*-
"""Validate workflow documentation without building or calling Bilibili."""

import argparse
import json
import re
import subprocess
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique_keys(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def validate(path, source_root=None):
    data = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_keys)
    upstream = data["upstream"]
    commit = upstream["commit"]
    require(re.fullmatch(r"[0-9a-f]{40}", commit), "Upstream commit must be pinned")
    requests = data["requests"]
    local_steps = data["local_steps"]
    nodes = requests + local_steps
    ids = [node["id"] for node in nodes]
    require(len(ids) == len(set(ids)), "Request/local step IDs must be unique")
    require(requests and local_steps and data["workflows"], "Workflow sections cannot be empty")
    used = set()
    workflow_ids = set()
    for workflow in data["workflows"]:
        require(workflow["id"] not in workflow_ids, "Duplicate workflow ID")
        workflow_ids.add(workflow["id"])
        require(workflow["steps"], "Workflow cannot be empty")
        for step in workflow["steps"]:
            require(step in ids, f"Unknown step: {step}")
            used.add(step)
    require(used == set(ids), f"Unreferenced steps: {set(ids) - used}")

    for node in requests:
        name = node["id"]
        require(node["purpose"] and node["condition"], f"Missing purpose/condition: {name}")
        request = node["request"]
        require(request["method"] in {"GET", "POST"}, f"Invalid method: {name}")
        require(request["url"].startswith("https://") or request["url"] == "{{selected_stream_url}}", f"Invalid URL: {name}")
        require(isinstance(request["headers"], dict) and isinstance(request["query"], dict), f"Invalid request maps: {name}")
        require(all(isinstance(v, str) for v in request["query"].values()), f"Query must use string values: {name}")
        if request["wbi_signed"]:
            require({"wts", "w_rid"} <= request["query"].keys(), f"Missing WBI parameters: {name}")
        else:
            require("w_rid" not in request["query"], f"Unexpected WBI signature: {name}")
        response = node["response"]
        require(response["format"] in {"json", "html", "binary"}, f"Invalid response format: {name}")
        require(response["success"] and response["extract"], f"Missing response rules: {name}")

    by_id = {node["id"]: node for node in requests}
    dash = by_id["play_dash"]["request"]["query"]
    require(dash["fnval"] == "272" and dash["platform"] == "pc", "Incorrect default DASH options")
    require({"bvid", "cid"} <= dash.keys() and "qn" not in dash, "Incorrect default play identifiers/options")
    html5 = by_id["play_html5"]["request"]["query"]
    require(html5["fnval"] == "0" and html5["platform"] == "html5" and html5["high_quality"] == "1", "Incorrect HTML5 fallback")
    ticket = by_id["wbi_ticket"]["request"]
    require(ticket["method"] == "POST" and ticket["body"] == {"encoding": "empty", "value": ""}, "Ticket requires an empty POST body")
    require("Cookie" not in ticket["headers"] and "Referer" not in ticket["headers"], "Ticket headers differ from source")
    require(by_id["media_get"]["response"]["format"] == "binary", "Media is not JSON")
    require(by_id["web_login"]["response"]["format"] == "html", "Web login is an HTML page")
    require(sorted(data["wbi_signing"]["mixin_index"]) == list(range(64)), "WBI index must be a permutation of 0..63")

    if source_root:
        actual = subprocess.check_output(["git", "-C", str(source_root), "rev-parse", "HEAD"], text=True).strip()
        require(actual == commit, f"Source checkout differs: expected {commit}, got {actual}")
    source_count = 0
    for node in nodes + [data["wbi_signing"]]:
        require(node["sources"], "Every step needs source evidence")
        for source in node["sources"]:
            relative = Path(source["path"])
            require(not relative.is_absolute() and ".." not in relative.parts, "Source path must be relative")
            require(isinstance(source["line"], int) and source["line"] > 0, "Source line must be positive")
            expected = f'{upstream["repository"]}/blob/{commit}/{source["path"]}#L{source["line"]}'
            require(source["url"] == expected, "Source URL does not match pinned path/line")
            if source_root:
                lines = (source_root / relative).read_text(encoding="utf-8").splitlines()
                require(source["line"] <= len(lines), f"Source line out of range: {relative}")
                require(source["symbol_or_text"] in lines[source["line"] - 1], f"Source text differs: {relative}:{source['line']}")
            source_count += 1
    print(f"PASS: {len(requests)} requests, {len(data['workflows'])} workflows, {source_count} source references")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, help="Optional NeriPlayer checkout at the pinned commit")
    args = parser.parse_args()
    validate(Path(__file__).resolve().parents[1] / "workflows.json", args.source_root)

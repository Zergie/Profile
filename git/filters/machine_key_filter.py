"""Git clean/smudge filter that keeps machine-specific keys of app config files out of the repo.

Registered in git/.gitconfig as filter "machine-keys" and attached to files in .gitattributes:

    python -I git/filters/machine_key_filter.py clean|smudge <path>

git/machine-keys.json lists, per repo-relative file path, the keys to exclude as dot-separated
paths whose segments may use * and ? wildcards (matched case-sensitively).

clean  (working file -> repo): reads the file from stdin, removes the excluded keys and writes
       the result to stdout. The removed keys are saved to <git common dir>/machine-keys/<path>.json.
smudge (repo -> working file): reads the repo version from stdin, removes excluded keys that
       older commits may still contain, and merges this machine's saved keys back in, so a
       checkout or pull keeps this machine's values.

Options per file:
  "format":  "json" (default) or "toml".
  "indent":  "tab" for tab indentation (JSON only; default: two spaces).
  "trailer": "orca-md5" for OrcaSlicer's "# MD5 checksum" line, which is dropped on clean and
             recomputed on smudge (MD5 of the LF-normalized JSON, uppercase hex).

JSON output has its object keys sorted, so the app's save order doesn't create diffs.
TOML is handled line by line, so the app's own formatting and comments survive: a pattern that
matches a table (e.g. "projects" or "mcp_servers.node_repl") removes that table and its subtables;
a pattern one segment longer than a table path removes a key line (e.g. "desktop.migrated*", or
"notify" for a top-level key). Multi-line arrays, inline tables and multi-line strings stay together.

Files without an entry pass through unchanged. Any error exits non-zero; with
filter.machine-keys.required = true git then refuses to continue instead of committing
machine-specific keys.

Written in Python because git runs it for every changed file it reads: Python with json and
tomllib starts in ~0.2 s, PowerShell took ~2.5 s.
"""

import hashlib
import json
import os
import re
import subprocess
import sys
from fnmatch import fnmatchcase

CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "machine-keys.json")


def matches(name, pattern):
    return fnmatchcase(name, pattern)


def cache_path_for(relative_path):
    common_dir = subprocess.run(
        ["git", "rev-parse", "--git-common-dir"], capture_output=True, text=True, check=True
    ).stdout.strip()
    return os.path.join(common_dir, "machine-keys", relative_path + ".json")


def write_cache(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as file:
        json.dump(data, file, indent=2, ensure_ascii=False)
        file.write("\n")


def read_cache(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8-sig") as file:
        data = json.load(file)
    return data if isinstance(data, list) else [data]


# --- JSON --------------------------------------------------------------------------------------

def remove_json_keys(obj, segments, prefix, removed):
    for key in list(obj.keys()):
        if not matches(key, segments[0]):
            continue
        if len(segments) == 1:
            removed.append({"path": prefix + [key], "value": obj.pop(key)})
        elif isinstance(obj[key], dict):
            remove_json_keys(obj[key], segments[1:], prefix + [key], removed)


def filter_json(text, file_config, cache_path, clean):
    trailer = file_config.get("trailer")
    if trailer == "orca-md5":
        text = re.sub(r"(?m)^# MD5 checksum [0-9A-Fa-f]+\s*\Z", "", text)
    elif trailer:
        raise ValueError(f"Unknown trailer '{trailer}'")

    root = json.loads(text)
    if not isinstance(root, dict):
        raise ValueError("not a JSON object")

    removed = []
    for pattern in file_config.get("exclude", []):
        remove_json_keys(root, pattern.split("."), [], removed)

    if clean:
        write_cache(cache_path, removed)
    else:
        for entry in read_cache(cache_path):
            parent = root
            for segment in entry["path"][:-1]:
                if segment not in parent or parent[segment] is None:
                    parent[segment] = {}
                parent = parent[segment]
                if not isinstance(parent, dict):
                    break
            else:
                parent[entry["path"][-1]] = entry["value"]

    indent = "\t" if file_config.get("indent") == "tab" else 2
    output = json.dumps(root, indent=indent, ensure_ascii=False, sort_keys=True)
    if not clean and trailer == "orca-md5":
        checksum = hashlib.md5(output.encode("utf-8")).hexdigest().upper()
        return f"{output}\n# MD5 checksum {checksum}\n"
    return output + "\n"


# --- TOML --------------------------------------------------------------------------------------

def split_toml_key(text):
    segments, current, i = [], [], 0
    while i < len(text):
        c = text[i]
        if c == '"':
            i += 1
            while i < len(text) and text[i] != '"':
                if text[i] == "\\" and i + 1 < len(text):
                    i += 1
                current.append(text[i])
                i += 1
        elif c == "'":
            end = text.find("'", i + 1)
            end = len(text) if end < 0 else end
            current.append(text[i + 1:end])
            i = end
        elif c == ".":
            segments.append("".join(current).strip())
            current = []
        elif not c.isspace():
            current.append(c)
        i += 1
    segments.append("".join(current).strip())
    return segments


def toml_key_text(line):
    """The key is everything before the first = that is outside quotes."""
    quote = None
    for i, c in enumerate(line):
        if quote:
            if c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c == "=":
            return line[:i]
    return None


def update_value_state(line, state):
    """Tracks open brackets and multi-line strings so a value spanning lines stays one item."""
    i = 0
    while i < len(line):
        if state["multiline"]:
            end = line.find(state["multiline"], i)
            if end < 0:
                return
            i = end + 3
            state["multiline"] = None
            continue
        c = line[i]
        if c == "#":
            return
        if line.startswith('"""', i) or line.startswith("'''", i):
            state["multiline"] = line[i:i + 3]
            i += 3
            continue
        if c == '"':
            i += 1
            while i < len(line) and line[i] != '"':
                if line[i] == "\\":
                    i += 1
                i += 1
        elif c == "'":
            end = line.find("'", i + 1)
            i = len(line) if end < 0 else end
        elif c in "[{":
            state["depth"] += 1
        elif c in "]}":
            state["depth"] -= 1
        i += 1


HEADER = re.compile(r"^\[\[(.+)\]\]\s*(#.*)?$|^\[(.+)\]\s*(#.*)?$")


def toml_items(lines):
    """Splits the file into header, key (with continuation lines) and other (comment/blank) items."""
    items, table, header, i = [], [], "", 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        match = HEADER.match(stripped)
        if match:
            table = split_toml_key(match.group(1) or match.group(3))
            header = stripped
            items.append({"kind": "header", "lines": [line], "table": table, "header": header})
            i += 1
            continue
        key_text = toml_key_text(line) if stripped and not stripped.startswith("#") else None
        if key_text is None:
            items.append({"kind": "other", "lines": [line], "table": table, "header": header})
            i += 1
            continue
        state = {"depth": 0, "multiline": None}
        update_value_state(line[len(key_text) + 1:], state)
        block = [line]
        i += 1
        while (state["depth"] > 0 or state["multiline"]) and i < len(lines):
            update_value_state(lines[i], state)
            block.append(lines[i])
            i += 1
        items.append({"kind": "key", "lines": block, "table": table, "header": header,
                      "key": split_toml_key(key_text)})
    return items


def pattern_matches(path, pattern, prefix=False):
    if len(pattern) > len(path) or (not prefix and len(pattern) != len(path)):
        return False
    return all(matches(name, part) for name, part in zip(path, pattern))


def compress_blank_lines(lines):
    result = []
    for line in lines:
        if not line.strip() and (not result or not result[-1].strip()):
            continue
        result.append(line)
    while result and not result[-1].strip():
        result.pop()
    return result


def remove_toml_excluded(lines, patterns):
    pattern_segments = [split_toml_key(pattern) for pattern in patterns]
    kept, removed, current_table = [], [], None

    for item in toml_items(lines):
        if item["kind"] == "header":
            if any(pattern_matches(item["table"], p, prefix=True) for p in pattern_segments):
                current_table = {"kind": "table", "header": item["header"], "lines": [item["lines"][0]]}
                removed.append(current_table)
            else:
                current_table = None
                kept.append(item["lines"][0])
            continue
        if current_table:
            current_table["lines"].extend(item["lines"])
            continue
        if item["kind"] == "key" and any(
            pattern_matches(item["table"] + item["key"], p) for p in pattern_segments
        ):
            removed.append({"kind": "key", "header": item["header"], "lines": item["lines"]})
            continue
        kept.extend(item["lines"])

    for entry in removed:
        if entry["kind"] == "table":
            while len(entry["lines"]) > 1 and not entry["lines"][-1].strip():
                entry["lines"].pop()
    return compress_blank_lines(kept), removed


def filter_toml(text, file_config, cache_path, clean):
    # Removed on smudge too: older commits may still contain machine keys, which the cache replaces.
    lines, removed = remove_toml_excluded(text.rstrip("\n").split("\n"), file_config.get("exclude", []))

    if clean:
        write_cache(cache_path, removed)
        return "\n".join(lines) + "\n"

    inserted_after = {}
    for entry in read_cache(cache_path):
        entry_lines = list(entry["lines"])
        if entry["kind"] == "table":
            if lines:
                lines.append("")
            lines.extend(entry_lines)
            continue
        header = entry.get("header") or ""
        if not header:
            # Top-level keys must come before the first table.
            index = 0
            while index < len(lines) and (not lines[index].strip() or lines[index].strip().startswith("#")):
                index += 1
        else:
            index = next((i for i, line in enumerate(lines) if line.strip() == header), -1)
            if index < 0:
                if lines:
                    lines.append("")
                lines.append(header)
                lines.extend(entry_lines)
                continue
            index += 1
        index += inserted_after.get(header, 0)
        lines[index:index] = entry_lines
        inserted_after[header] = inserted_after.get(header, 0) + len(entry_lines)
    return "\n".join(lines) + "\n"


# --- main --------------------------------------------------------------------------------------

def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("clean", "smudge"):
        raise SystemExit("usage: machine_key_filter.py clean|smudge <path>")
    clean = sys.argv[1] == "clean"
    relative_path = sys.argv[2].replace("\\", "/")
    data = sys.stdin.buffer.read()

    try:
        with open(CONFIG_PATH, encoding="utf-8") as file:
            file_config = json.load(file)["files"].get(relative_path)

        if file_config is None or not data:
            sys.stdout.buffer.write(data)
            return

        text = data.decode("utf-8-sig").replace("\r\n", "\n")
        cache_path = cache_path_for(relative_path)
        file_format = file_config.get("format", "json")
        if file_format == "json":
            output = filter_json(text, file_config, cache_path, clean)
        elif file_format == "toml":
            output = filter_toml(text, file_config, cache_path, clean)
        else:
            raise ValueError(f"Unknown format '{file_format}'")
        sys.stdout.buffer.write(output.encode("utf-8"))
    except Exception as error:
        print(f"machine-keys filter ({relative_path}): {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

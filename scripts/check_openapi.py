"""Every OpenAPI document the examples print, through the official validator, for all three versions.

    pip install openapi-spec-validator
    python scripts/check_openapi.py
"""
import json
import pathlib
import subprocess
import sys

from openapi_spec_validator import OpenAPIV2SpecValidator, OpenAPIV30SpecValidator, OpenAPIV31SpecValidator

ROOT = pathlib.Path(__file__).resolve().parent.parent
VALIDATORS = {"2.0": OpenAPIV2SpecValidator, "3.0": OpenAPIV30SpecValidator, "3.1": OpenAPIV31SpecValidator}


def documents(text):
    dec = json.JSONDecoder()
    at = text.find("{")
    while at >= 0:
        try:
            doc, end = dec.raw_decode(text, at)
        except json.JSONDecodeError:
            at = text.find("{", at + 1)
            continue
        yield doc
        at = text.find("{", end)


def validator(doc):
    version = doc.get("swagger") or str(doc.get("openapi", ""))[:3]
    make = VALIDATORS.get(version)
    return (make(doc), version) if make else (None, None)


seen = set()
bad = 0
for d in sorted((ROOT / "src/examples").iterdir()):
    pkg = d / "moon.pkg"
    if not pkg.exists() or 'kind: "executable"' not in pkg.read_text(encoding="utf-8"):
        continue
    if not any("openapi" in p.read_text(encoding="utf-8") for p in d.glob("*.mbt")):
        continue
    out = subprocess.run(["moon", "run", f"src/examples/{d.name}", "--target", "native"], cwd=ROOT, capture_output=True,
                         text=True, encoding="utf-8", errors="replace", timeout=300, check=True).stdout
    for doc in documents(out):
        check, version = validator(doc)
        if check is None:
            continue
        seen.add(version)
        errors = list(check.iter_errors())
        print(f"{d.name} {version}: {len(errors)} errors")
        for e in errors:
            bad += 1
            print(f"  {'/'.join(map(str, e.absolute_path))}: {e.message[:200]}")
assert seen == set(VALIDATORS), f"no document for a version: {seen}"
sys.exit(1 if bad else 0)

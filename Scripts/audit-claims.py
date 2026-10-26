#!/usr/bin/env python3
"""
audit-claims.py
Automated documentation, metadata, and architectural claims linter for Mac Screen Record.
Enforces parity across Info.plist, entitlements, Swift sources, SBOM, and markdown docs.
"""

from pathlib import Path
import json
import plistlib
import re
import sys


def fail(errors: list[str], msg: str) -> None:
    errors.append(msg)


def read_text_checked(root: Path, rel_path: str, errors: list[str]) -> str | None:
    target = root / rel_path
    if not target.is_file():
        fail(errors, f"Missing required file: {rel_path}")
        return None
    try:
        return target.read_text(encoding="utf-8")
    except OSError as exc:
        fail(errors, f"Could not read {rel_path}: {exc}")
        return None


def load_plist_checked(root: Path, rel_path: str, errors: list[str]) -> dict | None:
    target = root / rel_path
    if not target.is_file():
        fail(errors, f"Missing required plist: {rel_path}")
        return None
    try:
        with target.open("rb") as f:
            data = plistlib.load(f)
        if not isinstance(data, dict):
            fail(errors, f"Plist {rel_path} root is not a dictionary")
            return None
        return data
    except Exception as exc:
        fail(errors, f"Could not parse plist {rel_path}: {exc}")
        return None


def check_version_and_branding_parity(root: Path, errors: list[str]) -> str:
    plist = load_plist_checked(root, "Resources/Info.plist", errors)
    if plist is None:
        return "0.0.0"

    version = str(plist.get("CFBundleShortVersionString", ""))
    bundle_name = str(plist.get("CFBundleName", ""))
    bundle_id = str(plist.get("CFBundleIdentifier", ""))

    if not version:
        fail(errors, "CFBundleShortVersionString is empty in Resources/Info.plist")
    if bundle_name != "Mac Screen Record":
        fail(errors, f"CFBundleName in Info.plist expected 'Mac Screen Record', got '{bundle_name}'")
    if bundle_id != "com.macscreenrecord.app":
        fail(errors, f"CFBundleIdentifier in Info.plist expected 'com.macscreenrecord.app', got '{bundle_id}'")

    release_notes_path = "docs/RELEASE_NOTES.md" if (root / "docs/RELEASE_NOTES.md").is_file() else "RELEASE_NOTES.md"
    release_notes = read_text_checked(root, release_notes_path, errors)
    if release_notes is not None:
        if f"## Mac Screen Record {version}" not in release_notes:
            fail(errors, f"{release_notes_path} missing heading '## Mac Screen Record {version}'")
        if f"`v{version}`" not in release_notes:
            fail(errors, f"{release_notes_path} missing version tag '`v{version}`'")

    roadmap_path = "docs/ROADMAP.md" if (root / "docs/ROADMAP.md").is_file() else "ROADMAP.md"
    roadmap = read_text_checked(root, roadmap_path, errors)
    if roadmap is not None:
        if f"(v0.1.0 – v{version})" not in roadmap:
            fail(errors, f"{roadmap_path} milestone header does not match '(v0.1.0 – v{version})'")
        if f"(v{version})" not in roadmap:
            fail(errors, f"{roadmap_path} missing shipped milestone entry for '(v{version})'")

    build_script = read_text_checked(root, "Scripts/build-app.sh", errors)
    if build_script is not None:
        if 'APP_NAME="Mac Screen Record"' not in build_script:
            fail(errors, "Scripts/build-app.sh APP_NAME does not match 'Mac Screen Record'")
        if 'BUNDLE_ID="com.macscreenrecord.app"' not in build_script:
            fail(errors, "Scripts/build-app.sh BUNDLE_ID does not match 'com.macscreenrecord.app'")

    return version


FORBIDDEN_EGRESS_PATTERNS = [
    (r"\bimport\s+Network\b", "import Network"),
    (r"\bimport\s+CFNetwork\b", "import CFNetwork"),
    (r"\bimport\s+WebKit\b", "import WebKit"),
    (r"#\s*(?:import|include)\s*[<\"](?:CFNetwork|Network|WebKit)/", "#import Network/CFNetwork/WebKit"),
    (r"\bN?S?URLSession\b", "URLSession/NSURLSession"),
    (r"\bNSURLConnection\b", "NSURLConnection"),
    (r"\bNWConnection\b", "NWConnection"),
    (r"\bNWListener\b", "NWListener"),
    (r"\bnw_(?:connection|listener|endpoint|parameters)_\w*\b", "Network.framework C API (nw_*)"),
    (r"\bCF(?:StreamCreatePairWithSocket|ReadStreamCreateForHTTPRequest|HostCreateWithName)\w*\b", "CFNetwork stream/socket API"),
    (r"\bWKWebView\b", "WKWebView"),
    (r"\bsocket\s*\(", "BSD socket(...)"),
    (r"(?<!\.)\b(?:Darwin\.)?connect\s*\(", "BSD connect(...)"),
    (r"\bsockaddr_in6?\b", "sockaddr_in/sockaddr_in6"),
    (r"\bCFSocket\w*\b", "CFSocket"),
    (r"sys/socket\.h", "sys/socket.h"),
    (r"\bgetaddrinfo\s*\(", "getaddrinfo(...)"),
]


def scan_source_for_egress(content: str) -> list[str]:
    matched_labels: list[str] = []
    for pattern, label in FORBIDDEN_EGRESS_PATTERNS:
        if re.search(pattern, content):
            matched_labels.append(label)
    return matched_labels


def check_zero_egress_and_dependencies(root: Path, errors: list[str]) -> None:
    package_swift = read_text_checked(root, "Package.swift", errors)
    if package_swift is not None and re.search(r"\.package\s*\(\s*url\s*:", package_swift):
        fail(errors, "Package.swift contains external remote package dependencies")

    # Self-test fixture: verify scanner catches both high-level frameworks and low-level BSD sockets
    # while ignoring benign Combine-style `.connect()` method calls.
    fixtures = [
        ("import Darwin\nlet fd = socket(AF_INET, SOCK_STREAM, 0)", "BSD socket(...)"),
        ("import Darwin\nlet rc = connect(fd, addr, len)", "BSD connect(...)"),
        ("import Darwin\nlet rc = Darwin.connect(fd, addr, len)", "BSD connect(...)"),
        ("import Foundation\nlet s = URLSession.shared", "URLSession/NSURLSession"),
        ("let s = NSURLSession.shared()", "URLSession/NSURLSession"),
        ("let conn = nw_connection_create(ep, params)", "Network.framework C API (nw_*)"),
        ("#import <CFNetwork/CFNetwork.h>", "#import Network/CFNetwork/WebKit"),
        ("import Network\nlet c = NWConnection(host: h, port: p, using: .tcp)", "import Network"),
    ]
    for sample_code, expected_label in fixtures:
        detected = scan_source_for_egress(sample_code)
        if expected_label not in detected:
            fail(errors, f"Zero-egress scanner self-test failed to reject fixture for '{expected_label}'")

    benign_code = "let cancellable = publisher.makeConnectable().connect()"
    if scan_source_for_egress(benign_code):
        fail(errors, "Zero-egress scanner self-test falsely flagged benign '.connect()' method call")

    source_exts = {".swift", ".c", ".m", ".mm", ".h", ".hpp", ".cpp"}
    for folder_name in ("Sources", "Tests"):
        target_dir = root / folder_name
        if not target_dir.is_dir():
            fail(errors, f"Missing {folder_name}/ directory")
            continue
        for src_file in sorted(target_dir.rglob("*")):
            if not src_file.is_file() or src_file.suffix not in source_exts:
                continue
            rel_path = str(src_file.relative_to(root))
            content = read_text_checked(root, rel_path, errors)
            if content is None:
                continue
            for label in scan_source_for_egress(content):
                fail(errors, f"Forbidden network/web symbol '{label}' found in {rel_path}")

    ci_workflow = read_text_checked(root, ".github/workflows/ci.yml", errors)
    if ci_workflow is not None:
        if "audit-claims.py" not in ci_workflow:
            fail(errors, ".github/workflows/ci.yml does not execute Scripts/audit-claims.py")
        if "MacScreenRecordTests" not in ci_workflow:
            fail(errors, ".github/workflows/ci.yml does not execute MacScreenRecordTests unit test suite")


def check_hotkey_and_secure_input_parity(root: Path, errors: list[str]) -> None:
    hotkeys_swift = read_text_checked(root, "Sources/RecorderUI/GlobalHotkeys.swift", errors)
    if hotkeys_swift is not None:
        if "cmdKey | optionKey | controlKey" not in hotkeys_swift:
            fail(errors, "GlobalHotkeys.swift does not declare hyper modifiers 'cmdKey | optionKey | controlKey'")
        if "keyCode: kVK_ANSI_R" not in hotkeys_swift or "keyCode: kVK_ANSI_S" not in hotkeys_swift:
            fail(errors, "GlobalHotkeys.swift missing expected kVK_ANSI_R or kVK_ANSI_S bindings")

    roadmap_path = "docs/ROADMAP.md" if (root / "docs/ROADMAP.md").is_file() else "ROADMAP.md"
    for doc_name in ("README.md", roadmap_path):
        doc_text = read_text_checked(root, doc_name, errors)
        if doc_text is None:
            continue
        if "⌃⌥⌘R" not in doc_text or "⌃⌥⌘S" not in doc_text:
            fail(errors, f"{doc_name} missing documented hyper shortcuts '⌃⌥⌘R' and '⌃⌥⌘S'")
        if "⌘⇧R" in doc_text or "⌘⇧S" in doc_text:
            fail(errors, f"{doc_name} contains stale legacy shortcut '⌘⇧R' or '⌘⇧S'")

    keystroke_swift = read_text_checked(root, "Sources/RecorderUI/KeystrokeOverlay.swift", errors)
    if keystroke_swift is not None and "IsSecureEventInputEnabled()" not in keystroke_swift:
        fail(errors, "KeystrokeOverlay.swift does not call IsSecureEventInputEnabled() as claimed in NOTICE.md")


def check_entitlements_and_tcc_justifications(root: Path, errors: list[str]) -> None:
    info_plist = load_plist_checked(root, "Resources/Info.plist", errors)
    entitlements = load_plist_checked(root, "Resources/MacScreenRecord.entitlements", errors)
    notice_text = read_text_checked(root, "NOTICE.md", errors)
    if info_plist is None or entitlements is None or notice_text is None:
        return

    tcc_keys = [k for k in info_plist.keys() if k.startswith("NS") and k.endswith("UsageDescription")]
    if not tcc_keys:
        fail(errors, "No NS*UsageDescription keys found in Resources/Info.plist")

    def has_table_justification(key: str) -> bool:
        pattern = rf"^\|\s*`{re.escape(key)}`\s*\|[^|]+\|\s*(\S[^|]*)\|"
        return re.search(pattern, notice_text, flags=re.MULTILINE) is not None

    for key in tcc_keys:
        if not has_table_justification(key):
            fail(errors, f"Info.plist TCC key '{key}' lacks a non-empty table justification in NOTICE.md")

    for ent_key in entitlements.keys():
        if not has_table_justification(ent_key):
            fail(errors, f"Entitlement '{ent_key}' in MacScreenRecord.entitlements lacks a non-empty table justification in NOTICE.md")


def check_sbom_and_privacy_claims(root: Path, version: str, errors: list[str]) -> None:
    claims_swift = read_text_checked(root, "Sources/RecorderUI/PrivacyClaims.swift", errors)
    expected_claims = {
        'networkEgressPolicy: String = "deny"': ("knowthankyew:privacy:network_egress", "deny"),
        'telemetryMode: String = "disabled"': ("knowthankyew:privacy:telemetry_mode", "disabled"),
        "thirdPartyDependenciesCount: Int = 0": ("knowthankyew:privacy:third_party_dependencies", "0"),
        "externalCloudUpload: Bool = false": ("knowthankyew:privacy:cloud_upload", "false"),
    }

    if claims_swift is not None:
        for swift_sig in expected_claims:
            if swift_sig not in claims_swift:
                fail(errors, f"PrivacyClaims.swift missing expected default '{swift_sig}'")

    sbom_script = read_text_checked(root, "Scripts/generate-sbom.py", errors)
    if sbom_script is not None and '"$schema": "http://cyclonedx.org/schema/bom-1.5.schema.json"' not in sbom_script:
        fail(errors, "Scripts/generate-sbom.py missing canonical CycloneDX 1.5 schema URI")

    candidate_boms = [
        "bom.json",
        "dist/Mac Screen Record.app/Contents/Resources/bom.json",
        "dist/bom.json",
    ]
    for rel_bom in candidate_boms:
        bom_path = root / rel_bom
        if not bom_path.is_file():
            continue
        bom_text = read_text_checked(root, rel_bom, errors)
        if bom_text is None:
            continue
        try:
            bom = json.loads(bom_text)
        except json.JSONDecodeError as exc:
            fail(errors, f"{rel_bom} is not valid JSON: {exc}")
            continue

        if bom.get("$schema") != "http://cyclonedx.org/schema/bom-1.5.schema.json":
            fail(errors, f"{rel_bom} has invalid $schema: {bom.get('$schema')}")
        if bom.get("specVersion") != "1.5":
            fail(errors, f"{rel_bom} specVersion expected '1.5', got '{bom.get('specVersion')}'")

        comp = bom.get("metadata", {}).get("component", {})
        if comp.get("version") != version:
            fail(errors, f"{rel_bom} component version '{comp.get('version')}' != Info.plist '{version}'")

        props = {p.get("name"): p.get("value") for p in comp.get("properties", [])}
        for _, (prop_name, prop_val) in expected_claims.items():
            if props.get(prop_name) != prop_val:
                fail(errors, f"{rel_bom} property '{prop_name}' expected '{prop_val}', got '{props.get(prop_name)}'")


PROHIBITED_WORDS = [
    re.compile(r"\bbullet-?proof\b", re.IGNORECASE),
    re.compile(r"\brock\s+solid\b", re.IGNORECASE),
    re.compile(r"\bconclusive\b", re.IGNORECASE),
    re.compile(r"\bdefinitive\b", re.IGNORECASE),
    re.compile(r"\binfinitely scalable\b", re.IGNORECASE),
]


def check_vocabulary_guardrails(root: Path, errors: list[str]) -> None:
    docs_to_scan = [
        "README.md",
        "ROADMAP.md",
        "RELEASE_NOTES.md",
    ]
    docs_dir = root / "docs"
    if docs_dir.is_dir():
        docs_to_scan.extend([str(f.relative_to(root)) for f in sorted(docs_dir.glob("*.md"))])
    for rel_path in docs_to_scan:
        target = root / rel_path
        if not target.is_file():
            continue
        text = read_text_checked(root, rel_path, errors)
        if text is None:
            continue
        for idx, line in enumerate(text.splitlines(), 1):
            lower = line.lower()
            if "prohibit" in lower or "forbidden" in lower or "guardrail" in lower:
                continue
            for pattern in PROHIBITED_WORDS:
                if pattern.search(line):
                    fail(
                        errors,
                        f"Vocabulary violation in {rel_path}:{idx}: "
                        f"Prohibited term matching '{pattern.pattern}' found: '{line.strip()}'",
                    )


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    errors: list[str] = []

    version = check_version_and_branding_parity(root, errors)
    check_zero_egress_and_dependencies(root, errors)
    check_hotkey_and_secure_input_parity(root, errors)
    check_entitlements_and_tcc_justifications(root, errors)
    check_sbom_and_privacy_claims(root, version, errors)
    check_vocabulary_guardrails(root, errors)

    if errors:
        print("✗ Claims Audit FAILED with the following violations:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print(f"✓ Claims Audit passed (v{version}: version parity, zero-egress, hotkeys, secure-input, entitlements, SBOM).")
    return 0


if __name__ == "__main__":
    sys.exit(main())

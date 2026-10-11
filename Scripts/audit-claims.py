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


def check_version_and_branding_parity(root: Path, errors: list[str]) -> str:
    info_plist_path = root / "Resources" / "Info.plist"
    if not info_plist_path.is_file():
        fail(errors, "Missing Resources/Info.plist")
        return "0.0.0"

    with info_plist_path.open("rb") as f:
        plist = plistlib.load(f)

    version = plist.get("CFBundleShortVersionString", "")
    bundle_name = plist.get("CFBundleName", "")
    bundle_id = plist.get("CFBundleIdentifier", "")

    if not version:
        fail(errors, "CFBundleShortVersionString is empty in Resources/Info.plist")
    if bundle_name != "Mac Screen Record":
        fail(errors, f"CFBundleName in Info.plist expected 'Mac Screen Record', got '{bundle_name}'")
    if bundle_id != "com.macscreenrecord.app":
        fail(errors, f"CFBundleIdentifier in Info.plist expected 'com.macscreenrecord.app', got '{bundle_id}'")

    release_notes = (root / "RELEASE_NOTES.md").read_text(encoding="utf-8")
    if f"## Mac Screen Record {version}" not in release_notes:
        fail(errors, f"RELEASE_NOTES.md missing heading '## Mac Screen Record {version}'")
    if f"`v{version}`" not in release_notes:
        fail(errors, f"RELEASE_NOTES.md missing version tag '`v{version}`'")

    roadmap = (root / "ROADMAP.md").read_text(encoding="utf-8")
    if f"(v0.1.0 – v{version})" not in roadmap:
        fail(errors, f"ROADMAP.md milestone header does not match '(v0.1.0 – v{version})'")
    if f"(v{version})" not in roadmap:
        fail(errors, f"ROADMAP.md missing shipped milestone entry for '(v{version})'")

    sbom_script = (root / "Scripts" / "generate-sbom.py").read_text(encoding="utf-8")
    if f'version: str = "{version}"' not in sbom_script:
        fail(errors, f"Scripts/generate-sbom.py default version does not match '{version}'")

    build_script = (root / "Scripts" / "build-app.sh").read_text(encoding="utf-8")
    if f'echo "{version}"' not in build_script:
        fail(errors, f"Scripts/build-app.sh fallback version does not match '{version}'")
    if 'APP_NAME="Mac Screen Record"' not in build_script:
        fail(errors, "Scripts/build-app.sh APP_NAME does not match 'Mac Screen Record'")
    if 'BUNDLE_ID="com.macscreenrecord.app"' not in build_script:
        fail(errors, "Scripts/build-app.sh BUNDLE_ID does not match 'com.macscreenrecord.app'")

    return version


FORBIDDEN_EGRESS_PATTERNS = [
    (r"\bimport\s+Network\b", "import Network"),
    (r"\bimport\s+CFNetwork\b", "import CFNetwork"),
    (r"\bimport\s+WebKit\b", "import WebKit"),
    (r"\bURLSession\b", "URLSession"),
    (r"\bNSURLConnection\b", "NSURLConnection"),
    (r"\bNWConnection\b", "NWConnection"),
    (r"\bNWListener\b", "NWListener"),
    (r"\bWKWebView\b", "WKWebView"),
    (r"\bsocket\s*\(", "BSD socket(...)"),
    (r"\bconnect\s*\(", "BSD connect(...)"),
    (r"\bsockaddr_in6?\b", "sockaddr_in/sockaddr_in6"),
    (r"\bCFSocket\w*\b", "CFSocket"),
    (r"sys/socket\.h", "sys/socket.h"),
    (r"\bgetaddrinfo\s*\(", "getaddrinfo(...)"),
]


def scan_swift_source_for_egress(content: str) -> list[str]:
    matched_labels: list[str] = []
    for pattern, label in FORBIDDEN_EGRESS_PATTERNS:
        if re.search(pattern, content):
            matched_labels.append(label)
    return matched_labels


def check_zero_egress_and_dependencies(root: Path, errors: list[str]) -> None:
    package_swift = (root / "Package.swift").read_text(encoding="utf-8")
    if re.search(r"\.package\s*\(\s*url\s*:", package_swift):
        fail(errors, "Package.swift contains external remote package dependencies")

    # Self-test fixture: verify scanner catches both high-level frameworks and low-level BSD sockets
    fixtures = [
        ("import Darwin\nlet fd = socket(AF_INET, SOCK_STREAM, 0)", "BSD socket(...)"),
        ("import Darwin\nlet rc = connect(fd, addr, len)", "BSD connect(...)"),
        ("import Foundation\nlet s = URLSession.shared", "URLSession"),
        ("import Network\nlet c = NWConnection(host: h, port: p, using: .tcp)", "import Network"),
    ]
    for sample_code, expected_label in fixtures:
        detected = scan_swift_source_for_egress(sample_code)
        if expected_label not in detected:
            fail(errors, f"Zero-egress scanner self-test failed to reject fixture for '{expected_label}'")

    sources_dir = root / "Sources"
    for swift_file in sorted(sources_dir.rglob("*.swift")):
        content = swift_file.read_text(encoding="utf-8")
        rel_path = swift_file.relative_to(root)
        for label in scan_swift_source_for_egress(content):
            fail(errors, f"Forbidden network/web symbol '{label}' found in {rel_path}")


def check_hotkey_parity(root: Path, errors: list[str]) -> None:
    hotkeys_swift = (root / "Sources" / "RecorderUI" / "GlobalHotkeys.swift").read_text(encoding="utf-8")
    if "cmdKey | optionKey | controlKey" not in hotkeys_swift:
        fail(errors, "GlobalHotkeys.swift does not declare hyper modifiers 'cmdKey | optionKey | controlKey'")
    if "keyCode: kVK_ANSI_R" not in hotkeys_swift or "keyCode: kVK_ANSI_S" not in hotkeys_swift:
        fail(errors, "GlobalHotkeys.swift missing expected kVK_ANSI_R or kVK_ANSI_S bindings")

    for doc_name in ("README.md", "ROADMAP.md"):
        doc_text = (root / doc_name).read_text(encoding="utf-8")
        if "⌃⌥⌘R" not in doc_text or "⌃⌥⌘S" not in doc_text:
            fail(errors, f"{doc_name} missing documented hyper shortcuts '⌃⌥⌘R' and '⌃⌥⌘S'")
        if "⌘⇧R" in doc_text or "⌘⇧S" in doc_text:
            fail(errors, f"{doc_name} contains stale legacy shortcut '⌘⇧R' or '⌘⇧S'")


def check_entitlements_and_tcc_justifications(root: Path, errors: list[str]) -> None:
    info_plist_path = root / "Resources" / "Info.plist"
    entitlements_path = root / "Resources" / "MacScreenRecord.entitlements"
    notice_text = (root / "NOTICE.md").read_text(encoding="utf-8")

    with info_plist_path.open("rb") as f:
        info_plist = plistlib.load(f)
    with entitlements_path.open("rb") as f:
        entitlements = plistlib.load(f)

    tcc_keys = [k for k in info_plist.keys() if k.startswith("NS") and k.endswith("UsageDescription")]
    if not tcc_keys:
        fail(errors, "No NS*UsageDescription keys found in Resources/Info.plist")

    for key in tcc_keys:
        if f"`{key}`" not in notice_text:
            fail(errors, f"Info.plist TCC key '{key}' lacks a documented justification in NOTICE.md")

    for ent_key in entitlements.keys():
        if f"`{ent_key}`" not in notice_text:
            fail(errors, f"Entitlement '{ent_key}' in MacScreenRecord.entitlements lacks a documented justification in NOTICE.md")


def check_sbom_and_privacy_claims(root: Path, version: str, errors: list[str]) -> None:
    claims_swift = (root / "Sources" / "RecorderUI" / "PrivacyClaims.swift").read_text(encoding="utf-8")
    expected_claims = {
        'networkEgressPolicy: String = "deny"': ("knowthankyew:privacy:network_egress", "deny"),
        'telemetryMode: String = "disabled"': ("knowthankyew:privacy:telemetry_mode", "disabled"),
        "thirdPartyDependenciesCount: Int = 0": ("knowthankyew:privacy:third_party_dependencies", "0"),
        "externalCloudUpload: Bool = false": ("knowthankyew:privacy:cloud_upload", "false"),
    }

    for swift_sig in expected_claims:
        if swift_sig not in claims_swift:
            fail(errors, f"PrivacyClaims.swift missing expected default '{swift_sig}'")

    sbom_script = (root / "Scripts" / "generate-sbom.py").read_text(encoding="utf-8")
    if '"$schema": "http://cyclonedx.org/schema/bom-1.5.schema.json"' not in sbom_script:
        fail(errors, "Scripts/generate-sbom.py missing canonical CycloneDX 1.5 schema URI")

    bom_path = root / "dist" / "bom.json"
    if bom_path.is_file():
        try:
            bom = json.loads(bom_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            fail(errors, f"dist/bom.json is not valid JSON: {exc}")
            return

        if bom.get("$schema") != "http://cyclonedx.org/schema/bom-1.5.schema.json":
            fail(errors, f"dist/bom.json has invalid $schema: {bom.get('$schema')}")
        if bom.get("specVersion") != "1.5":
            fail(errors, f"dist/bom.json specVersion expected '1.5', got '{bom.get('specVersion')}'")

        comp = bom.get("metadata", {}).get("component", {})
        if comp.get("version") != version:
            fail(errors, f"dist/bom.json component version '{comp.get('version')}' != Info.plist '{version}'")

        props = {p.get("name"): p.get("value") for p in comp.get("properties", [])}
        for _, (prop_name, prop_val) in expected_claims.items():
            if props.get(prop_name) != prop_val:
                fail(errors, f"dist/bom.json property '{prop_name}' expected '{prop_val}', got '{props.get(prop_name)}'")


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    errors: list[str] = []

    version = check_version_and_branding_parity(root, errors)
    check_zero_egress_and_dependencies(root, errors)
    check_hotkey_parity(root, errors)
    check_entitlements_and_tcc_justifications(root, errors)
    check_sbom_and_privacy_claims(root, version, errors)

    if errors:
        print("✗ Claims Audit FAILED with the following violations:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print(f"✓ Claims Audit passed (v{version}: version parity, zero-egress, hotkeys, entitlements, SBOM).")
    return 0


if __name__ == "__main__":
    sys.exit(main())

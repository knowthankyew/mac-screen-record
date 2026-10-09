#!/usr/bin/env python3
"""
generate-sbom.py
Generates a valid CycloneDX v1.5 JSON Software Bill of Materials (SBOM) for Mac Screen Record.
Documents application metadata, Swift package modules, and knowthankyew zero-egress properties.
"""

import json
import os
import sys
import uuid
from datetime import datetime, timezone

def generate_sbom(output_path: str, arch: str = "arm64", version: str = "0.3.0"):
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    ts = datetime.fromtimestamp(int(epoch), timezone.utc) if epoch else datetime.now(timezone.utc)
    now_iso = ts.strftime("%Y-%m-%dT%H:%M:%SZ")
    serial_uuid = f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, f'mac-screen-record/{version}/{arch}')}"
    app_ref = f"pkg:generic/mac-screen-record@{version}?arch={arch}"

    sbom = {
        "$schema": "http://cyclonedx.org/schema/bom-1.5.json",
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": serial_uuid,
        "version": 1,
        "metadata": {
            "timestamp": now_iso,
            "tools": [
                {
                    "vendor": "knowthankyew",
                    "name": "generate-sbom",
                    "version": "1.0.0"
                }
            ],
            "component": {
                "type": "application",
                "bom-ref": app_ref,
                "name": "Mac Screen Record",
                "version": version,
                "description": "Privacy-first, native macOS screen recorder built on ScreenCaptureKit and VideoToolbox with zero egress. Hard fork of free-mac-screen-recorder.",
                "licenses": [
                    {
                        "license": {
                            "id": "MIT"
                        }
                    }
                ],
                "properties": [
                    {
                        "name": "knowthankyew:privacy:network_egress",
                        "value": "deny"
                    },
                    {
                        "name": "knowthankyew:privacy:telemetry_mode",
                        "value": "disabled"
                    },
                    {
                        "name": "knowthankyew:privacy:cloud_upload",
                        "value": "false"
                    },
                    {
                        "name": "knowthankyew:privacy:third_party_dependencies",
                        "value": "0"
                    },
                    {
                        "name": "knowthankyew:security:secure_input_guard",
                        "value": "active"
                    }
                ]
            }
        },
        "components": [
            {
                "type": "library",
                "bom-ref": f"pkg:swift/MacScreenRecord/CaptureCore@{version}",
                "name": "CaptureCore",
                "version": version,
                "scope": "required",
                "description": "ScreenCaptureKit wrapper for display, window, app, and audio capture"
            },
            {
                "type": "library",
                "bom-ref": f"pkg:swift/MacScreenRecord/DeviceKit@{version}",
                "name": "DeviceKit",
                "version": version,
                "scope": "required",
                "description": "AVCaptureDevice enumeration and hot-swap monitoring"
            },
            {
                "type": "library",
                "bom-ref": f"pkg:swift/MacScreenRecord/EncoderKit@{version}",
                "name": "EncoderKit",
                "version": version,
                "scope": "required",
                "description": "AVAssetWriter, VideoToolbox hardware-accelerated encoder, and GIF exporter"
            },
            {
                "type": "library",
                "bom-ref": f"pkg:swift/MacScreenRecord/RecorderUI@{version}",
                "name": "RecorderUI",
                "version": version,
                "scope": "required",
                "description": "SwiftUI recorder views, overlays, controls, settings, and PrivacyClaimsProvider"
            }
        ],
        "dependencies": [
            {
                "ref": app_ref,
                "dependsOn": [
                    f"pkg:swift/MacScreenRecord/CaptureCore@{version}",
                    f"pkg:swift/MacScreenRecord/DeviceKit@{version}",
                    f"pkg:swift/MacScreenRecord/EncoderKit@{version}",
                    f"pkg:swift/MacScreenRecord/RecorderUI@{version}"
                ]
            },
            {
                "ref": f"pkg:swift/MacScreenRecord/CaptureCore@{version}",
                "dependsOn": [
                    f"pkg:swift/MacScreenRecord/EncoderKit@{version}"
                ]
            },
            {
                "ref": f"pkg:swift/MacScreenRecord/RecorderUI@{version}",
                "dependsOn": [
                    f"pkg:swift/MacScreenRecord/CaptureCore@{version}",
                    f"pkg:swift/MacScreenRecord/DeviceKit@{version}",
                    f"pkg:swift/MacScreenRecord/EncoderKit@{version}"
                ]
            }
        ]
    }

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(sbom, f, indent=2)
    print(f"✓ CycloneDX SBOM written to {output_path}")

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "dist/bom.json"
    arch = sys.argv[2] if len(sys.argv) > 2 else "arm64"
    ver = sys.argv[3] if len(sys.argv) > 3 else "0.3.0"
    generate_sbom(out, arch, ver)

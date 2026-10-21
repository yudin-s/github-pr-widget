import json
import sys
from pathlib import Path

app = Path(sys.argv[1])
targets = {
    app: {"RefreshPRIntent"},
    app / "Contents/PlugIns/PRWidget.appex": {"RefreshPRIntent", "ShowPRPageIntent", "HidePRIntent", "ReadPRIntent"},
}
for bundle, expected in targets.items():
    file = bundle / "Contents/Resources/Metadata.appintents/extract.actionsdata"
    if not file.is_file():
        sys.exit(f"Missing App Intents metadata: {file}. Build with full Xcode before testing widget buttons.")
    actions = json.loads(file.read_text()).get("actions", {})
    missing = expected - {key.rsplit(".", 1)[-1] for key in actions}
    if missing:
        sys.exit(f"Missing actions in {file}: {sorted(missing)}")
print("App and widget intent metadata present. Runtime button verification is still required.")

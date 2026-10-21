import sys
from pathlib import Path

app = Path(sys.argv[1])
config = Path(__file__).resolve().parent.parent / "Config"
for destination, source in [(app / "Contents/Info.plist", "AppInfo.plist"),
                            (app / "Contents/PlugIns/PRWidget.appex/Contents/Info.plist", "WidgetInfo.plist")]:
    destination.write_bytes((config / source).read_bytes())

#!/usr/bin/env python3
"""Write realistic sample data into the app's Documents folder.

Usage: tool/seed_demo_data.py <Documents dir>
For the simulator:
  tool/seed_demo_data.py "$(xcrun simctl get_app_container booted jp.dezura.app data)/Documents"
Only for store screenshots. The app never ships with this data.
"""
import datetime as dt
import json
import os
import sys

docs = sys.argv[1]
root = os.path.join(docs, "dezura_nittou")
os.makedirs(os.path.join(root, "exports"), exist_ok=True)
today = dt.date.today()
created = int(dt.datetime(today.year, today.month, 1).timestamp() * 1000) - 86400000 * 40

workers = [
    ("w1", "鈴木 隼人", 20000, 2800),
    ("w2", "山田 太郎", 18000, 2500),
    ("w3", "佐藤 健", 16000, 2200),
    ("w4", "高橋 翔", 13000, 1800),
]
sites = [
    ("s1", "港北倉庫改修", "〇〇建設"),
    ("s2", "南区マンション内装", "△△工務店"),
    ("s3", "緑町 戸建て外構", "直請け"),
]
rates = {w[0]: (w[2], w[3]) for w in workers}

# (worker, site, units, overtime) per weekday pattern, by day index
patterns = [
    [("w1", "s1", 1, 0), ("w2", "s1", 1, 0), ("w3", "s1", 1, 0), ("w4", "s1", 1, 0)],
    [("w1", "s1", 1, 2), ("w2", "s1", 1, 2), ("w3", "s2", 1, 0), ("w4", "s1", 1, 0)],
    [("w1", "s3", 0.5, 0), ("w2", "s3", 0.5, 0)],
    [("w1", "s1", 1, 0), ("w2", "s1", 1, 1), ("w3", "s2", 1, 0), ("w4", "s2", 1, 0)],
    [("w1", "s2", 1, 0), ("w2", "s1", 1, 0), ("w3", "s2", 1, 1.5), ("w4", "s2", 0.5, 0)],
    [("w1", "s1", 1, 1), ("w2", "s1", 1, 1), ("w3", "s1", 1, 0)],
]

records = []
i = 0
for day in range(1, today.day + 1):
    date = dt.date(today.year, today.month, day)
    if date.weekday() == 6:  # Sunday off
        continue
    if date == today:
        # Today: entered so far this morning.
        rows = [("w1", "s1", 1, 0), ("w2", "s1", 1, 0), ("w3", "s1", 0.5, 0)]
    elif date.weekday() == 5:
        rows = patterns[2]
    else:
        rows = patterns[[0, 1, 3, 4, 5][i % 5]]
        i += 1
    for w, s, u, ot in rows:
        rate, otr = rates[w]
        records.append({
            "workerId": w, "day": date.isoformat(), "siteId": s,
            "units": u, "overtimeHours": ot, "dayRate": rate, "overtimeRate": otr,
        })

def write(name, obj):
    with open(os.path.join(root, name), "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)

write("workers.json", {"version": 1, "workers": [
    {"id": w, "name": n, "dayRate": r, "overtimeRate": o, "createdAt": created}
    for w, n, r, o in workers]})
write("sites.json", {"version": 1, "sites": [
    {"id": s, "name": n, "note": note, "createdAt": created} for s, n, note in sites]})
write("records.json", {"version": 1, "records": records})
write("settings.json", {"version": 1, "selectedSiteId": "s1", "businessName": "鈴木工業"})
write("entitlement.json", {"version": 1})
print(f"wrote {len(records)} records to {root}")

#!/usr/bin/env python3
"""1.0.6 sample data (saved-data v3): same-day entries and a 外注 with 3人工.

Usage: tool/seed_demo_data_v3.py <Documents dir>
Only for screenshots. The app never ships with this data.
"""
import datetime as dt
import json
import os
import sys

root = os.path.join(sys.argv[1], "dezura_nittou")
os.makedirs(os.path.join(root, "exports"), exist_ok=True)
today = dt.date.today()
created = int(dt.datetime(today.year, today.month, 1).timestamp() * 1000) - 86400000 * 40

workers = [
    ("w1", "山田 太郎", "employee", 20000, 2800),
    ("w2", "田中 一郎", "employee", 18000, 2500),
    ("w3", "山田工業", "contractor", 25000, 0),
]
sites = [("s1", "港北倉庫改修", "〇〇建設"), ("s2", "南区マンション内装", "△△工務店")]
rates = {w[0]: (w[3], w[4]) for w in workers}
records = []


def add(w, day, site, units, ot=0, shift="day"):
    rate, otr = rates[w]
    records.append({
        "id": f"{w}-{day}-{site}-{shift}", "shift": shift, "workerId": w, "day": day,
        "siteId": site, "payType": "daily", "units": units, "hours": 0, "overtimeHours": ot,
        "dayRate": rate, "hourlyRate": 0, "monthlySalary": 0, "overtimeRate": otr,
    })


for d in range(1, today.day + 1):
    date = dt.date(today.year, today.month, d)
    if date.weekday() == 6:
        continue
    k = date.isoformat()
    if date == today:
        add("w1", k, "s1", 0.5)
        add("w1", k, "s2", 0.5)
        add("w2", k, "s1", 1)
        add("w2", k, "s1", 1, 1, "night")
        add("w3", k, "s1", 3)
        continue
    add("w1", k, "s1", 1, 2 if d % 3 == 0 else 0)
    if d % 2 == 0:
        add("w2", k, "s2", 1)
    if d % 4 == 1:
        add("w1", k, "s2", 1, 0, "night")
    if d % 3 == 1:
        add("w3", k, "s1", 3 if d % 2 else 2.5)


def write(name, obj):
    with open(os.path.join(root, name), "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)


if os.environ.get("REVERSE_WORKERS"):
    workers.reverse()  # screenshots: show the 外注 tile first
write("workers.json", {"version": 3, "workers": [
    {"id": w, "name": n, "kind": kind, "payType": "daily", "dayRate": r, "hourlyRate": 0,
     "monthlySalary": 0, "overtimeRate": o, "createdAt": created}
    for w, n, kind, r, o in workers]})
write("sites.json", {"version": 3, "sites": [
    {"id": s, "name": n, "note": note, "createdAt": created} for s, n, note in sites]})
write("records.json", {"version": 3, "records": records})
write("settings.json", {"version": 1, "selectedSiteId": "s1", "businessName": "山田工業"})
write("entitlement.json", {"version": 1})
print(f"wrote {len(records)} records to {root}")

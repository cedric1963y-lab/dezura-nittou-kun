#!/usr/bin/env python3
"""1.0.7 sample data: a 平米 site, 色付け, and a normal 日当 site.

Usage: tool/seed_demo_data_v4.py <Documents dir>
Only for screenshots. The app never ships with this data.
"""
import datetime as dt
import json
import os
import sys

root = os.path.join(sys.argv[1], "dezura_nittou")
os.makedirs(os.path.join(root, "exports"), exist_ok=True)
today = dt.date.today()
month = f"{today.year:04d}-{today.month:02d}"
created = int(dt.datetime(today.year, today.month, 1).timestamp() * 1000) - 86400000 * 40

workers = [
    ("w1", "山田 太郎", "employee", 20000, 2800),
    ("w2", "田中 一郎", "employee", 18000, 2500),
    ("w3", "山田工業", "contractor", 25000, 0),
]
rates = {w[0]: (w[3], w[4]) for w in workers}
records = []


def add(w, day, site, units, ot=0, shift="day", allowance=0, memo=""):
    rate, otr = rates[w]
    records.append({
        "id": f"{w}-{day}-{site}-{shift}",
        "shift": shift,
        "workerId": w,
        "day": day,
        "siteId": site,
        "payType": "daily",
        "units": units,
        "hours": 0,
        "overtimeHours": ot,
        "dayRate": rate,
        "hourlyRate": 0,
        "monthlySalary": 0,
        "overtimeRate": otr,
        "allowance": allowance,
        "allowanceMemo": memo,
    })


for d in range(1, today.day + 1):
    date = dt.date(today.year, today.month, d)
    if date.weekday() == 6:
        continue
    k = date.isoformat()
    if date == today:
        add("w1", k, "s-area", 1)
        add("w2", k, "s-area", 0.5)
        add("w1", k, "s1", 1, 0, "day", 5000, "搬入が大変だった")
        add("w2", k, "s1", 1)
        continue
    # A few 平米 days (no 日当), plus regular 日当 days.
    if d % 3 == 1:
        add("w1", k, "s-area", 1)
        add("w2", k, "s-area", 0.5)
        if d % 6 == 1:
            add("w3", k, "s-area", 2)
    else:
        add("w1", k, "s1", 1, 2 if d % 5 == 0 else 0)
        if d % 2 == 0:
            add("w2", k, "s1", 1)


def write(name, obj):
    with open(os.path.join(root, name), "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)


write("workers.json", {"version": 4, "workers": [
    {"id": w, "name": n, "kind": kind, "payType": "daily", "dayRate": r,
     "hourlyRate": 0, "monthlySalary": 0, "overtimeRate": o, "createdAt": created}
    for w, n, kind, r, o in workers]})
write("sites.json", {"version": 4, "sites": [
    {
        "id": "s-area",
        "name": "川崎物流センター床",
        "note": "〇〇建設",
        "createdAt": created,
        "isAreaSite": True,
        "areaAmountMode": "contract",
        "areaSqm": 120,
        "areaUnitPrice": 3000,
        "contractAmount": 360000,
        "settlementMonth": month,
    },
    {
        "id": "s1",
        "name": "港北倉庫改修",
        "note": "△△工務店",
        "createdAt": created,
        "isAreaSite": False,
        "areaAmountMode": "areaTimesRate",
        "areaSqm": 0,
        "areaUnitPrice": 0,
        "contractAmount": 0,
        "settlementMonth": "",
    },
]})
write("records.json", {"version": 4, "records": records})
write("settings.json", {"version": 1, "selectedSiteId": "s-area", "businessName": "山田工業"})
write("entitlement.json", {"version": 1})
print(f"wrote {len(records)} records to {root}")

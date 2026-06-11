import json

d = json.load(open(r"E:/SplitCode/godot/data/synergies.json", encoding="utf-8"))
syns = d.get("synergies", [])
print("total:", len(syns))
for s in syns:
    tiers = [t.get("count") for t in s.get("tiers", [])]
    print("%-24s tag=%-22s tiers=%s applies=%s" % (
        s.get("id", "?"), s.get("count_tag", "?"), tiers, s.get("applies_to_tags", [])))

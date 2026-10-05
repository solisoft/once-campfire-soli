import json, sys
out = sys.argv[1]
def parse(line):
    return {k: tuple(int(x) for x in v.split("/")) for k, v in (kv.split("=") for kv in line.split())}
idle = parse(open(f"{out}/memory-idle.txt").read())
names = list(idle)
# The sampler is killed when the run ends, possibly mid-line: keep complete samples only.
samples = [s for s in (parse(l) for l in open(f"{out}/memory-samples.txt") if l.strip()) if all(k in s for k in names)]
mib = lambda kb: round(kb / 1024, 1)
fields = ["rss", "anon", "pss"]
summary = {"idle": {k: dict(zip(fields, map(mib, v))) for k, v in idle.items()},
           "peak": {k: dict(zip(fields, (mib(max(s[k][i] for s in samples)) for i in range(3)))) for k in names},
           "idle_total": dict(zip(fields, (mib(sum(v[i] for v in idle.values())) for i in range(3)))),
           "peak_total": dict(zip(fields, (mib(max(sum(v[i] for v in s.values()) for s in samples)) for i in range(3)))),
           "samples": len(samples)}
json.dump(summary, open(f"{out}/memory.json", "w"), indent=2)
t, p = summary["idle_total"], summary["peak_total"]
print(f"memory (MiB): idle total RSS {t['rss']} / anon {t['anon']} / PSS {t['pss']};  peak total RSS {p['rss']} / anon {p['anon']} / PSS {p['pss']}")
for k in names:
    i, q = summary["idle"][k], summary["peak"][k]
    print(f"  {k:8} idle RSS {i['rss']:7.1f} anon {i['anon']:7.1f} PSS {i['pss']:7.1f}   peak RSS {q['rss']:7.1f} anon {q['anon']:7.1f} PSS {q['pss']:7.1f}")

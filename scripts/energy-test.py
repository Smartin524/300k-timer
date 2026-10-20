#!/usr/bin/env python3
"""Sample a running 300k Timer using macOS top; no elevated permissions required."""
import argparse
import csv
import datetime as dt
import json
from pathlib import Path
import statistics
import subprocess
import time


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--duration', type=int, default=300, help='Seconds, default 300')
    parser.add_argument('--interval', type=int, default=5, help='Seconds between samples')
    parser.add_argument('--label', default='current', help='Scenario label; does not change app state')
    args = parser.parse_args()
    if args.interval < 1 or args.duration < args.interval:
        parser.error('duration must be >= interval >= 1')
    pids = run('/usr/bin/pgrep', '-x', '300KTimer').splitlines()
    if len(pids) != 1:
        raise SystemExit('Expected exactly one running 300KTimer process.')
    pid = pids[0]
    stamp = dt.datetime.now().strftime('%Y%m%d-%H%M%S')
    output = Path(__file__).resolve().parents[1] / 'dist' / 'energy-tests' / stamp
    output.mkdir(parents=True, exist_ok=False)
    before = run('/usr/bin/pmset', '-g', 'batt')
    count = args.duration // args.interval
    command = ['/usr/bin/top', '-l', str(count + 1), '-s', str(args.interval),
               '-pid', pid, '-n', '1', '-stats', 'pid,command,cpu,mem,idlew,power']
    started = time.monotonic()
    print(f'Sampling PID {pid} for about {count * args.interval}s → {output}', flush=True)
    result = subprocess.run(command, text=True, capture_output=True,
                            timeout=count * args.interval + 60, check=True)
    (output / 'top.txt').write_text(result.stdout)
    (output / 'battery.txt').write_text('BEFORE\n' + before + '\nAFTER\n' + run('/usr/bin/pmset', '-g', 'batt') + '\n')
    rows = []
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) == 6 and fields[0] == pid:
            rows.append(dict(cpu_percent=float(fields[2]), memory=fields[3],
                             idlew_reported=fields[4], power_score=float(fields[5])))
    # top's first sample does not represent the measured interval.
    rows = rows[1:]
    if len(rows) != count:
        raise SystemExit('Incomplete samples: app may have exited. Raw output saved; no report produced.')
    with (output / 'samples.csv').open('w', newline='') as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    summary = dict(label=args.label, pid=int(pid), samples=len(rows), interval_seconds=args.interval,
                   elapsed_seconds=round(time.monotonic() - started, 1),
                   cpu_average_percent=round(statistics.mean(r['cpu_percent'] for r in rows), 3),
                   cpu_peak_percent=max(r['cpu_percent'] for r in rows),
                   last_memory=rows[-1]['memory'],
                   average_top_power_score=round(statistics.mean(r['power_score'] for r in rows), 3),
                   battery_source_at_start=before,
                   caveat='top POWER is a relative score, not watts. IDLEW is retained as reported by top. Battery readings describe the whole Mac, not this app. Scenario is user-labeled, not automatically verified.')
    (output / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    report = f'''# 300k Timer 开销采样

场景标签：{args.label}（由运行者指定）
采样：{len(rows)} 次，每 {args.interval} 秒一次
CPU 平均：{summary['cpu_average_percent']}%（100% 约为一个逻辑核心）
CPU 峰值：{summary['cpu_peak_percent']}%
末次内存：{summary['last_memory']}
top POWER 平均分值：{summary['average_top_power_score']}

这不是瓦数或电池耗电百分比。IDLEW 原始读数保存在 samples.csv。
整机电池状态保存在 battery.txt；接电或短时采样不能证明 App 不耗电。
对比时应使用相同电源、屏幕亮度与后台负载，分别手动设为暂停、计时且 Chrome 不在前台、计时且 Chrome 前台普通网页，再运行相同采样时长。
'''
    (output / 'report.md').write_text(report)
    print(report)


if __name__ == '__main__':
    try:
        main()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        raise SystemExit(f'Sampling failed: {error}')

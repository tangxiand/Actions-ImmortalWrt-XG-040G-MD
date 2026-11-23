import re, subprocess, tempfile, os, sys

path = r"C:/Users/19755/WorkBuddy/2026-10-17-15-25-32/ponwrt-build/.github/workflows/build.yml"
with open(path, encoding="utf-8") as f:
    lines = f.read().split("\n")

n = len(lines)
idx = 0
current_step_name = None
blocks = []
while idx < n:
    line = lines[idx]
    m = re.match(r'^\s*-\s*name:\s*(.*)$', line)
    if m:
        current_step_name = m.group(1).strip()
        idx += 1
        continue
    m = re.match(r'^(\s*)run:\s*(\||>|-|\+)?\s*(.*)$', line)
    if m:
        indent = len(m.group(1))
        inline = m.group(3)
        if inline == '':
            script_lines = []
            idx += 1
            while idx < n:
                l = lines[idx]
                if l.strip() == '':
                    script_lines.append('')
                    idx += 1
                    continue
                lead = len(l) - len(l.lstrip(' '))
                if lead > indent:
                    script_lines.append(l)
                    idx += 1
                else:
                    break
            script = "\n".join(script_lines)
        else:
            script = inline
            idx += 1
        blocks.append((current_step_name or "?", script))
        continue
    idx += 1

print(f"共解析到 {len(blocks)} 个 run 步骤")
bash_exe = "bash"
problems = 0
for name, script in blocks:
    stubbed = re.sub(r"\$\{\{.*?\}\}", "GITHUB_EXPR", script, flags=re.S)
    with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False, encoding="utf-8") as tf:
        tf.write(stubbed)
        tfname = tf.name
    r = subprocess.run([bash_exe, "-n", tfname], capture_output=True, text=True)
    os.unlink(tfname)
    if r.returncode != 0:
        problems += 1
        print(f"[FAIL] {name}\n{r.stderr}")
    else:
        print(f"[OK]   {name}")
print(f"\n问题数: {problems}")
sys.exit(1 if problems else 0)

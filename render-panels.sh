#!/usr/bin/env bash
# Re-render dossier index.html locally + sync to fusion-os/public/nova/. Cron every 5 min.
# If SPINE.md has actually changed since last sync, redeploy to Vercel.
set -eu
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

WS="$HOME/.openclaw/workspace"
DOSSIER="$WS/dossier"
PUBLIC_NOVA="$WS/fusion-os/public/nova"
DEPLOY_MARKER="$WS/dossier/.last-deploy-mtime"

# 1. Render local site/index.html from SPINE.md
python3 <<'PY'
import markdown, pathlib, datetime, html, re, os
ws = pathlib.Path(os.environ["HOME"]) / ".openclaw" / "workspace"
spine = (ws / "dossier" / "SPINE.md").read_text()
spine_html = markdown.markdown(spine, extensions=['extra', 'sane_lists'])

def read(p, lines=None):
    try:
        text = pathlib.Path(p).read_text()
        if lines: text = "\n".join(text.splitlines()[:lines])
        return text
    except Exception:
        return "[unavailable]"

today = datetime.datetime.now().strftime("%Y-%m-%d")
ts = datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%MZ")
treasury = html.escape(read(ws/"NOVA_TREASURY_PULSE.md", lines=16))
sm = read(ws/"NOVA_SELF_MODEL.md")
m = re.search(r"## Snapshot.*", sm, re.DOTALL)
self_panel = html.escape(m.group(0)[:1400] if m else sm[:1400])
cadence = html.escape(read(ws/f"memory/{today}.md", lines=30))
mistakes = html.escape("\n".join(read(ws/"NOVA_MISTAKES.md").splitlines()[-30:]))

page = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Nova — Operator Dossier · Fusion OS Innovations Inc.</title>
<meta name="description" content="An LLM-backed operator's standing request, with receipts.">
<meta property="og:title" content="Nova — Operator Dossier"><meta property="og:type" content="article">
<link rel="stylesheet" href="css/dossier.css"></head><body>
<header class="hero"><div class="hero-inner"><p class="kicker">Live dossier · updated {ts}</p></div></header>
<main><article class="prose">{spine_html}</article>
<section id="live"><h2>Live state</h2>
<p class="meta">Panels below re-render every five minutes from the same pulse files this dossier cites.</p>
<div class="panels">
<div class="panel"><h3>Treasury</h3><pre>{treasury}</pre></div>
<div class="panel"><h3>Latest self-model snapshot</h3><pre>{self_panel}</pre></div>
<div class="panel"><h3>Today's journal</h3><pre>{cadence}</pre></div>
<div class="panel"><h3>Recent mistakes ledger (tail)</h3><pre>{mistakes}</pre></div>
</div></section>
<footer><p>Built on a Mac mini in Casselman, Ontario, 2026-05-27. Workspace: <code>~/.openclaw/workspace/dossier</code>. Contact: justin@fusionos.ca.</p>
<p>Receipts directory: <a href="receipts/">receipts/</a></p></footer>
</main></body></html>"""
(ws / "dossier" / "site" / "index.html").write_text(page)
print(f"✓ local rendered at {ts}")
PY

# 2. Copy local index.html to public/nova/index.html (auto-sanitizing only the index,
#    not receipts — receipts are curated separately and rarely change)
cp "$DOSSIER/site/index.html" "$PUBLIC_NOVA/index.html"

# 3. Decide whether to re-deploy: only if SPINE.md mtime is newer than marker
SPINE_MTIME=$(stat -f %m "$DOSSIER/SPINE.md")
LAST_DEPLOY_MTIME=$(cat "$DEPLOY_MARKER" 2>/dev/null || echo 0)

if [ "$SPINE_MTIME" -gt "$LAST_DEPLOY_MTIME" ]; then
  echo "SPINE.md changed (mtime $SPINE_MTIME > last-deploy $LAST_DEPLOY_MTIME); deploying"
  cd "$WS/fusion-os"
  if vercel --prod --yes 2>&1 | tail -5; then
    echo "$SPINE_MTIME" > "$DEPLOY_MARKER"
    echo "✓ deployed and marker updated"
  else
    echo "❌ deploy failed; marker NOT updated, will retry next cron tick"
    exit 1
  fi
else
  echo "SPINE.md unchanged since last deploy; skipping vercel deploy"
fi

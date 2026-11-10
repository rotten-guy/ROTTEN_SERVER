#!/usr/bin/env bash
# mc: switch the box between playing (practice world) and pre-generating the
# future "official" world, and chain Chunky over the 3 dimensions by itself.
#
# Installed as /usr/local/bin/mc (symlink to this file, see docs/SETUP.md § 9.8).
#
#   mc status          what runs, players online, Chunky progress, plan step
#   mc play            stop the pre-generation, start the practice server
#   mc pregen [-f]     stop the practice server (refuses if players are online,
#                      unless -f), start minecraft-return; the timer does the rest
#   mc stop            stop minecraft-return only (graceful: world + Chunky saved)
#   mc loop            run `mc tick` every 5 min in the foreground (machines without the timer)
#   mc init-return     one-time: prepare minecraft-return (config, world datapacks, .env)
#   mc seed            seed of the minecraft-return world
#   mc tick            called every 5 min by mc-pregen.timer: resume Chunky, or
#                      start the next dimension once the previous one is finished
#
# Only one Minecraft server runs at a time: 6 GB of RAM can't hold two.
set -euo pipefail

# Overridable, e.g. to pre-generate on a faster machine (see docs/SETUP.md § 9.7):
#   MC_RET_DIR=~/mc-pregen/minecraft-return mc pregen
PLAY_DIR=${MC_PLAY_DIR:-/opt/stacks/minecraft}
RET_DIR=${MC_RET_DIR:-/opt/stacks/minecraft-return}
PLAY_CT=minecraft
RET_CT=minecraft-return
STATE="$RET_DIR/data/pregen-step"           # index of the next plan step to start

# Pre-generation plan: world | centre ("spawn" or "x z") | radius (blocks)
PLAN=(
  "minecraft:overworld|spawn|5000"
  "minecraft:the_nether|0 0|1500"
  "minecraft:the_end|0 0|2000"
)

log()     { echo "[mc $(date '+%F %T')] $*"; }
running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }
rcon()    { docker exec "$1" rcon-cli "$2" 2>/dev/null; }
compose() {  # -f disables compose.override.yaml auto-loading: add it back when present
  local d=$1; shift
  local files=(-f "$d/compose.yaml")
  [ -f "$d/compose.override.yaml" ] && files+=(-f "$d/compose.override.yaml")
  docker compose "${files[@]}" "$@"
}

wait_ready() {  # wait until RCON answers (server finished booting)
  local ct=$1 i
  printf 'Waiting for %s to finish booting' "$ct"
  for i in $(seq 1 240); do
    if rcon "$ct" "list" >/dev/null; then echo " ready."; return 0; fi
    printf '.'; sleep 5
  done
  echo; log "$ct did not answer RCON after 20 min: check 'docker logs $ct'"; return 1
}

players() {  # number of players online on a running server
  rcon "$1" "list" | grep -oE 'There are [0-9]+' | grep -oE '[0-9]+' || echo 0
}

stop_server() {  # save, then stop the whole stack gracefully
  local dir=$1 ct=$2
  if running "$ct"; then
    log "Saving and stopping $ct…"
    rcon "$ct" "save-all flush" >/dev/null || true
    compose "$dir" stop
  fi
}

step() { cat "$STATE" 2>/dev/null || echo 0; }

global_progress() {  # all 3 dimensions together: chunks done / total + ETA at the current rate
  local n out total=0 done=0 cur rate i r c
  n=$(step)
  out=$(rcon "$RET_CT" "chunky progress" || true)
  for i in "${!PLAN[@]}"; do
    IFS='|' read -r _ _ r <<<"${PLAN[$i]}"
    c=$(( (2*((r+15)/16)+1)**2 ))             # Chunky square: (2*ceil(r/16)+1)^2 chunks
    total=$((total+c))
    if [ "$n" -gt "${#PLAN[@]}" ] || [ "$i" -lt "$((n-1))" ]; then done=$((done+c)); fi
  done
  cur=$(grep -oE 'Processed: [0-9]+' <<<"$out" | grep -oE '[0-9]+' || echo 0)
  rate=$(grep -oE 'Rate: [0-9.]+' <<<"$out" | grep -oE '[0-9.]+' || echo 0)
  [ "$n" -gt "${#PLAN[@]}" ] && cur=0
  awk -v d="$((done+cur))" -v t="$total" -v r="$rate" 'BEGIN{
    printf "  %d / %d chunks (%.1f%%)", d, t, 100*d/t
    if (r > 0 && d < t) { s=(t-d)/r; printf " — ETA ~%dh%02d at %.1f cps (rate varies per dimension)", s/3600, (s%3600)/60, r }
    print "" }'
}

cmd_status() {
  echo "== Mode"
  if running "$PLAY_CT"; then
    echo "  PLAY    — practice server up, $(players "$PLAY_CT") player(s) online"
  elif running "$RET_CT"; then
    echo "  PREGEN  — minecraft-return up"
  else
    echo "  OFF     — no Minecraft server running"
  fi
  echo "== Pre-generation plan (minecraft-return)"
  local n i; n=$(step)
  for i in "${!PLAN[@]}"; do
    IFS='|' read -r world _ radius <<<"${PLAN[$i]}"
    if   [ "$i" -lt "$((n-1))" ]; then mark="done"
    elif [ "$i" -eq "$((n-1))" ]; then mark="current"
    else mark="todo"; fi
    [ "$n" -gt "${#PLAN[@]}" ] && mark="done"
    printf '  %-8s %-22s radius %s\n' "$mark" "$world" "$radius"
  done
  [ "$n" -gt "${#PLAN[@]}" ] && echo "  >>> All 3 dimensions pre-generated."
  if running "$RET_CT"; then echo "== Global (3 dimensions)"; global_progress; fi
  if running "$RET_CT"; then
    echo "== Chunky"
    rcon "$RET_CT" "chunky progress" | sed 's/^/  /' || echo "  (server still booting)"
  fi
  echo "== Finished tasks (since minecraft-return last started)"
  docker logs --since "$(docker inspect -f '{{.State.StartedAt}}' "$RET_CT" 2>/dev/null)" "$RET_CT" 2>&1 | grep "Task finished" | sed 's/^/  /' || echo "  none yet"
}

cmd_play() {
  stop_server "$RET_DIR" "$RET_CT"
  log "Starting the practice server…"
  compose "$PLAY_DIR" up -d
  wait_ready "$PLAY_CT" && log "Play on mc.rotten-guy.com"
}

cmd_pregen() {
  [ -f "$RET_DIR/.env" ] || { log "Run 'mc init-return' first."; exit 1; }
  if running "$PLAY_CT"; then
    local p; p=$(players "$PLAY_CT")
    if [ "$p" -gt 0 ] && [ "${1:-}" != "-f" ]; then
      log "$p player(s) online on the practice server: not stopping it (use 'mc pregen -f' to force)."
      exit 1
    fi
  fi
  stop_server "$PLAY_DIR" "$PLAY_CT"
  log "Starting minecraft-return…"
  compose "$RET_DIR" up -d
  wait_ready "$RET_CT" && { cmd_tick || true; }
  log "Pre-generation running. 'mc status' to follow it, 'mc play' to get your world back."
}

cmd_stop() { stop_server "$RET_DIR" "$RET_CT"; log "minecraft-return stopped."; }

cmd_loop() {  # for a machine without mc-pregen.timer (e.g. the desktop)
  log "Chaining the pre-generation every 5 min. Ctrl+C to stop watching (the server keeps running)."
  while true; do
    cmd_tick || true
    [ "$(step)" -gt "${#PLAN[@]}" ] && { log "Plan complete."; break; }
    sleep 300
  done
}

cmd_init_return() {
  local src=$PLAY_DIR/data dst=$RET_DIR/data
  [ -d "$RET_DIR" ] || { log "$RET_DIR missing: run 'scripts/stacks.sh export' first."; exit 1; }
  if [ -f "$dst/world/level.dat" ]; then
    log "minecraft-return already has a world: nothing to do."; return 0
  fi
  log "Preparing $dst…"
  sudo mkdir -p "$dst/world"
  # Mod configs as currently tuned on the practice server (the pack re-applies its own on boot)
  [ -d "$src/config" ] && sudo cp -a "$src/config" "$dst/"
  # World-level datapacks and per-world mod configs must exist BEFORE the world is created
  for d in datapacks serverconfig; do
    [ -d "$src/world/$d" ] && sudo cp -a "$src/world/$d" "$dst/world/"
  done
  sudo cp --update=none "$PLAY_DIR/.env" "$RET_DIR/.env"
  sudo chown -R 1000:1000 "$dst"
  echo 0 | sudo tee "$STATE" >/dev/null && sudo chown 1000:1000 "$STATE"
  log "Done. Copied: config/, world/datapacks, world/serverconfig, .env. Next: 'mc pregen'."
}

cmd_seed() {
  if running "$RET_CT"; then rcon "$RET_CT" "seed"
  else log "minecraft-return is not running (seed is in $RET_DIR/data/world/level.dat)."; fi
}

cmd_tick() {
  exec 9>"/tmp/mc-tick.$(id -u).lock"; flock -n 9 || return 0
  running "$RET_CT" || return 0                     # play mode: nothing to do
  rcon "$RET_CT" "list" >/dev/null || return 0      # still booting
  local out n
  out=$(rcon "$RET_CT" "chunky progress")
  grep -q "Task running" <<<"$out" && return 0      # busy, all good
  out=$(rcon "$RET_CT" "chunky continue")
  if grep -q "continuing" <<<"$out"; then log "Resumed: $out"; return 0; fi

  # Nothing running, nothing to resume: the current step is finished (or none started yet)
  n=$(step)
  if [ "$n" -ge "${#PLAN[@]}" ]; then
    if [ "$n" -eq "${#PLAN[@]}" ]; then log "All dimensions pre-generated."; echo $((n+1)) > "$STATE"; fi
    return 0
  fi
  IFS='|' read -r world centre radius <<<"${PLAN[$n]}"
  log "Starting step $((n+1))/${#PLAN[@]}: $world, radius $radius, centre $centre"
  rcon "$RET_CT" "chunky world $world" >/dev/null
  if [ "$centre" = "spawn" ]; then rcon "$RET_CT" "chunky spawn" >/dev/null
  else rcon "$RET_CT" "chunky center $centre" >/dev/null; fi
  rcon "$RET_CT" "chunky radius $radius" >/dev/null
  out=$(rcon "$RET_CT" "chunky start")
  grep -q "already started" <<<"$out" && out=$(rcon "$RET_CT" "chunky confirm")
  if grep -qi "started" <<<"$out"; then
    echo $((n+1)) > "$STATE"; log "$out"
  else
    log "Could not start $world: $out"; return 1
  fi
}

case "${1:-status}" in
  status)      cmd_status ;;
  play)        cmd_play ;;
  pregen)      cmd_pregen "${2:-}" ;;
  init-return) cmd_init_return ;;
  seed)        cmd_seed ;;
  stop)        cmd_stop ;;
  loop)        cmd_loop ;;
  tick)        cmd_tick ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac

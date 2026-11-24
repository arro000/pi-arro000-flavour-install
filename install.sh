#!/usr/bin/env bash
set -euo pipefail

packages=(
  npm:@aliou/pi-guardrails
  npm:pi-goal-x
  npm:pi-autoresearch
  npm:better-custom
  npm:pi-web-access
  npm:@juicesharp/rpiv-ask-user-question
  npm:@ff-labs/pi-fff
  npm:pi-rtk-optimizer
  npm:pi-lens
  npm:pi-extmgr
  npm:@dietrichgebert/ponytail
  npm:@quintinshaw/pi-dynamic-workflows
  npm:pi-codex-status
  npm:pi-subagents
  npm:pi-simplify
  npm:@tmustier/pi-usage-extension
  npm:pi-btw
  npm:pi-terminal-theme
  npm:pi-tool-display
  npm:pi-open-tui
  npm:@arro000/pi-monokai-contrast
)

if [[ $# != 0 ]]; then
  printf 'Uso: bash install.sh\n' >&2
  exit 2
fi
if [[ $EUID == 0 || $(uname -s) != Linux && $(uname -s) != Darwin ]]; then
  printf 'Esegui come utente normale su Linux o macOS.\n' >&2
  exit 1
fi
command -v curl >/dev/null || { printf 'Serve curl.\n' >&2; exit 1; }

agent_dir=${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}
work=$(mktemp -d)
loader_pid=
done_steps=0
total=$(( ${#packages[@]} + 2 ))
animate=false
if [[ -t 2 && ${TERM:-dumb} != dumb ]] && command -v tput >/dev/null &&
   (( $(tput cols 2>/dev/null || echo 0) >= 42 && $(tput lines 2>/dev/null || echo 0) >= 16 )); then
  animate=true
fi

# La parte illuminata segue l'avanzamento; la superficie ruota anche a progresso fermo.
torus_frame() {
  LC_ALL=C awk -v frame="$1" -v fill="$2" 'BEGIN {
    a = frame*0.10; b = frame*0.06
    for (u=0; u<6.283; u+=0.09) for (v=0; v<6.283; v+=0.16) {
      r=1.8+0.7*cos(v)
      x=r*cos(u); y=r*sin(u); z=0.7*sin(v)
      yy=y*cos(a)-z*sin(a); zz=y*sin(a)+z*cos(a)
      xx=x*cos(b)-yy*sin(b); yy=x*sin(b)+yy*cos(b)
      col=int(19+xx*7); row=int(6+yy*2.4)
      if (col<0 || col>=38 || row<0 || row>=13) continue
      k=row*38+col
      if (!(k in depth) || zz>depth[k]) {
        depth[k]=zz
        light=(cos(v)*sin(u)*sin(a)+sin(v)*cos(a)+1)/2
        cell[k]=u<fill*0.062832 ? substr("oO0%@#",1+int(light*5),1) : "."
      }
    }
    for (row=0; row<13; row++) {
      for (col=0; col<38; col++) {
        k=row*38+col; printf "%s", k in cell ? cell[k] : " "
      }
      printf "\n"
    }
  }'
}

loader() {
  local frame=0 percent=$(( 100 * done_steps / total ))
  while :; do
    torus_frame "$frame" "$percent"
    printf '\033[13A'
    frame=$(( frame + 1 ))
    sleep 0.10
  done >&2
}

stop_loader() {
  if [[ -n $loader_pid ]]; then
    kill "$loader_pid" 2>/dev/null || true
    wait "$loader_pid" 2>/dev/null || true
    loader_pid=
    printf '\033[u\033[J\033[?25h' >&2
  fi
}
trap 'stop_loader; rm -rf -- "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

step() {
  local label=$1 status
  shift
  printf '[%d/%d - %d%%] %s\n' "$done_steps" "$total" "$((100 * done_steps / total))" "$label" >&2
  if $animate; then
    # Riserva righe reali prima di salvare la posizione, anche a fondo schermo.
    printf '\n\n\n\n\n\n\n\n\n\n\n\n\n\033[13A\033[s\033[?25l' >&2
    loader & loader_pid=$!
    status=0
    "$@" >"$work/step.log" 2>"$work/step.err" || status=$?
    stop_loader
    cat "$work/step.err" >&2
    if (( status != 0 )); then
      cat "$work/step.log" >&2
      return "$status"
    fi
  else
    "$@"
  fi
  done_steps=$(( done_steps + 1 ))
}

step 'Scarico l’installer ufficiale' curl -fsSL https://pi.dev/install.sh -o "$work/pi-install.sh"
printf '[%d/%d] Installer ufficiale di Pi (rispondi alle richieste a schermo)\n' "$done_steps" "$total" >&2
PI_LEGACY_INSTALL=0 sh "$work/pi-install.sh"
done_steps=$(( done_steps + 1 ))

pi_bin="$agent_dir/bin/pi"
if [[ ! -x $pi_bin ]]; then
  printf 'Launcher gestito non trovato in %s. Completa l’installazione ufficiale e riprova.\n' "$pi_bin" >&2
  exit 1
fi
pi_version=$("$pi_bin" --version)
for package in "${packages[@]}"; do
  step "Installo $package" "$pi_bin" install "$package" --no-approve
done

if $animate; then torus_frame 0 100 >&2; fi
printf '[%d/%d - 100%%] Pi %s e %d pacchetti installati.\n' "$done_steps" "$total" "$pi_version" "${#packages[@]}"
printf 'Avvia con pi oppure con: %q\n' "$pi_bin"

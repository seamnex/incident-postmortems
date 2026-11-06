#!/usr/bin/env bash
# Verifica que cada documento tenga su versión en el otro idioma.
#
# Cada documento en español enlaza a su traducción con "[English](...)", y cada
# documento en inglés a la suya con "[Español](...)". El script comprueba que
# el link exista, que el archivo enlazado exista y que ese archivo enlace de
# vuelta. Así una traducción que falta, o un archivo renombrado de un solo
# lado, rompe el CI en vez de quedar como un link muerto que nadie revisa.
set -euo pipefail

cd "$(dirname "$0")/.."
errores=0

enlace() { # archivo, etiqueta -> ruta enlazada (vacía si no hay)
  grep -oE "\[$2\]\([^)]+\)" "$1" | head -n1 | sed -E 's/.*\(([^)]+)\)/\1/' || true
}

revisar() { # archivo, etiqueta de ida, etiqueta de vuelta
  local archivo="$1" ida="$2" vuelta="$3" destino par
  destino="$(enlace "$archivo" "$ida")"
  if [ -z "$destino" ]; then
    echo "FALTA  $archivo no enlaza a su versión [$ida]"; errores=$((errores + 1)); return
  fi
  par="$(dirname "$archivo")/$destino"
  if [ ! -f "$par" ]; then
    echo "ROTO   $archivo -> $destino (no existe)"; errores=$((errores + 1)); return
  fi
  if [ "$(realpath "$(dirname "$par")/$(enlace "$par" "$vuelta")" 2>/dev/null)" != "$(realpath "$archivo")" ]; then
    echo "VUELTA $par no enlaza de vuelta a $archivo"; errores=$((errores + 1)); return
  fi
  echo "ok     $archivo <-> $par"
}

for f in postmortems/es/*.md runbooks/es/*.md plantilla/*.es.md; do revisar "$f" English Español; done
for f in postmortems/en/*.md runbooks/en/*.md plantilla/*.en.md; do revisar "$f" Español English; done

echo
if [ "$errores" -gt 0 ]; then
  echo "$errores problema(s) de paridad"; exit 1
fi
echo "Paridad ES/EN completa"

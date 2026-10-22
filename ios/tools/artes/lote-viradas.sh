#!/bin/zsh
# Gera as viradas até acabar: quando o ChatGPT bate o limite diário, espera 1 h e tenta de novo.
# Precisa do Chrome aberto com ./chrome.sh.  Uso: ./lote-viradas.sh [abas]
cd ${0:A:h}
export ARTES_WORK=.work-viradas
while true; do
  node gerar.mjs ${1:-4}
  falta=$(python3 -c "import json,os; print(sum(not os.path.exists(j['out']) for j in json.load(open('$ARTES_WORK/jobs.json'))))")
  echo "$(date +%H:%M) faltam $falta"
  (( falta == 0 )) && break
  sleep 3600
done

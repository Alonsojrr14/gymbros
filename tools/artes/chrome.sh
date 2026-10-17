#!/bin/zsh
# Abre o Chrome com uma CÓPIA do seu perfil (para entrar já logado no ChatGPT) e depuração na porta 9333.
# O Chrome não permite automação no perfil original. A cópia tem seus cookies: fica fora do repositório
# e é apagada com ./chrome.sh --apagar.  Uso: ./chrome.sh [perfil, padrão Default] | --apagar
COPIA=~/Library/Caches/gymmonsters-chrome
if [[ $1 == --apagar ]]; then
  pkill -f "user-data-dir=$COPIA"; sleep 2; rm -rf $COPIA; echo "cópia do perfil apagada"; exit 0
fi
PERFIL=${1:-Default}
ORIGEM="$HOME/Library/Application Support/Google/Chrome"
if [[ ! -d $COPIA/$PERFIL ]]; then
  mkdir -p $COPIA/$PERFIL && cp "$ORIGEM/Local State" $COPIA/
  rsync -a --exclude 'Cache' --exclude 'Code Cache' --exclude 'GPUCache' --exclude 'Service Worker/CacheStorage' \
    --exclude 'File System' --exclude 'IndexedDB' --exclude 'Extensions' "$ORIGEM/$PERFIL/" $COPIA/$PERFIL/
fi
nohup "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --user-data-dir=$COPIA --profile-directory=$PERFIL \
  --remote-debugging-port=9333 --no-first-run --no-default-browser-check https://chatgpt.com/ >/dev/null 2>&1 &
for i in {1..20}; do curl -s localhost:9333/json/version >/dev/null && { echo "Chrome pronto na porta 9333"; exit 0; }; sleep 1; done
echo "Chrome não abriu a porta 9333"; exit 1

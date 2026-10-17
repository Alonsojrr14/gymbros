#!/bin/zsh
# Recorta cada arte de .work/raw e cria os imagesets sprite_<espécie_>champion_a_b no app, no widget e o _live (96 px).
# Ultimates usam FLOOD=1: o recorte do Vision apaga a aura, então só o fundo liso ligado às bordas sai.
ROOT=${0:A:h:h:h}   # antes do cd: com caminho relativo, ${0:A} depende da pasta atual
cd ${0:A:h}
WORK=${ARTES_WORK:-.work}
mkdir -p $WORK/final $WORK/live
[[ -x .work/recortar-final && .work/recortar-final -nt recortar-final.swift ]] || { mkdir -p .work; swiftc -O recortar-final.swift -o .work/recortar-final; }
for f in $WORK/raw/*.png(N); do
  b=$(basename $f .png)
  n=512; [[ $b == champion_* || $b == ultimate_* ]] && n=640   # coelho (espécie padrão) usa 640 como os sprites dele
  if [[ ! -f $WORK/final/$b.png || $f -nt $WORK/final/$b.png ]]; then
    if [[ $b == *ultimate_* ]]; then FLOOD=1 .work/recortar-final $f $WORK/final/$b.png $n $WORK/live/$b.png 96
    else .work/recortar-final $f $WORK/final/$b.png $n $WORK/live/$b.png 96; fi
  fi
  for A in $ROOT/GymMonsters/Assets.xcassets $ROOT/GymMonstersWidget/Assets.xcassets; do
    d=$A/sprite_$b.imageset; mkdir -p $d; cp $WORK/final/$b.png $d/$b.png
    echo "{\"images\":[{\"filename\":\"$b.png\",\"idiom\":\"universal\"}],\"info\":{\"author\":\"xcode\",\"version\":1}}" > $d/Contents.json
  done
  d=$ROOT/GymMonstersWidget/Assets.xcassets/sprite_${b}_live.imageset; mkdir -p $d; cp $WORK/live/$b.png $d/sprite_${b}_live.png
  echo "{\"images\":[{\"filename\":\"sprite_${b}_live.png\",\"idiom\":\"universal\"}],\"info\":{\"author\":\"xcode\",\"version\":1},\"properties\":{\"compression-type\":\"lossless\"}}" > $d/Contents.json
done
echo "instaladas: $(ls $WORK/raw/*.png(N) | wc -l | tr -d ' ')"

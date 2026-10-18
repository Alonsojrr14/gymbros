# Ferramentas

`recortar-sprite.swift`: recorta o monstro do fundo com o Vision do macOS (o mesmo recorte de objeto das Fotos) e deixa a borda nítida para o pixel art.

```sh
swiftc -O tools/recortar-sprite.swift -o /tmp/recortar
/tmp/recortar entrada.png saida.png [margem]
```

`margem` (pixels) descarta faixas de imagens vizinhas nas bordas; use 0 quando o desenho encosta na borda (ex.: anilhas).

`recortar-quadro.swift`: corta um quadro (x, y, largura, altura) de uma folha com as 10 evoluções, antes de passar no `recortar-sprite`.

```sh
swift tools/recortar-quadro.swift folha.png quadro.png x y largura altura
```

Nas folhas 1536×1024 geradas até aqui, os quadros são: linha de cima (y 0–484) com x 0–288, 288–586, 586–905, 905–1217, 1217–1536 (bebê, rookie, champion força, resistência, agilidade); linha de baixo (y 484–1024) com x 0–258, 258–636, 636–935, 935–1217, 1217–1536 (champion técnica, ultimate força, resistência, agilidade, técnica).

## Artes novas (`tools/artes/`)

Gera as artes pelo ChatGPT do navegador (a cota de imagem do chat é maior que a do Codex CLI), recorta e instala no app. Hoje cobre as formas híbridas do `HIBRIDOS.md`.

```sh
cd tools/artes && npm install          # uma vez (playwright-core)
./chrome.sh                            # Chrome com cópia do seu perfil, já logado no ChatGPT (porta 9333)
python3 prompts.py                     # .work/jobs.json: prompt e referências de cada arte
node gerar.mjs 2                       # gera o que falta em .work/raw (2 abas; pula o que já existe)
swift folha.swift .work/folha.png .work/raw/*.png   # revise: confira se cada arte bate com o nome
./instalar.sh                          # recorta e cria os imagesets no app, no widget e o _live
./chrome.sh --apagar                   # fecha o Chrome e apaga a cópia do perfil (tem seus cookies)
```

- Para refazer uma arte, apague o arquivo dela em `.work/raw` e rode `gerar.mjs` de novo; o Ultimate híbrido usa o Champion gerado como referência, então refaça os dois juntos.
- O ChatGPT guarda o rascunho da caixa entre conversas: o `gerar.mjs` limpa a caixa e confere que a conversa tem só o prompt daquele arquivo antes de baixar. Mesmo assim, revise a folha.
- Ultimates têm aura: o `instalar.sh` recorta só o fundo liso ligado às bordas (`FLOOD=1`), porque o recorte do Vision apaga a aura.
- `.work/` e a cópia do perfil (`~/Library/Caches/gymbros-chrome`) ficam fora do git.

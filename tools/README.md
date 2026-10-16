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

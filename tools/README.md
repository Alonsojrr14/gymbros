# Ferramentas

`recortar-sprite.swift`: recorta o monstro do fundo com o Vision do macOS (o mesmo recorte de objeto das Fotos) e deixa a borda nítida para o pixel art.

```sh
swiftc -O tools/recortar-sprite.swift -o /tmp/recortar
/tmp/recortar entrada.png saida.png [margem]
```

`margem` (pixels) descarta faixas de imagens vizinhas nas bordas; use 0 quando o desenho encosta na borda (ex.: anilhas).

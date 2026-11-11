#!/usr/bin/env python3
"""Рисует простые пиксельные спрайты флоры 16×16 в assets/sprites/flora.

Запуск: python3 tools/make_flora_sprites.py  (нужен Pillow).
Низ картинки — земля клетки: растение стоит на нижнем крае.
Замени картинки своими — имена файлов заданы в data/biomes.json (flora.sprite).
"""
from pathlib import Path
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "assets" / "sprites" / "flora"

# Буквы → цвета. '.' — прозрачно.
PAL = {
    "k": (28, 40, 22, 255),     # тёмный контур
    "d": (38, 92, 34, 255),     # тёмная листва
    "g": (62, 132, 48, 255),    # листва
    "l": (110, 172, 70, 255),   # светлая листва
    "t": (92, 62, 36, 255),     # ствол
    "T": (60, 40, 24, 255),     # тёмный ствол
    "c": (24, 70, 48, 255),     # тёмная хвоя
    "n": (40, 104, 66, 255),    # хвоя
    "N": (78, 140, 92, 255),    # светлая хвоя
    "r": (196, 40, 58, 255),    # ягода
    "R": (240, 110, 120, 255),  # блик ягоды
    "y": (150, 150, 64, 255),   # камыш
    "Y": (110, 112, 46, 255),   # тёмный камыш
    "b": (96, 60, 34, 255),     # початок камыша
    "w": (214, 186, 90, 255),   # колос
    "W": (240, 220, 130, 255),  # светлый колос
    "s": (160, 132, 60, 255),   # стебель злака
}

SPRITES = {
    "broadleaf": [
        "................",
        ".....kkkkk......",
        "...kkgglllkk....",
        "..kgggglllggk...",
        ".kddggggllgggk..",
        ".kdgggggglgggk..",
        "kddggdgggggggk..",
        "kdddgggggggdgkk.",
        "kddddggggdggddk.",
        ".kdddddggdddddk.",
        ".kkdddddddddkk..",
        "...kkkdtdkkk....",
        "......Ttt.......",
        "......Ttt.......",
        ".....TTttt......",
        "................",
    ],
    "conifer": [
        ".......k........",
        "......knk.......",
        ".....knNnk......",
        ".....cnNnk......",
        "....kcnnNnk.....",
        "...kccnnnNnk....",
        ".....cnnNnk.....",
        "....kccnnnNk....",
        "...kcccnnnNnk...",
        "..kccccnnnnNnk..",
        "....kccnnnnk....",
        "...kcccnnnnnk...",
        "..kcccccnnnnnk..",
        ".kkkkkkTtkkkkkk.",
        ".......Tt.......",
        "................",
    ],
    "bush": [
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        ".....kkkk.......",
        "...kkglllkk.....",
        "..kggggllggk....",
        ".kdggggggggkk...",
        ".kddgggdggglgk..",
        "kdddddggggggdk..",
        "kkdddddddddddk..",
        ".kkkkkkkkkkkk...",
        "................",
    ],
    "berries": [
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        ".....kkkk.......",
        "...kkglrRkk.....",
        "..kgrRglrgggk...",
        ".kdgrggrRggrRk..",
        ".kdrRgggrgggrk..",
        "kddrdgrRggrRgdk.",
        "kkdddddrddrdddk.",
        ".kkkkkkkkkkkkk..",
        "................",
    ],
    "reed": [
        "................",
        "................",
        "....b.....b.....",
        "....b..b..b.....",
        "...yb..b..b..b..",
        "...y.y.b.yb..b..",
        "...y.y.yy.y.yb..",
        "..y..y.y..y.y...",
        "..y..yy.y.y.y...",
        "..yY.y..y.yy....",
        "...Y.yY.yYy.....",
        "...YY.Y.Y.Y.....",
        "....Y.YYY.Y.....",
        "....YYYYYYY.....",
        "................",
        "................",
    ],
    "wild_grain": [
        "................",
        "................",
        "................",
        "................",
        "................",
        "....W.....W.....",
        "...wWw.W..wW....",
        "...ww.wWw.ww.W..",
        "....wsww..sw.wW.",
        "..W..s.ws..s.w..",
        ".wWw.s..s..s.s..",
        "..w..s..s.s..s..",
        "...s.s..s.s.s...",
        "....s.s.s.ss....",
        "................",
        "................",
    ],
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, rows in SPRITES.items():
        assert len(rows) == 16 and all(len(r) == 16 for r in rows), name
        img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch != ".":
                    img.putpixel((x, y), PAL[ch])
        img.save(OUT / f"{name}.png")
        print("готово:", OUT / f"{name}.png")


if __name__ == "__main__":
    main()

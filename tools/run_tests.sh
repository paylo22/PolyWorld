#!/usr/bin/env sh
# Запуск тестов без окна. Нужен Godot 4.7 в PATH под именем godot
# (или укажи путь: GODOT=/путь/к/godot tools/run_tests.sh).
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
# Первый запуск: импорт проекта (создаёт .godot/ и кэш классов).
[ -d .godot ] || "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
exec "$GODOT" --headless --path . -s res://tests/run_tests.gd

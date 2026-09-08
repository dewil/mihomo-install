#!/usr/bin/env bash
# Проверка ветки "политика из правил осталась без узла" в mihomo-build-config.
#
# Запуск:  bash tests/stub-policy.sh
# Требует: python3, curl, base64. Права root не нужны - песочница поднимается
# через MIHOMO_BASE, боевой /etc/mihomo не трогается.
#
# ЛОВУШКА, на которую легко наступить при ручной проверке: сценарий "конфига
# нет" нельзя гонять двумя запусками подряд. Первый запуск создает config.yaml,
# и второй честно уходит в ветку "конфиг есть" с кодом 3 - выглядит как провал,
# хотя это правильное поведение. Поэтому каждый сценарий ниже готовит свое
# предусловие явно.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDER="$ROOT/usr/local/sbin/mihomo-build-config"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

FAILED=0
hashof() { if command -v md5sum >/dev/null; then md5sum "$1" | cut -d" " -f1; else md5 -q "$1"; fi; }
ok()   { printf '  ok   %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; FAILED=1; }
check(){ [[ "$2" == "$3" ]] && ok "$1 ($2)" || bad "$1: ожидалось [$3], получено [$2]"; }

mkdir -p "$SB/base" "$SB/subs"
cp "$ROOT/etc/mihomo/config.base.yaml" "$ROOT/etc/mihomo/iso3166_alpha2.txt" "$SB/base/"
printf 'rules:\n  - "DOMAIN-SUFFIX,example.com,de"\n' > "$SB/base/routing-rules.yaml"
printf 'rules: []\n' > "$SB/base/local-rules.yaml"

node() { # $1 = код страны, $2 = имя узла в percent-encoding
  printf 'vless://11111111-2222-3333-4444-555555555555@%s.example.net:443?hiddify=1&sni=%s.example.net&type=grpc&alpn=h2&path=ABC&host=%s.example.net&serviceName=ABC&mode=gun&encryption=none&fp=chrome&headerType=none&security=tls#%s\n' "$1" "$1" "$1" "$2"
}
DE="%F0%9F%87%A9%F0%9F%87%AA%20DE%20direct%20node"
EE="%F0%9F%87%AA%F0%9F%87%AA%20EE%20direct%20node"
{ node de "$DE"; node ee "$EE"; } | base64 > "$SB/subs/both.txt"
node ee "$EE" | base64 > "$SB/subs/no_de.txt"
node de "$DE" | base64 > "$SB/subs/only_de.txt"

build() { # $1 = файл подписки; печатает код возврата, вывод в $OUT_FILE
  printf 'file://%s/subs/%s\n' "$SB" "$1" > "$SB/base/subscription.url"
  # env, а не префикс присваивания: раскрытие ${ALLOW_SHRINK:+...} происходит
  # ПОСЛЕ того, как оболочка разобрала присваивания, и такое слово ушло бы в
  # имя команды (получали "127: command not found").
  env MIHOMO_BASE="$SB/base" MIHOMO_MIN_NODES_ABS=1 MIHOMO_MIN_NODES_RATIO=0.1 \
    ${ALLOW_SHRINK:+MIHOMO_ALLOW_SHRINK=1} python3 "$BUILDER" >"$SB/out.txt" 2>&1
  echo $?
}
fresh() { rm -f "$SB/base/config.yaml" "$SB/base/build-state.json"; }
# grep -c при нуле совпадений печатает 0 И возвращает 1: конструкция
# "grep -c ... || echo 0" дает две строки, а не одну.
stubs() { grep -c "^      - $1\$" "$SB/base/config.yaml" 2>/dev/null | head -1; }

echo "A. узел на месте - обычная сборка"
fresh; RC=$(build both.txt)
check "код возврата" "$RC" "0"
check "группа de реальная" "$(grep -A1 '^  - name: de$' "$SB/base/config.yaml" | tail -1 | tr -d ' ')" "type:url-test"
check "заглушек DIRECT" "$(stubs DIRECT)" "0"

echo "B. узел потерян, предыдущий конфиг ЕСТЬ - отмена, конфиг не тронут"
BEFORE=$(hashof "$SB/base/config.yaml")
RC=$(build no_de.txt)
check "код возврата" "$RC" "3"
check "конфиг не изменился" "$(hashof "$SB/base/config.yaml")" "$BEFORE"
grep -q "политики без узла" "$SB/out.txt" && ok "причина названа в выводе" || bad "в выводе нет причины"

echo "C. узел потерян, предыдущего конфига НЕТ - сборка с REJECT"
fresh; RC=$(build no_de.txt)
check "код возврата" "$RC" "0"
check "заглушек REJECT" "$(stubs REJECT)" "1"
check "заглушек DIRECT" "$(stubs DIRECT)" "0"

echo "D. алиас без узла, но и без ссылки в правилах - блокировки нет"
fresh; RC=$(build only_de.txt)
check "код возврата" "$RC" "0"
check "заглушек всего" "$(( $(stubs REJECT) + $(stubs DIRECT) ))" "0"

echo "E. конфиг ЕСТЬ, но человек продавил MIHOMO_ALLOW_SHRINK - сборка с REJECT"
fresh; build both.txt >/dev/null            # предусловие: рабочий конфиг на месте
BEFORE=$(hashof "$SB/base/config.yaml")
RC=$(ALLOW_SHRINK=1 build no_de.txt)
check "код возврата" "$RC" "0"
check "конфиг перезаписан" "$([[ "$(hashof "$SB/base/config.yaml")" != "$BEFORE" ]] && echo да || echo нет)" "да"
check "заглушек REJECT" "$(stubs REJECT)" "1"
check "заглушек DIRECT" "$(stubs DIRECT)" "0"

echo
[[ $FAILED -eq 0 ]] && echo "ВСЕ СЦЕНАРИИ ПРОШЛИ" || echo "ЕСТЬ ПРОВАЛЫ"
exit $FAILED

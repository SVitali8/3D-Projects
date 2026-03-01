#!/usr/bin/env bash
set -e

REPO_DIR="/Volumes/SSD/3D/REPO"
cd "$REPO_DIR"

MAX_SIZE=$((90 * 1024 * 1024))  # 90 MB
SPLIT_LOG="SPLIT_LOG.md"

echo "== Проверяю изменения =="
git status --short || true

echo "== Поиск файлов > 90MB =="

BIG_FILES=()
while IFS= read -r line; do
  BIG_FILES+=("$line")
done < <(find . \
  -path './.git' -prune -o \
  -type f -size +90M \
  ! -name '*.part_*' \
  -print)

SPLIT_MSGS=()

if [ ${#BIG_FILES[@]} -gt 0 ]; then
  echo "Найдены крупные файлы:"
  for f in "${BIG_FILES[@]}"; do
    size_bytes=$(stat -f%z "$f")
    size_mb=$((size_bytes / 1024 / 1024))
    echo " - $f (${size_mb} MB)"
  done

  echo
  read -p "Разбить эти файлы на части перед коммитом? [y/N]: " ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) echo "Отмена."; exit 1;;
  esac

  if [ ! -f "$SPLIT_LOG" ]; then
    cat > "$SPLIT_LOG" << EOF
# SPLIT_LOG

Лог крупных файлов, которые были разбиты на части для выкладки в GitHub.

EOF
  fi

  for f in "${BIG_FILES[@]}"; do
    size_bytes=$(stat -f%z "$f")
    size_mb=$((size_bytes / 1024 / 1024))

    echo
    echo "== Обработка '$f' (${size_mb} MB) =="

    dir=$(dirname "$f")
    base=$(basename "$f")
    name="${base%.*}"
    ext="${base##*.}"

    parts_dir="${dir}/${name}_parts"
    mkdir -p "$parts_dir"

    tmp_prefix="${parts_dir}/raw_part_"
    split -b 80m "$f" "$tmp_prefix"

    idx=1
    PART_LIST=()
    for part_raw in "${tmp_prefix}"*; do
      part_name="${name}.part_${idx}.${ext}.chunk"
      mv "$part_raw" "${parts_dir}/${part_name}"
      PART_LIST+=("${parts_dir}/${part_name}")
      echo "  -> ${parts_dir}/${part_name}"
      idx=$((idx+1))
    done

    cat > "${parts_dir}/README_SPLIT.txt" << INFO
Файл был слишком большим для GitHub и разбит на части.

Исходное имя: ${base}
Исходный относительный путь: ${f}
Оценочный исходный размер: ${size_mb} MB

Пример реконструкции (bash):

  cat ${name}.part_*.${ext}.chunk > "${base}"

INFO

    backup="${f}.backup_local"
    if [ ! -f "$backup" ]; then
      cp "$f" "$backup"
      echo "  -> Локальный бэкап: ${backup}"
    fi

    rm "$f"
    echo "  -> Оригинальный файл удалён из репозитория: ${f}"

    {
      echo "## $(date '+%Y-%m-%d %H:%M:%S')"
      echo
      echo "- Исходный файл: \`${f}\` (${size_mb} MB)"
      echo "- Части:"
      for p in "${PART_LIST[@]}"; do
        echo "  - \`${p}\`"
      done
      echo
    } >> "$SPLIT_LOG"

    SPLIT_MSGS+=("SPLIT: ${f} -> ${parts_dir} (${size_mb} MB, ${#PART_LIST[@]} parts)")
  done

  echo
  echo "== Крупные файлы обработаны. Продолжаю коммит =="
fi

# Проверка: есть ли что‑то, что Git видит (включая untracked)
if git status --porcelain | grep -q .; then
  : # есть изменения, идём дальше
else
  echo "Изменений нет, пушить нечего."
  exit 0
fi


echo
git status --short

read -p "Комментарий коммита (Enter для авто): " MSG
if [ -z "$MSG" ]; then
  MSG="Update $(date '+%Y-%m-%d %H:%M:%S')"
fi

if [ ${#SPLIT_MSGS[@]} -gt 0 ]; then
  MSG="${MSG}\n\nSplit info:"
  for m in "${SPLIT_MSGS[@]}"; do
    MSG="${MSG}\n- ${m}"
  done
fi

echo
echo "== Итоговый комментарий коммита =="
echo -e "$MSG"
echo

echo "== Добавляю все изменения =="
git add -A

echo "== Делаю commit =="
git commit -m "$MSG"

echo "== Пушу в origin main =="
git push origin main

echo "Готово."


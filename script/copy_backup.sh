#!/usr/bin/env bash
# zip_sync_backup.sh (修改版 + dry-run)
# 功能：先備份，再詢問使用者是否要進行取代，輸入 Y 才會繼續取代流程。
# 新增 dry-run 模式：用參數 --dry-run 啟用，只顯示操作，不實際執行。

set -euo pipefail

DEFAULT_TARGET="/home/threedlidar/IUMOBO_ws/src"
DEFAULT_BACKUP="/home/threedlidar/Backup"

DRY_RUN=false

log() { echo -e "[\033[1;32mINFO\033[0m] $*"; }
warn() { echo -e "[\033[1;33mWARN\033[0m] $*"; }
err() { echo -e "[\033[1;31mERR \033[0m] $*" >&2; }

do_cmd() {
  if $DRY_RUN; then
    log "(dry-run) $*"
  else
    eval "$@"
  fi
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "缺少指令：$1，請先安裝 (e.g. sudo apt install $1)"; exit 1
  fi
}

confirm_default_or_prompt() {
  local t="$1" b="$2"
  if [[ -z "$t" || -z "$b" ]]; then
    read -r -p "未同時輸入 '目標路徑' 與 '備份路徑'。是否使用預設路徑? (Y/N) " ans
    case "${ans:-Y}" in
      Y|y)
        TARGET="$DEFAULT_TARGET"
        BACKUP="$DEFAULT_BACKUP"
        ;;
      N|n)
        read -r -e -p "請輸入 目標路徑: " TARGET
        read -r -e -p "請輸入 備份路徑: " BACKUP
        ;;
      *)
        warn "輸入非 Y/N，預設使用預設路徑。"
        TARGET="$DEFAULT_TARGET"; BACKUP="$DEFAULT_BACKUP";
        ;;
    esac
  else
    TARGET="$t"; BACKUP="$b";
  fi
}

backup_then_remove_dir() {
  local name="$1"
  local src_dir="$TARGET/$name"
  if [[ -d "$src_dir" ]]; then
    local ts; ts=$(date +%Y%m%d-%H%M)
    local dest_zip="$BACKUP/${name}_${ts}.zip"
    log "備份 '$src_dir' → '$dest_zip'"
    if $DRY_RUN; then
      log "(dry-run) cd $TARGET && zip -rq $dest_zip $name"
      log "(dry-run) rm -rf $src_dir"
    else
      (cd "$TARGET" && zip -rq "$dest_zip" "$name")
      rm -rf -- "$src_dir"
    fi
  else
    log "略過：目標路徑下不存在資料夾 '$name'"
  fi
}

copy_unzip_and_cleanup() {
  local zip_path="$1"
  local base="${zip_path##*/}"
  local zip_name="$base"
  log "複製 '$zip_path' → '$TARGET/'"
  do_cmd cp -f -- "$zip_path" "$TARGET/"
  log "解壓 '$TARGET/$zip_name'"
  if $DRY_RUN; then
    log "(dry-run) cd $TARGET && unzip -q -o $zip_name"
  else
    (cd "$TARGET" && unzip -q -o "$zip_name")
  fi
  log "刪除目標路徑中的壓縮檔 '$TARGET/$zip_name'"
  do_cmd rm -f -- "$TARGET/$zip_name"
}

# ===== 主流程 =====
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
shopt -s nullglob

# 檢查 dry-run 參數
if [[ ${1-} == "--dry-run" ]]; then
  DRY_RUN=true
  shift
fi

ARG_TARGET="${1-}"
ARG_BACKUP="${2-}"

confirm_default_or_prompt "$ARG_TARGET" "$ARG_BACKUP"

need_cmd zip
need_cmd unzip

do_cmd mkdir -p -- "$TARGET" "$BACKUP"
log "目標路徑：$TARGET"
log "備份路徑：$BACKUP"

mapfile -t ZIP_FILES < <(printf '%s\n' "$SCRIPT_DIR"/*.zip)
if [[ ${#ZIP_FILES[@]} -eq 0 ]]; then
  warn "目前資料夾無 .zip 檔可處理。"
  exit 0
fi

# Step 1: 備份與刪除目標路徑中的同名資料夾
for z in "${ZIP_FILES[@]}"; do
  base="${z##*/}"          # a.zip
  name="${base%.zip}"      # a
  backup_then_remove_dir "$name"
done

# Step 2: 詢問是否要進行取代
read -r -p "備份已完成，是否要進行取代? (Y/N) " ans
case "${ans:-N}" in
  Y|y)
    for z in "${ZIP_FILES[@]}"; do
      copy_unzip_and_cleanup "$z"
    done
    log "取代完成。"
    ;;
  *)
    log "使用者選擇不進行取代，流程結束。"
    ;;
esac


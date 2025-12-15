#!/usr/bin/env bash
#
# cuesplit - split single-file albums using CUE sheets
#
# Features:
#   - Recursive traversal of album tree
#   - Audio formats: flac, ape, wav, wv, tta, mp3, ogg
#   - Pairing rule: prefer    File.ext.cue
#                    fallback File.cue
#   - Output directory: Artist - Year - Album
#   - Light filename sanitization (remove dots in basename)
#   - Never writes into source album directories
#   - Uses mktemp -d for safe isolated temp dirs
#   - Keeps source images by default (optional --delete-source)
#   - Overwrites output files cleanly
#
# macOS / BSD / Linux compatible

set -euo pipefail

#############################################
# Globals / default settings
#############################################
OUTPUT_ROOT=""
TEMP_ROOT="/mnt/storage/tmp"
DELETE_SOURCE=0
DRY_RUN=0
VERBOSE=0
ROOT_DIR="."
TEMP_DIRS=()

#############################################
# Logging utilities
#############################################
log()  { printf '[*] %s\n' "$*" >&2; }
vlog() { [[ "$VERBOSE" -eq 1 ]] && printf '[v] %s\n' "$*" >&2 || true; }
warn() { printf '[!] %s\n' "$*" >&2; }
err()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

#############################################
# Cleanup on failure
#############################################
cleanup_tempdirs() {
  for d in "${TEMP_DIRS[@]}"; do
    if [[ -n "$d" && -d "$d" ]]; then
      rm -rf -- "$d" 2>/dev/null || true
    fi
  done
}

# Register traps for full automatic cleanup
trap cleanup_tempdirs EXIT ERR INT TERM

#############################################
# Check required commands
#############################################
require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || err "Required command not found: $c"
  done
}

require_cmd find grep sed awk wc stat

detect_disc_number() {
  local s="$1"
  local disc=""

  # Normalize case
  local lower="${s,,}"

  #
  # 1. Patterns like "(Disc 1)", "(Disc One)", "(Disc Two)"
  #
  if [[ "$lower" =~ \(disc[[:space:]]*([0-9]+)\) ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi
  if [[ "$lower" =~ \(disc[[:space:]]*one\) ]]; then
    echo "1"; return
  fi
  if [[ "$lower" =~ \(disc[[:space:]]*two\) ]]; then
    echo "2"; return
  fi
  if [[ "$lower" =~ \(disc[[:space:]]*three\) ]]; then
    echo "3"; return
  fi

  #
  # 2. CD1, CD 1, cd1, etc.
  #
  if [[ "$lower" =~ cd[[:space:]]*([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi

  #
  # 3. Patterns inside filenames like "Disc One.flac"
  #
  if [[ "$lower" =~ disc[[:space:]]*([0-9]+)\. ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi

  #
  # 4. Patterns inside directories
  #
  if [[ "$lower" =~ disc[[:space:]]*([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi

  #
  # 5. TEXT versions inside filenames (rare but present)
  #
  case "$lower" in
    *"disc one"*) echo "1"; return ;;
    *"disc two"*) echo "2"; return ;;
    *"disc three"*) echo "3"; return ;;
  esac

  echo ""   # not a multi-disc release
}

has_disc_tag() {
  local s="${1,,}"   # lowercase
  s="${s//[^a-z0-9]/ }"   # replace all non-alphanumerics with spaces
  set -- $s                # tokenize by spaces: $1 $2 $3 ...

  # Loop over tokens
  for tok in "$@"; do
    case "$tok" in
      disc|disk|cd)
        # next token should be a number or text number: disc 2, cd 1, disk three
        return 0
        ;;
      disc1|disc2|disc3|disc4|disc5) return 0 ;;
      disk1|disk2|disk3|disk4|disk5) return 0 ;;
      cd1|cd2|cd3|cd4|cd5)           return 0 ;;
      one|two|three|four|five)
        # check if previous word was disc/disk/cd
        return 0
        ;;
    esac
  done

  return 1
}

#############################################
# Light filename sanitization

# Replace forbidden VFAT characters with '-'
# - Replace all dots in basename with spaces
# - Keep extension intact
# - Collapse whitespace and trim
#############################################
sanitize_filename() {
  local name="$1"
  local base ext

  if [[ "$name" == *.* ]]; then
    ext=".${name##*.}"
    base="${name%.*}"
  else
    base="$name"
    ext=""
  fi

  # Replace forbidden VFAT characters with '-'
  base="${base//:/ - }"
  base="${base//\"/}"
  base="${base//\//-}"
  base="${base//\\/}"
  base="${base//\|/-}"
  base="${base//\?/-}"
  base="${base//\*/-}"
  base="${base//</(}"
  base="${base//>/(}"

  # Replace dots with spaces
  base="${base//./ }"

  # Collapse whitespace
  base="$(printf '%s' "$base" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"

  printf '%s%s\n' "$base" "$ext"
}

#############################################
# Sanitize directory names (remove / characters)
#############################################
sanitize_dirname() {
  local s="$1"
  s="${s//\//-}"
  s="${s//\\/-}"
  s="$(printf '%s' "$s" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  printf '%s\n' "$s"
}

#############################################
# CUE metadata extraction
#############################################
CUE_ARTIST=""
CUE_ALBUM=""
CUE_YEAR=""

extract_cue_metadata() {
  local cue="$1"
  local line

  CUE_ARTIST=""
  CUE_ALBUM=""
  CUE_YEAR=""

  # Artist
  if line=$(grep -m1 -E '^[[:space:]]*PERFORMER[[:space:]]*"' "$cue" || true); then
    CUE_ARTIST=$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*PERFORMER[[:space:]]*"(.*)".*/\1/')
  fi

  # Album title (first TITLE)
  if line=$(grep -m1 -E '^[[:space:]]*TITLE[[:space:]]*"' "$cue" || true); then
    CUE_ALBUM=$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*TITLE[[:space:]]*"(.*)".*/\1/')
  fi

  # Year from REM DATE or DATE
  if line=$(grep -m1 -E '^[[:space:]]*(REM[[:space:]]+DATE|DATE)[[:space:]]+[0-9]{4}' "$cue" || true); then
    CUE_YEAR=$(printf '%s\n' "$line" | sed -E 's/.*([0-9]{4}).*/\1/')
  fi
}

#############################################
# Select and validate temp root dir
#############################################
select_temp_root() {
  local t

  if [[ -n "$TEMP_ROOT" ]]; then
    t="$TEMP_ROOT"
  elif [[ -n "${TMPDIR:-}" ]]; then
    t="$TMPDIR"
  else
    t="/tmp"
  fi

  [[ -d "$t" ]] || err "Temp dir '$t' does not exist"
  [[ -w "$t" ]] || err "Temp dir '$t' not writable"

  printf '%s\n' "$t"
}

#############################################
# Ensure output dir exists and is writable
#############################################
ensure_writable_dir() {
  local d="$1"

  if [[ ! -d "$d" ]]; then
    if ! mkdir -p "$d" 2>/dev/null; then
      err "Cannot create output directory: $d"
    fi
  fi
  [[ -w "$d" ]] || err "Output directory not writable: $d"
}

#############################################
# Determine output directory
#############################################
compute_output_dir() {
  local audio_dir="$1"
  local cue="$2"
  local audio="$3"

  extract_cue_metadata "$cue"

  local artist="${CUE_ARTIST:-Unknown Artist}"
  local album="${CUE_ALBUM:-Unknown Album}"
  local year="$CUE_YEAR"

  #
  # Detect disc number from:
  #  - audio filename
  #  - cue filename
  #  - directory name
  #
  local disc=""
  disc=$(detect_disc_number "$audio")
  [[ -z "$disc" ]] && disc=$(detect_disc_number "$cue")
  [[ -z "$disc" ]] && disc=$(detect_disc_number "$audio_dir")

  #
  # Build base folder name
  #
  local folder=""
  if [[ -n "$year" ]]; then
    folder="$artist - $year - $album"
  else
    folder="$artist - $album"
  fi

  #
  # Append disc suffix ("(Disc 1)")
  #
  if [[ -n "$disc" ]]; then
    # Add "(Disc X)" only if folder does not already contain disc info
    if ! has_disc_tag "$folder"; then
      folder="$folder (Disc $disc)"
    fi
  fi

  folder=$(sanitize_dirname "$folder")

  #
  # Output root handling
  #
  if [[ -z "$OUTPUT_ROOT" ]]; then
    [[ -w "$audio_dir" ]] || err "Source directory '$audio_dir' is read-only. Use -o DIR."
    printf '%s\n' "$audio_dir/$folder"
  else
    printf '%s/%s\n' "$OUTPUT_ROOT" "$folder"
  fi
}

#############################################
# Count number of audio TRACKS in cue
#############################################
count_tracks_in_cue() {
  grep -E '^[[:space:]]*TRACK[[:space:]][0-9]{2}[[:space:]]+AUDIO' "$1" | wc -l
}

#############################################
# Move & sanitize split files → target dir
#############################################
move_and_sanitize_files() {
  local split="$1"
  local target="$2"
  local pattern="$3"

  ensure_writable_dir "$target"

  shopt -s nullglob
  local f bn clean dest
  for f in "$split"/$pattern; do
    bn=$(basename "$f")
    clean=$(sanitize_filename "$bn")
    dest="$target/$clean"

    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "DRY-RUN: mv -f '$f' '$dest'"
    else
      vlog "Moving '$f' → '$dest'"
      mv -f -- "$f" "$dest"
    fi
  done
  shopt -u nullglob
}

#############################################
# Process a matched audio + cue pair
#############################################
process_pair() {
  local audio="$1"
  local cue="$2"

  local dir file ext stem outdir tempbase splitdir

  dir=$(dirname "$audio")
  file=$(basename "$audio")
  ext="${file##*.}"
  ext="${ext,,}"       # lower-case extension
  stem="${file%.*}"

  log "Processing:"
  log "  Audio: $audio"
  log "  Cue:   $cue"
  log "  Type:  $ext"

  ###########################################
  # Create output dir
  ###########################################
  outdir=$(compute_output_dir "$dir" "$cue" "$audio")
  log "  Output: $outdir"

  ###########################################
  # Create safe temporary split dir
  ###########################################
  tempbase=$(select_temp_root)
  splitdir=$(mktemp -d "$tempbase/cuesplit.XXXXXX")
  TEMP_DIRS+=("$splitdir")   # register for cleanup
  log "  Temp:   $splitdir"

  ###########################################
  # Split audio
  ###########################################
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: would split '$audio'"
  else
    case "$ext" in
      flac|ape|wav|wv|tta)
        require_cmd shnsplit flac
        log "  Splitting (lossless)…"
        shnsplit -d "$splitdir" -f "$cue" \
          -o "flac flac -V --best -o %f -" \
          "$audio" \
          -t "%n %p - %t"
        ;;
      mp3|ogg)
        require_cmd mp3splt
        log "  Splitting (mp3/ogg)…"
        mp3splt -d "$splitdir" -o "@n. @p - @t" -c "$cue" "$audio"
        ;;
      *)
        warn "Unsupported format '$ext'"
        return
        ;;
    esac

    # Remove pregap track(s)
    rm -f "$splitdir"/00.*pregap* "$splitdir"/00*pregap* 2>/dev/null || true
  fi

  ###########################################
  # Tagging
  ###########################################
  if [[ "$DRY_RUN" -eq 0 ]] && command -v cuetag >/dev/null 2>&1; then
    case "$ext" in
      mp3)
        compgen -G "$splitdir/*.mp3" >/dev/null && cuetag "$cue" "$splitdir"/*.mp3
        ;;
      ogg)
        compgen -G "$splitdir/*.ogg" >/dev/null && cuetag "$cue" "$splitdir"/*.ogg
        ;;
      *)
        compgen -G "$splitdir/*.flac" >/dev/null && cuetag "$cue" "$splitdir"/*.flac
        ;;
    esac
  fi

  ###########################################
  # Move files to destination
  ###########################################
  case "$ext" in
    mp3) move_and_sanitize_files "$splitdir" "$outdir" "*.mp3" ;;
    ogg) move_and_sanitize_files "$splitdir" "$outdir" "*.ogg" ;;
    *)   move_and_sanitize_files "$splitdir" "$outdir" "*.flac" ;;
  esac

  ###########################################
  # Clean temp directory
  ###########################################
  if [[ "$DRY_RUN" -eq 0 ]]; then
    rm -rf -- "$splitdir"
    TEMP_DIRS=("${TEMP_DIRS[@]/$splitdir}")
  fi

  ###########################################
  # Optionally delete source
  ###########################################
  if [[ "$DELETE_SOURCE" -eq 1 ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "DRY-RUN: would delete '$audio'"
    else
      rm -f -- "$audio"
    fi
  fi

  log "Done.\n"
}

#############################################
# Walk directory tree and find audio files
#############################################
process_tree() {
  local root="$1"

  log "Scanning under: $root"

  while IFS= read -r -d '' audio; do
    local dir file ext stem base fallback_stem cue1 cue2 cue

    dir=$(dirname "$audio")
    file=$(basename "$audio")

    # extract audio extension e.g. flac, wav, ape...
    ext="${file##*.}"
    ext="${ext,,}"

    # remove only the audio extension (NOT ".cue" yet)
    stem="${file%.*}"              # e.g. "Album.cue" from "Album.cue.flac"
    base="$stem"

    # First attempt:
    #   If audio = A.B.ext
    #   Try cue = A.B.cue
    cue1="$dir/$base.cue"

    # Second attempt (fallback):
    #   If base ends with ".cue", strip it:
    #   A.cue --> A
    fallback_stem="$base"
    if [[ "$fallback_stem" == *.cue ]]; then
      fallback_stem="${fallback_stem%.*}"
    fi
    cue2="$dir/$fallback_stem.cue"

    # Select cue file according to rules:
    # 1) Prefer exact prefix-match (cue1)
    # 2) Else fallback (cue2)
    if [[ -f "$cue1" ]]; then
      cue="$cue1"
    elif [[ -f "$cue2" ]]; then
      cue="$cue2"
    else
      vlog "Skipping '$audio' — no matching cue ('$cue1' or '$cue2')"
      continue
    fi

    process_pair "$audio" "$cue"

  done < <(
    find "$root" -type f \( \
        -name '*.flac' -o \
        -name '*.ape'  -o \
        -name '*.wav'  -o \
        -name '*.wv'   -o \
        -name '*.tta'  -o \
        -name '*.mp3'  -o \
        -name '*.ogg' \
      \) -print0
  )
}

#############################################
# CLI usage
#############################################
usage() {
  cat <<EOF
Usage: ${0##*/} [OPTIONS] [ROOT_DIR]

Options:
  -o, --output DIR      Output root directory.
      --temp-dir DIR    Use DIR for temporary split dirs.
      --delete-source   Delete source audio files after splitting.
  -n, --dry-run         Do not modify anything; show operations.
  -v, --verbose         Verbose logging.
  -h, --help            Show this help.

If no output directory is specified, tracks are placed next
to audio files — but only if the directory is writable.

Cue selection priorities for File.ext:
   1. File.ext.cue
   2. File.cue
EOF
}

#############################################
# Parse arguments
#############################################
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o|--output)
        OUTPUT_ROOT="$2"
        shift 2
        ;;
      --temp-dir)
        TEMP_ROOT="$2"
        shift 2
        ;;
      --delete-source)
        DELETE_SOURCE=1
        shift
        ;;
      -n|--dry-run)
        DRY_RUN=1
        shift
        ;;
      -v|--verbose)
        VERBOSE=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        err "Unknown option: $1"
        ;;
      *)
        ROOT_DIR="$1"
        shift
        ;;
    esac
  done
}

#############################################
# Main entry
#############################################
main() {
  parse_args "$@"

  if [[ ! -d "$ROOT_DIR" ]]; then
    err "Not a directory: $ROOT_DIR"
  fi

  if [[ -n "$OUTPUT_ROOT" ]]; then
    ensure_writable_dir "$OUTPUT_ROOT"
  fi

  process_tree "$ROOT_DIR"
}

main "$@"

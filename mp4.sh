#!/usr/bin/env bash

# 0) Dependency check with install hints
REQUIRED=(ffmpeg ffprobe yt-dlp jq bc)
MISSING=()
for tool in "${REQUIRED[@]}"; do
  if ! command -v "$tool" &>/dev/null; then
    MISSING+=("$tool")
  fi
done
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "❌ Missing dependencies: ${MISSING[*]}"
  if   command -v apt-get &>/dev/null; then
    echo "Install on Debian/Ubuntu:"
    echo "  sudo apt update && sudo apt install ${MISSING[*]}"
  elif command -v brew   &>/dev/null; then
    echo "Install on macOS with Homebrew:"
    echo "  brew install ${MISSING[*]}"
  else
    echo "Please install the missing tools via your OS package manager."
  fi
  exit 1
fi

# 1) Defaults & argument parsing
TARGET_SIZE_MB=1000
RESOLUTION=""       # manual override: 360p|480p|720p|1080p
INPUT=""
CLEANUP=false       # if set, auto-delete download
PROMPT_CLEANUP=true # if true, ask before deleting

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input)       INPUT="$2";          shift 2 ;;
    -s|--target-size) TARGET_SIZE_MB="$2"; shift 2 ;;
    -r|--resolution)  RESOLUTION="$2";      shift 2 ;;
    -c|--cleanup)     CLEANUP=true
                      PROMPT_CLEANUP=false; shift ;;
    *) echo "❌ Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$INPUT" ]]; then
  echo "❌ No input provided. Use -i <URL|file>"
  exit 1
fi

IS_URL=false
DOWNLOAD_FILE=""
BASENAME=""

# 2) Fetch duration & base name
if [[ "$INPUT" =~ ^https?:// ]]; then
  IS_URL=true
  echo "🌐 Fetching metadata..."
  META=$(yt-dlp --dump-single-json "$INPUT") || {
    echo "❌ Failed to fetch metadata"; exit 1; }
  BASENAME=$(echo "$META" | jq -r .title | tr -cd '[:alnum:]-_ ')
  DURATION=$(echo "$META" | jq -r .duration)
  DURATION=${DURATION:-0}
  if (( DURATION < 1 )); then
    echo "❌ Could not determine duration"; exit 1
  fi
else
  if [[ ! -f "$INPUT" ]]; then
    echo "❌ File not found: $INPUT"; exit 1
  fi
  BASENAME=$(basename "$INPUT"); BASENAME="${BASENAME%.*}"
  DURATION=$(ffprobe -v error \
    -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 \
    "$INPUT")
  DURATION=${DURATION%.*}
  if (( DURATION < 1 )); then
    echo "❌ Could not determine file duration"; exit 1
  fi
fi

# 3) Compute video‐bitrate budget (kbps)
# total_bits = TARGET_SIZE_MB × 8 388 608
TOTAL_BITS=$(echo "$TARGET_SIZE_MB * 8192 * 1024" | bc)
VIDEO_BITRATE_KBPS=$(echo "($TOTAL_BITS / $DURATION / 1024) - 128" | bc)

if (( VIDEO_BITRATE_KBPS < 1 )); then
  echo "❌ Target size too small for a $DURATION-second video."
  exit 1
fi

# 4) Select resolution by bitrate thresholds
# Store resolution options as pure numbers (without the "p")
RESOLUTIONS=(1080 720 480 360)
THRESHOLDS=(5000 2500 1000 600)

if [[ -n "$RESOLUTION" ]]; then
  # Strip trailing "p" if present
  TARGET_HEIGHT=${RESOLUTION%p}
  echo "🎯 Manual resolution: ${TARGET_HEIGHT}p"
else
  # Default to lowest resolution
  TARGET_HEIGHT=360
  
  # Strip decimal part for comparison
  VBR_INT=$(echo "$VIDEO_BITRATE_KBPS" | sed 's/\..*//g')
  
  # Try each resolution
  for i in {0..3}; do
    res=${RESOLUTIONS[$i]}
    thresh=${THRESHOLDS[$i]}
    
    if [[ $VBR_INT -ge $thresh ]]; then
      TARGET_HEIGHT=$res
      break
    fi
  done
  
  RESOLUTION="${TARGET_HEIGHT}p"
  echo "🤖 Auto resolution: $RESOLUTION"
fi

# 5) Download (if URL) at that resolution cap
if $IS_URL; then
  echo "⬇ Downloading [height<=$TARGET_HEIGHT]..."
  yt-dlp -f "bestvideo[height<=$TARGET_HEIGHT]+bestaudio" \
    -o "${BASENAME}.%(ext)s" "$INPUT" || {
      echo "❌ Download failed"; exit 1; }
  DOWNLOAD_FILE=$(ls "${BASENAME}".* \
    | grep -Ei '\.(mp4|mkv|mov|webm)$' \
    | head -n1)
  if [[ ! -f "$DOWNLOAD_FILE" ]]; then
    echo "❌ Couldn't locate downloaded file"; exit 1
  fi
  INPUT="$DOWNLOAD_FILE"
fi

# 6) Probe actual width/height
echo "📊 Probing '$INPUT'..."
INFO=$(ffprobe -v quiet -print_format json -show_streams "$INPUT")
W=$(echo "$INFO" | jq -r '.streams[]|select(.width)|.width')
H=$(echo "$INFO" | jq -r '.streams[]|select(.height)|.height')
if [[ -z "$W" || -z "$H" ]]; then
  echo "❌ Failed to read video dimensions"; exit 1
fi

# 6b) Check source bitrate to avoid making files bigger unnecessarily
SOURCE_BITRATE=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 \
  "$INPUT")

# If ffprobe couldn't determine bitrate, calculate from filesize and duration
if [[ -z "$SOURCE_BITRATE" || "$SOURCE_BITRATE" == "N/A" ]]; then
  FILE_SIZE=$(stat -f%z "$INPUT" 2>/dev/null || stat -c%s "$INPUT" 2>/dev/null)
  if [[ -n "$FILE_SIZE" ]]; then
    # Calculate bitrate: filesize in bits / duration in seconds
    SOURCE_BITRATE=$(echo "($FILE_SIZE * 8) / $DURATION" | bc)
    echo "📊 Calculated source bitrate: $(echo "$SOURCE_BITRATE / 1000" | bc) kbps"
  else
    echo "⚠️ Couldn't determine source file size"
    SOURCE_BITRATE=999999999  # Set high to not interfere with target bitrate
  fi
else
  echo "📊 Source video bitrate: $(echo "$SOURCE_BITRATE / 1000" | bc) kbps"
fi

# Convert to kbps for comparison
SOURCE_BITRATE_KBPS=$(echo "$SOURCE_BITRATE / 1000" | bc)

# Use the lower of the two bitrates (don't increase bitrate)
if [[ -n "$SOURCE_BITRATE_KBPS" ]] && [[ "$SOURCE_BITRATE_KBPS" -lt "$VIDEO_BITRATE_KBPS" ]]; then
  echo "⚠️ Source bitrate (${SOURCE_BITRATE_KBPS} kbps) is lower than target (${VIDEO_BITRATE_KBPS} kbps)"
  echo "✅ Using source bitrate to avoid increasing file size"
  VIDEO_BITRATE_KBPS=$SOURCE_BITRATE_KBPS
fi

# 7) Downscale if source is larger
SCALE=""
if (( H > TARGET_HEIGHT )); then
  SCALE="-vf scale=-2:${TARGET_HEIGHT}"
  echo "⬇ Downscaling ${W}x${H} → $RESOLUTION"
else
  echo "✅ Keeping ${W}x${H}"
fi

# 8) Re-encode with ffmpeg - now with hardware acceleration
OUTPUT="${BASENAME}_${RESOLUTION}_${TARGET_SIZE_MB}M.mp4"
echo "🎬 Compressing → $OUTPUT"

# Detect platform and available encoders
OS=$(uname)
HW_ENCODER=""

if [[ "$OS" == "Darwin" ]]; then
  # macOS - check for VideoToolbox
  if ffmpeg -encoders 2>/dev/null | grep -q h264_videotoolbox; then
    echo "🚀 Using Apple VideoToolbox hardware acceleration"
    HW_ENCODER="-c:v h264_videotoolbox"
  fi
elif [[ "$OS" == "Linux" ]]; then
  # Linux - check for NVIDIA, VAAPI or QSV
  if ffmpeg -encoders 2>/dev/null | grep -q h264_nvenc; then
    echo "🚀 Using NVIDIA hardware acceleration"
    HW_ENCODER="-c:v h264_nvenc"
  elif ffmpeg -encoders 2>/dev/null | grep -q h264_vaapi; then
    echo "🚀 Using VAAPI hardware acceleration"
    HW_ENCODER="-c:v h264_vaapi -vaapi_device /dev/dri/renderD128"
  elif ffmpeg -encoders 2>/dev/null | grep -q h264_qsv; then
    echo "🚀 Using Intel QuickSync hardware acceleration"
    HW_ENCODER="-c:v h264_qsv"
  fi
elif [[ "$OS" =~ Windows ]]; then
  # Windows - check for NVIDIA, AMD or Intel
  if ffmpeg -encoders 2>/dev/null | grep -q h264_nvenc; then
    echo "🚀 Using NVIDIA hardware acceleration"
    HW_ENCODER="-c:v h264_nvenc"
  elif ffmpeg -encoders 2>/dev/null | grep -q h264_amf; then
    echo "🚀 Using AMD hardware acceleration"
    HW_ENCODER="-c:v h264_amf"
  elif ffmpeg -encoders 2>/dev/null | grep -q h264_qsv; then
    echo "🚀 Using Intel QuickSync hardware acceleration"
    HW_ENCODER="-c:v h264_qsv"
  fi
fi

# Use hardware encoding if available, otherwise fallback to software
if [[ -n "$HW_ENCODER" ]]; then
  ffmpeg -i "$INPUT" \
    $HW_ENCODER -b:v "${VIDEO_BITRATE_KBPS}k" \
    -c:a aac -b:a 128k \
    $SCALE -movflags +faststart "$OUTPUT" \
    || {
      echo "⚠️ Hardware encoding failed, falling back to software encoding"
      ffmpeg -i "$INPUT" \
        -c:v libx264 -b:v "${VIDEO_BITRATE_KBPS}k" \
        -c:a aac -b:a 128k \
        $SCALE -movflags +faststart "$OUTPUT" \
        || { echo "❌ ffmpeg failed"; exit 1; }
    }
else
  echo "ℹ️ Using software encoding (no hardware encoder detected)"
  ffmpeg -i "$INPUT" \
    -c:v libx264 -b:v "${VIDEO_BITRATE_KBPS}k" \
    -c:a aac -b:a 128k \
    $SCALE -movflags +faststart "$OUTPUT" \
    || { echo "❌ ffmpeg failed"; exit 1; }
fi

# Get actual output file size in MB (rounded down)
if [[ -f "$OUTPUT" ]]; then
  FILE_SIZE_BYTES=$(stat -f%z "$OUTPUT" 2>/dev/null || stat -c%s "$OUTPUT" 2>/dev/null)
  ACTUAL_SIZE_MB=$(( FILE_SIZE_BYTES / 1024 / 1024 ))

  if (( ACTUAL_SIZE_MB < TARGET_SIZE_MB )); then
    NEW_OUTPUT="${BASENAME}_${RESOLUTION}_${ACTUAL_SIZE_MB}M.mp4"
    mv "$OUTPUT" "$NEW_OUTPUT"
    OUTPUT="$NEW_OUTPUT"
    echo "ℹ️ Output file is smaller than target. Renamed to: $OUTPUT"
  fi
fi

echo "✅ Done: $OUTPUT"

# 9) Cleanup downloaded temp (if any)
if $IS_URL && $PROMPT_CLEANUP; then
  read -p "🧹 Delete temp file '$DOWNLOAD_FILE'? (Your output '$OUTPUT' is safe) [y/N]: " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    rm -f "$DOWNLOAD_FILE"; echo "🗑 Deleted temp file"
  fi
elif $IS_URL && $CLEANUP; then
  rm -f "$DOWNLOAD_FILE"; echo "🗑 Auto-deleted temp file"
fi
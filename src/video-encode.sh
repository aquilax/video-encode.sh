#!/bin/bash

set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes

# Define usage function
function usage {
  echo "Usage: $0 [-k|--keep] [--dry-run] [--recursive] INPUT_DIR [OUTPUT_DIR]"
  exit 1
}

# Parse command line arguments
KEEP=false
DRY_RUN=false
RECURSIVE=false
INPUT_DIR=""

while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -k|--keep)
      KEEP=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --recursive)
      RECURSIVE=true
      shift
      ;;
    *)
      if [ -z "$INPUT_DIR" ]; then
        INPUT_DIR="$1"
      elif [ -z "$OUTPUT_DIR" ]; then
        OUTPUT_DIR="$1"
      else
        usage
      fi
      shift
      ;;
  esac
done

if [ -z "$INPUT_DIR" ]; then
  usage
fi

if [ "$RECURSIVE" = true ]; then
  find_options=()
else
  find_options=(-maxdepth 1)
fi

size_before_total=0
size_after_total=0
stop_loop=false


# Function to handle Ctrl-C
interrupt_handler() {
  echo "Ctrl-C caught. Terminating loop on next iteration."
  stop_loop=true
}

# Set the interrupt handler
trap interrupt_handler SIGINT

# Loop through all video files in the input directory
while IFS= read -r -d '' file; do
  if "$stop_loop"; then
    break
  fi

  # Get the base filename without extension
  filename=$(basename -- "$file")
  directory=$(dirname "$file")
  filename="${filename%.*}"

  # Set the output directory to the file directory
  OUTPUT_DIR="$directory"

  if [[ ("$file" == *_x265.mp4) || ("$file" == *_x265.mkv) ]]; then
    echo "Skipping $file"
    continue
  fi

  # Determine the output file extension
  if [[ "$file" == *.mkv ]]; then
    output_ext=".mkv"
  else
    output_ext=".mp4"
  fi

  # Set the output file name and path
  output="$OUTPUT_DIR/${filename}_x265${output_ext}"

  exit_code=0
  # Re-encode the video file using FFmpeg
  if [ "$DRY_RUN" = true ]; then
    echo "> ffmpeg -nostdin -i $file -c:v libx265 -crf 28 -preset medium -c:a aac $output"
  else
    ffmpeg -nostdin -i "$file" -c:v libx265 -crf 28 -preset medium -c:a aac "$output"
    exit_code=$?
  fi

  # Check if the re-encoding process was successful
  if [ $exit_code -eq 0 ]; then
    size_before=$(stat -c%s "$file")
    size_before_total=$((size_before + size_before_total))
    size_after=$size_before

    if [ "$DRY_RUN" != true ]; then
      size_after=$(stat -c%s "$output")
    fi

    # Delete the failed attempt if it exists
    if ! $KEEP; then
      if [ "$DRY_RUN" = true ]; then
        echo "> rm -f $file"
      else
        rm -f "$file"
      fi
    fi
  else
    # Delete the failed output
    if [ "$DRY_RUN" = true ]; then
      echo "> rm -f $output"
    else
      rm -f "$output"
    fi
  fi

  size_after_total=$((size_after + size_after_total))
  reduction_ratio=$(bc -l <<< "scale=2; ($size_before - $size_after) / $size_before")
  printf "# size before: %s\tsize after: %s\treduction: %s\tfilename: %s\n" "$size_before" "$size_after" "$reduction_ratio" "$file"
done < <(find "$INPUT_DIR" "${find_options[@]}" -type f \( -iname "*.flv" -o -iname "*.wmv" -o -iname "*.mpg" -o -iname "*.mpeg" -o -iname "*.avi" -o -iname "*.mkv" -o -iname "*.mp4" \) ! -name "*_x265.mp4" ! -name "*_x265.mkv" -print0)

reduction_ratio_total=$(bc -l <<< "scale=2; ($size_before_total - $size_after_total) / $size_before_total")
printf "# totals: size before: %s\tsize after: %s\treduction: %s\n" "$size_before_total" "$size_after_total" "$reduction_ratio_total"

#!/bin/bash
set -u
shopt -s nullglob

output="timelapse.webm"
temp_dir=$(mktemp -d)

cleanup() {
  rm -rf "$temp_dir"
}
trap cleanup EXIT

i=0

mapfile -d '' images < <(
  find /srv/images/ -maxdepth 1 -type f \
    \( -name "*_corrected.jpg" -o -name "*_map.jpg" \) \
    -cmin -1440 -print0
)

if [ ${#images[@]} -eq 0 ]; then
  echo "No matching images found, skipping animation"
  exit 0
fi

mapfile -t sorted_images < <(
  printf '%s\0' "${images[@]}" |
  xargs -0 stat --format '%Y %n' |
  sort -n |
  cut -d' ' -f2-
)

for img in "${sorted_images[@]}"; do
  [ -f "$img" ] || continue

  filename=$(basename "$img")
  timestamp_raw=$(echo "$filename" | grep -oE '[0-9]{8}-[0-9]{6}' || true)

  if [ -n "$timestamp_raw" ]; then
    date_part=${timestamp_raw%-*}
    time_part=${timestamp_raw#*-}
    formatted_date="${date_part:0:4}-${date_part:4:2}-${date_part:6:2} ${time_part:0:2}:${time_part:2:2}:${time_part:4:2}"
    readable_time=$(date -d "$formatted_date" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$timestamp_raw")
  else
    readable_time="$filename"
  fi

  printf -v newname "%s/img%04d.jpg" "$temp_dir" "$i"

  convert "$img" \
    -gravity NorthWest \
    -fill yellow \
    -undercolor black \
    -pointsize 50 \
    -annotate +10+10 "$readable_time" \
    "$newname"

  ((i++))
done

frames=( "$temp_dir"/img*.jpg )
if [ ${#frames[@]} -eq 0 ]; then
  echo "No animation frames were generated, skipping timelapse"
  exit 0
fi

ffmpeg -y \
  -an \
  -framerate 2 \
  -i "$temp_dir/img%04d.jpg" \
  -vcodec libvpx-vp9 \
  -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" \
  -pix_fmt yuv420p \
  "$output"

if [ -f "$output" ]; then
  sudo mv "$output" /srv/videos/RollingAnimation.webm
else
  echo "Timelapse was not created"
  exit 0
fi

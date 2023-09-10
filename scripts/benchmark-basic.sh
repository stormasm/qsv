#!/bin/bash

# This script does some very basic benchmarks with 'qsv' using a 520mb, 41 column, 1M row 
# sample of NYC's 311 data. If it doesn't exist on your system, it will be downloaded for you.
#
# Make sure you're using a release-optimized `qsv - generated by 
# `cargo build --release --locked`; `cargo install --locked qsv`; or `cargo install --locked --path .` 
# issued from the root of your qsv git repo.
#
# This shell script has been tested on Linux, macOS and Cygwin for Windows.
# It requires 7-Zip (https://www.7-zip.org/download.html) as we need the high compression ratio
# so we don't have to deal with git-lfs to host the large compressed file on GitHub.
# On Cygwin, you also need to install `bc` and `time`.

set -e

pat="$1"
bin_name=qsv
# set sevenz_bin_name  to "7z" on Windows/Linux and "7zz" on macOS
sevenz_bin_name=7z
datazip=/tmp/NYC_311_SR_2010-2020-sample-1M.7z
data=NYC_311_SR_2010-2020-sample-1M.csv
data_idx=NYC_311_SR_2010-2020-sample-1M.csv.idx
data_to_exclude=data_to_exclude.csv
searchset_patterns=searchset_patterns.txt
commboarddata=communityboards.csv
urltemplate="http://localhost:4000/v1/search?text={Street Name}, {City}"
jql='"features".[0]."properties"."label"'


if [ ! -r "$data" ]; then
  printf "Downloading benchmarking data...\n"
  curl -sS https://raw.githubusercontent.com/wiki/jqnatividad/qsv/files/NYC_311_SR_2010-2020-sample-1M.7z > "$datazip"
  "$sevenz_bin_name" e -y "$datazip"
  "$bin_name" sample --seed 42 1000 "$data" -o "$data_to_exclude"
  printf "homeless\npark\nnoise\n" > "$searchset_patterns"
fi


commands_without_index=()
commands_with_index=()

function add_command {
  local dest_array="$1"
  local custom_name="$2"
  shift 2
  local cmd=": '$custom_name' && $@"
  
  if [[ "$dest_array" == "without_index" ]]; then
    commands_without_index+=("$cmd")
  else
    commands_with_index+=("$cmd")
  fi
}
function add_command {
  local dest_array="$1"
  shift
  local cmd="$@"
  
  if [[ "$dest_array" == "without_index" ]]; then
    commands_without_index+=("$cmd")
  else
    commands_with_index+=("$cmd")
  fi
}

function run {
  local index=
  while true; do
    case "$1" in
      --index)
        index="yes"
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  local name="$1"
  shift

  if [ -z "$index" ]; then
    add_command "without_index" "$@"
  else
    rm -f "$data_idx"
    "$bin_name" index "$data"
    add_command "with_index" "$@"
    rm -f "$data_idx"
  fi
}

# Add commands for benchmarking
run apply_op_string "$bin_name apply operations lower Agency  $data"
run apply_op_similarity "$bin_name apply operations lower,simdln Agency --comparand brooklyn --new-column Agency_sim-brooklyn_score  $data"
run apply_op_eudex "$bin_name apply operations lower,eudex Agency --comparand Queens --new-column Agency_queens_soundex  $data" 
run apply_datefmt "$bin_name apply datefmt \"Created Date\"  $data"
run apply_emptyreplace "$bin_name" apply emptyreplace \"Bridge Highway Name\" --replacement Unspecified "$data"
run count "$bin_name" count "$data"
run --index count_index "$bin_name" count "$data"
run dedup "$bin_name" dedup "$data"
run enum "$bin_name" enum "$data"
run exclude "$bin_name" exclude \'Incident Zip\' "$data" \'Incident Zip\' "$data_to_exclude"
run --index exclude_index "$bin_name" exclude \'Incident Zip\' "$data" \'Incident Zip\' "$data_to_exclude"
run explode "$bin_name" explode City "-" "$data"
run fill "$bin_name" fill -v Unspecified \'Address Type\' "$data"
run fixlengths "$bin_name" fixlengths "$data"
run flatten "$bin_name" flatten "$data"
run flatten_condensed "$bin_name" flatten "$data" --condense 50
run fmt "$bin_name" fmt --crlf "$data"
run frequency "$bin_name" frequency "$data"
run --index frequency_index "$bin_name" frequency "$data"
run frequency_selregex "$bin_name" frequency -s /^R/ "$data"
run frequency_j1 "$bin_name" frequency -j 1 "$data"
run geocode_suggest "$bin_name" geocode suggest City --new-column geocoded_city "$data"
run geocode_reverse "$bin_name" geocode reverse Location --new-column geocoded_location "$data"
run index "$bin_name" index "$data"
run join "$bin_name" join \'Community Board\' "$data" community_board "$commboarddata"
run lua "$bin_name" luau map location_empty "tonumber\(Location\)==nil" "$data"
run partition "$bin_name" partition \'Community Board\' /tmp/partitioned "$data"
run pseudo "$bin_name" pseudo \'Unique Key\' "$data"
run rename "$bin_name" rename \'unique_key,created_date,closed_date,agency,agency_name,complaint_type,descriptor,loctype,zip,addr1,street,xstreet1,xstreet2,inter1,inter2,addrtype,city,landmark,facility_type,status,due_date,res_desc,res_act_date,comm_board,bbl,boro,xcoord,ycoord,opendata_type,parkname,parkboro,vehtype,taxi_boro,taxi_loc,bridge_hwy_name,bridge_hwy_dir,ramp,bridge_hwy_seg,lat,long,loc\' "$data"
run reverse "$bin_name" reverse "$data"
run sample_10 "$bin_name" sample 10 "$data"
run --index sample_10_index "$bin_name" sample 10 "$data"
run sample_1000 "$bin_name" sample 1000 "$data"
run --index sample_1000_index "$bin_name" sample 1000 "$data"
run sample_100000 "$bin_name" sample 100000 "$data"
run --index sample_100000_index "$bin_name" sample 100000 "$data"
run sample_100000_seeded "$bin_name" sample 100000 --seed 42 "$data"
run --index sample_100000_seeded_index "$bin_name" sample --seed 42 100000 "$data"
run --index sample_25pct_index "$bin_name" sample 0.25 "$data"
run --index sample_25pct_seeded_index "$bin_name" sample 0.25 --seed 42 "$data"
run search "$bin_name" search -s \'Agency Name\' "'(?i)us'" "$data"
run search_unicode "$bin_name" search --unicode -s \'Agency Name\' "'(?i)us'" "$data"
run searchset "$bin_name" searchset "$searchset_patterns" "$data"
run searchset_unicode "$bin_name" searchset "$searchset_patterns" --unicode "$data"
run select "$bin_name" select \'Agency,Community Board\' "$data"
run select_regex "$bin_name" select /^L/ "$data"
run slice_one_middle "$bin_name" slice -i 500000 "$data"
run --index slice_one_middle_index "$bin_name" slice -i 500000 "$data"
run sort "$bin_name" sort -s \'Incident Zip\' "$data"
run sort_random_seeded "$bin_name" sort --random --seed 42 "$data"
run split "$bin_name" split --size 50000 split_tempdir "$data"
run --index split_index "$bin_name" split --size 50000 split_tempdir "$data"
run --index split_index_j1 "$bin_name" split --size 50000 -j 1 split_tempdir "$data"
run stats "$bin_name" stats "$data"
run --index stats_index "$bin_name" stats "$data"
run --index stats_index_j1 "$bin_name" stats -j 1 "$data"
run stats_everything "$bin_name" stats "$data" --everything
run stats_everything_j1 "$bin_name" stats "$data" --everything -j 1
run --index stats_everything_index "$bin_name" stats "$data" --everything
run --index stats_everything_index_j1 "$bin_name" stats "$data" --everything -j 1
run table "$bin_name" table "$data"
run transpose "$bin_name" transpose "$data"
run extsort "$bin_name" extsort "$data" test.csv
run schema "$bin_name" schema "$data"
run validate "$bin_name" validate "$data" "$schema"
run sample_10 "$bin_name" sample 10 "$data" -o city.csv
run sql "$bin_name" sqlp  "$data" city.csv "'select * from _t_1 join _t_2 on _t_1.City = _t_2.City'"


if [ ${#commands_without_index[@]} -gt 0 ]; then
  hyperfine --warmup 2 -i --export-json without_index_results.json "${commands_without_index[@]}"
fi

# Now, run hyperfine with commands_with_index and export to with_index_results.csv
if [ ${#commands_with_index[@]} -gt 0 ]; then
  hyperfine --warmup 2 -i --export-json with_index_results.json "${commands_with_index[@]}"
fi

echo "Benchmark results completed"

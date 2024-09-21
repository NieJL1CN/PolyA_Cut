#!/bin/bash

RE_POLY_A="A{5,}|T{5,}"
MIN_SEQ_LEN=40
MIN_POLYA_LEN=10

function seek_polyA_start_pos {
    seq=$1
    pos=()
    while read -r m; do
        start=${BASH_REMATCH[0]}
        end=$((start + ${#BASH_REMATCH}))
        pos+=("$start $end")
    done < <(echo "$seq" | grep -boP "$RE_POLY_A")
    echo "${pos[@]}"
}

function calc_polyA_length {
    pos=("$@")
    polyA_len=()
    for p in "${pos[@]}"; do
        read -r start end <<<"$p"
        length=$((end - start))
        polyA_len+=("$length")
    done
    echo "${polyA_len[@]}"
}

function trim_polyA {
    input_file_path=$1
    output_file_path=$2

    i=0
    pos=-1
    pos_list=()
    seq=''
    seq_len=0

    gzip -dc "$input_file_path" | while read -r buf; do
        i=$((i + 1))
        if [[ $i -eq 1 ]]; then
            seq+="$buf"
        elif [[ $i -eq 3 ]]; then
            seq+="$buf"
        elif [[ $i -eq 2 ]]; then
            pos_list=($(seek_polyA_start_pos "$buf"))
            polyA_len=($(calc_polyA_length "${pos_list[@]}"))
            pos=${#buf}
            if [[ ${#pos_list[@]} -gt 0 ]]; then
                max_polyA_len=$(IFS=$'\n'; echo "${polyA_len[*]}" | sort -nr | head -n1)
                if [[ $max_polyA_len -gt $MIN_POLYA_LEN || $(IFS=+; echo "$((${polyA_len[*]}))") -gt $(( ${#buf} / 3 )) ]]; then
                    pos=$(echo "${pos_list[0]}" | cut -d' ' -f1)
                fi
            fi
            seq+="${buf:0:pos}\n"
            seq_len=${#buf:0:pos}
        elif [[ $i -eq 4 ]]; then
            seq+="${buf:0:pos}\n"
            if [[ $seq_len -ge $MIN_SEQ_LEN ]]; then
                echo -e "$seq" >> >(gzip > "$output_file_path")
            fi
            i=0
            seq=''
            seq_len=0
            pos=-1
            pos_list=()
        fi
    done
}

function process_fastq {
    input_dpath=$1
    output_dpath=$2
    input_pattern=$3
    output_pattern=$4
    n_cpu=$5

    if [[ -f "$input_dpath" ]]; then
        trim_polyA "$input_dpath" "$output_dpath"
    else
        fq_input_fpath=($(find "$input_dpath" -name "*$input_pattern" | sort))
        for in_fpath in "${fq_input_fpath[@]}"; do
            out_fpath="${in_fpath/$input_pattern/$output_pattern}"
            trim_polyA "$in_fpath" "$out_fpath" &
            if (( $(jobs -r | wc -l) >= n_cpu )); then
                wait -n
            fi
        done
        wait
    fi
}

if [[ $# -ge 2 ]]; then
    input_dpath=$1
    output_dpath=$2
    if [[ $# -ge 5 ]]; then
        input_pattern=$3
        output_pattern=$4
        n_cpu=$5
    else
        input_pattern="*"
        output_pattern="trimmed"
        n_cpu=1
    fi
    process_fastq "$input_dpath" "$output_dpath" "$input_pattern" "$output_pattern" "$n_cpu"
else
    echo "Usage: $0 <input_dpath> <output_dpath> [input_pattern] [output_pattern] [n_cpu]"
    exit 1
fi






# bash trim_polyA.sh /path/to/input /path/to/output "*.fastq.gz" "_trimmed.fastq.gz" 4

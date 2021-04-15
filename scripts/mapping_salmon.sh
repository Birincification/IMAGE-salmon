#!/bin/bash -x

echo $@
params=("$@")

# saner programming env: these switches turn some bugs into errors
set -o errexit -o pipefail -o noclobber -o nounset

# -allow a command to fail with !’s side effect on errexit
# -use return value from ${PIPESTATUS[0]}, because ! hosed $?
! getopt --test > /dev/null 
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    echo 'I’m sorry, `getopt --test` failed in this environment.'
    exit 1
fi

OPTIONS=
LONGOPTS=index:,pdata:,samples:,out:,nthread:,log:

# -regarding ! and PIPESTATUS see above
# -temporarily store output to be able to check for errors
# -activate quoting/enhanced mode (e.g. by writing out “--options”)
# -pass arguments only via   -- "$@"   to separate them correctly
! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    # e.g. return value is 1
    #  then getopt has complained about wrong arguments to stdout
    exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

# now enjoy the options in order and nicely split until we see --
while true; do
    case "$1" in
		--index)
        	index="$2"
            shift 2
            ;;
		--pdata)
            pdata="$2"
            shift 2
            ;;
        --samples)
            samples="$2"
            shift 2
            ;;
        --out)
            out="$2"
            shift 2
            ;;
        --nthread)
            nthread="$2"
            shift 2
            ;;
		--log)
			log="$2"
			shift 2
			;;
        --)
            shift
            break
            ;;
        *)
            shift
            ;;
    esac
done

baseout=$out/SALMON
cdna="$index/salmon/cdna.fa"
index="$index/salmon/index"

dir=$(basename $out)

mkdir -p $baseout
mkdir -p $baseout/READS
mkdir -p $baseout/STAR

echo "[INFO] [Salmon] ["`date "+%Y/%m/%d-%H:%M:%S"`"] Started processing $dir"$'\n'

##create index if missing
if [[ ! -f "$index" ]]; then
	watch pidstat -dru -hlH '>>' $log/salmon_${dir}_index-$(date +%s).pidstat & wid=$!

	salmon index -t $cdna -i $index

	kill -15 $wid
fi


##fastq input
for sample in `sed '1d' $pdata | cut -f1`; do
	samplein=$samples/$sample
	sampleout=$baseout/READS/$sample
	[ -f "$sampleout" ] && echo "[INFO] [Salmon] $sampleout already exists; skipping.."$'\n' && continue
	##paired
	watch pidstat -dru -hl '>>' $log/salmon_${dir}_$sample-$(date +%s).pidstat & wid=$!

	[ -f "${samplein}_1.fastq.gz" ] &&\
		salmon quant -i $index -l A -1 ${samplein}_1.fastq.gz -2 ${samplein}_2.fastq.gz -p $nthread -o $baseout --dumpEq

	##unpaired
	[ -f "$samplein.fastq.gz" ] &&\
		salmon quant -i $index -l A -r ${samplein}.fastq.gz -p $nthread -o $baseout --dumpEq

	kill -15 $wid
done

##STAR input
for sample in `sed '1d' $pdata | cut -f1`; do
	samplein=$out/STAR/quant/${sample}Aligned.toTranscriptome.out.bam
	sampleout=$baseout/STAR/$sample
	[ -f "$sampleout" ] && echo "[INFO] [Salmon] $sampleout already exists; skipping.."$'\n' && continue
	##paired
	watch pidstat -dru -hlH '>>' $log/salmon_${dir}_${sample}_star-$(date +%s).pidstat & wid=$!

	salmon quant -t $cdna -l A -a $sample -o $sampleout -p $nthread --dumpEq

	kill -15 $wid
done

#-t [ --targets ] arg	FASTA format file containing target transcripts
#-l [ --libType ] arg	Format string describing the library type
#-a [ --alignments ] arg	input alignment (BAM) file(s)
#-p [ --threads ] arg (=8)	The number of threads to use concurrently
#--dumpEq	Dump the equivalence class counts that were computed during quasi-mapping

#/home/software/salmon-0.14.1_linux_x86_64/bin/salmon quant -t /home/indices/salmon/9606/standardchr/cdna.fa\
#		 -l IU -a output/STAR/cond1_01Aligned.toTranscriptome.out.bam\
#		 -o output/SALMON/cond1_01 -p 6 --dumpEq

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
LONGOPTS=index:,pdata:,samples:,out:,nthread:,log:,star

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

star=n
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
        --star)
            star=y
            shift
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


echo "[INFO] [Salmon] ["`date "+%Y/%m/%d-%H:%M:%S"`"] Started processing $dir"$'\n'

watch pidstat -dru -hlH '>>' $log/salmon_${dir}.$(date +%s).pidstat & wid2=$!
starter="$(date +%s)"
mkdir -p $log/salmon_$dir

##fastq input
for sample in `sed '1d' $pdata | cut -f1`; do
	samplein=$samples/$sample
	sampleout=$baseout/READS/$sample
	! [ -f "${samplein}.fastq.gz" ] && ! [ -f "${samplein}_1.fastq.gz" ] && ! [ -f "${samplein}_2.fastq.gz" ] && \
		echo "[INFO] [Salmon] No $samplein.fastq.gz or ${samplein}_(1|2).fastq.gz exists; skipping.."$'\n' && continue
	[ -f "$sampleout/quant.sf" ] && echo "[INFO] [Salmon] $sampleout already exists; skipping.."$'\n' && continue
	mkdir -p $baseout/READS

	##paired
	watch pidstat -dru -hlH '>>' $log/salmon_${dir}/$sample.$(date +%s).pidstat & wid=$!

	[ -f "${samplein}_1.fastq.gz" ] &&\
		salmon quant -i $index -l A -1 ${samplein}_1.fastq.gz -2 ${samplein}_2.fastq.gz -p $nthread -o $sampleout --dumpEq

	##unpaired
	[ -f "$samplein.fastq.gz" ] &&\
		salmon quant -i $index -l A -r ${samplein}.fastq.gz -p $nthread -o $sampleout --dumpEq

	kill -15 $wid
done
echo "$(($(date +%s)-$starter))" >> $log/salmon_${dir}.$(date +%s).runtime
kill -15 $wid2

##STAR input
if [[ "$star" = "y" ]]; then

	watch pidstat -dru -hlH '>>' $log/salmon-star_${dir}.$(date +%s).pidstat & wid2=$!
	starter="$(date +%s)"

	mkdir -p $log/salmon-star_$dir

	for sample in `sed '1d' $pdata | cut -f1`; do
		samplein=$out/STAR/quant/${sample}Aligned.toTranscriptome.out.bam
		sampleout=$baseout/STAR/$sample
		! [ -f "$samplein" ] && echo "[INFO] [Salmon] $samplein does not exists; skipping.."$'\n' && continue
		[ -f "$sampleout/quant.sf" ] && echo "[INFO] [Salmon] $sampleout already exists; skipping.."$'\n' && continue
		mkdir -p $baseout/STAR

		watch pidstat -dru -hlH '>>' $log/salmon-star_${dir}/${sample}.$(date +%s).pidstat & wid=$!

		salmon quant -t $cdna -l A -a $samplein -o $sampleout -p $nthread --dumpEq

		kill -15 $wid
	done

	echo "$(($(date +%s)-$starter))" >> $log/salmon-star_${dir}.$(date +%s).runtime
	kill -15 $wid2
fi
#-t [ --targets ] arg	FASTA format file containing target transcripts
#-l [ --libType ] arg	Format string describing the library type
#-a [ --alignments ] arg	input alignment (BAM) file(s)
#-p [ --threads ] arg (=8)	The number of threads to use concurrently
#--dumpEq	Dump the equivalence class counts that were computed during quasi-mapping

#/home/software/salmon-0.14.1_linux_x86_64/bin/salmon quant -t /home/indices/salmon/9606/standardchr/cdna.fa\
#		 -l IU -a output/STAR/cond1_01Aligned.toTranscriptome.out.bam\
#		 -o output/SALMON/cond1_01 -p 6 --dumpEq

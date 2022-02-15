#!/bin/bash
## Environments
SD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source ${SD}/parameter.txt
WD=`pwd`

#parameters
FLAG_rawbam=0
MQ=50
taskname="myPRSScall"
ref="${SD}/data/GRCh38.ALT_PRSS.fa"
export PATH=${path_to_samtools}:${path_to_bwa}:${path_to_java}:${path_to_python2}:${path_to_gatk}:${path_to_freebayes}:${path_to_snpEff}:$PATH

if [ x$1 != x ]
then
	while getopts "i:m:n:" arg
	do
		case $arg in
		i)
			rawbam=$OPTARG
			FLAG_rawbam=1
			;;
		m)
			MQ=$OPTARG
			;;
		n)
			taskname=$OPTARG
			;;
		?)
			echo "FAIL: Unknown argument. Please check again."
			exit 1
			;;
		esac
	done

	#check parameters
	until [ $FLAG_rawbam -eq 1 ]
	do
		echo "FAIL: Variables uncomplete. Please check again."
		exit 1
	done

	RP="realpath "`echo $rawbam`
	rawbam=`$RP`

	#clean failed runs
	rm -r ${WD}/${taskname} 2>/dev/null
	mkdir ${WD}/${taskname}
	cd ${WD}/${taskname}
	WD=`pwd`

	#read sample list
	sampleID=`cat ${rawbam} | cut -f 1`
	samplecount=`echo ${sampleID[*]} | sed "s/ /\n/g" | wc -l`
	if [ $samplecount -eq 0 ]
		then
		echo "FAIL: Cannot find sample in list. Please check again."
		exit 1
	fi
	mkdir bamfile

	#remapping
	for id in ${sampleID[@]}
	do
		bamfile=`cat ${rawbam} | grep "^${id}	" | cut -f 2`
		#check bam & bai existence
		if [ -f "${bamfile}" ]
		then
			ln -s ${bamfile} ${WD}/bamfile/${id}.bam
		else
			echo "FAIL: Cannot find ${bamfile}. Please check again."
			exit 1
		fi
		baifile1=`echo ${bamfile} | sed "s/bam$/bai/g"`
		baifile2=`echo ${bamfile} | sed "s/$/.bai/g"`
		if [ -f "${baifile1}" ]
		then
			ln -s ${baifile1} ${WD}/bamfile/${id}.bam.bai
		elif [ -f "${baifile2}" ]
		then
			ln -s ${baifile2} ${WD}/bamfile/${id}.bam.bai
		else
			cd bamfile
			${samtools} index -b ${WD}/bamfile/${id}.bam
			cd ..
		fi
		depth=`cat ${rawbam} | grep "^${id}	" | cut -f 3`
		if [ ${depth} == "U" ]
		then
			${python27} ${SD}/remapping.py -s ${id} -r GRCh38 -f ${bamfile}
		else
			${python27} ${SD}/remapping.py -s ${id} -r GRCh38 -f ${bamfile} -e ${depth}
		fi

		cat ${id}/${id}.PRSS_5copy.primary_genotype.refGRCh38_ALT.remapping.bedcov.matrix.beta.txt | sed -n "2p" >> ${taskname}.remapped.list
	done

	#variant calling
	for id in ${sampleID[@]}
	do
		echo "Processing ${id}..."
		remapbam=`cat ${taskname}.remapped.list | grep "^${id}	" | cut -f 2`
		cn1=`cat ${taskname}.remapped.list | grep "^${id}	" | cut -f 3`
		cn2=`cat ${taskname}.remapped.list | grep "^${id}	" | cut -f 4`
		cn3=`cat ${taskname}.remapped.list | grep "^${id}	" | cut -f 5`
		cn4=`cat ${taskname}.remapped.list | grep "^${id}	" | cut -f 6`
		cn5=`cat ${taskname}.remapped.list | grep "^${id}	" | cut -f 7`
		echo "PRSS1_PRSS2	1	10696	"${id}"	"${cn1} >> ${taskname}_cn.txt
		echo "PRSS1_PRSS2	10697	21276	"${id}"	"${cn2} >> ${taskname}_cn.txt
		echo "PRSS1_PRSS2	21277	31853	"${id}"	"${cn3} >> ${taskname}_cn.txt
		echo "PRSS1_PRSS2	31854	41655	"${id}"	"${cn4} >> ${taskname}_cn.txt
		echo "PRSS1_PRSS2	41656	52148	"${id}"	"${cn5} >> ${taskname}_cn.txt
		echo ${remapbam} >> ${taskname}_remapbam.txt
	done

	${freebayes} -f ${ref} --region PRSS1_PRSS2:1-52148 --cnv-map ${taskname}_cn.txt -L ${taskname}_remapbam.txt -m ${MQ} --min-coverage 5 --min-alternate-fraction 0.3 --use-best-n-alleles 0 --vcf ${taskname}_PRSS.vcf

	#annotation
	${python27} ${SD}/snpEff_config.py ${path_snpEff} ${SD}/data
	${python27} ${SD}/snpEff_ann.py ${path_snpEff} ${SD}/data ${taskname}_PRSS.vcf ${taskname}_PRSS_snpEff_ann.vcf ${taskname}_PRSS_snpEff_ann.txt

	rm -r tmp bamfile

	TIMENOW=`date`
	echo ${TIMENOW}"	NGS-PRSS-call complete!"
else
	echo "usage:   NGS-PRSS-caller.sh -i [filelist] -m [num] -n [name]

Required arguments
          -i FILE  Tab-separated bam file list including *sample ID* / *bam file location* / *sample read depth* (U for unknown)

Optional arguments
          -m [num] Mapping quality (default=50)
          -n       Taskname
          
example: ./NGS-PRSS-caller.sh -i example.list -n test
"
fi

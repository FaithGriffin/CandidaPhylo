## Verions of the software used in this WDL:
##   PICARD_VER=1.782
##   GATK37_VER=3.7-93-ge9d8068
##   SAMTOOLS_VER=1.3.1
##   BWA_VER=0.7.12
##   TABIX_VER=0.2.5_r1005
##   BGZIP_VER=1.3
##
## Cromwell version support
## - Successfully tested on v28, v30 and v36
## - Does not work on versions < v23 due to output syntax


workflow CandidaPhylo {
    # input data
    String run_name

    File ref                   # path to reference file
    File ref_sa
    File ref_bwt
    File ref_amb
    File ref_ann
    File ref_pac
    File ref_dict
    File ref_index
    Array[String] input_samples
    Array[File] input_fastqs_1
    Array[File] input_fastqs_2

    # mem size/ disk size params
    Int small_mem_size_gb
    Int med_mem_size_gb
    Int large_mem_size_gb
    Int extra_large_mem_size_gb

    Int disk_size
    Int med_disk_size
    Int large_disk_size
    Int extra_large_disk_size

    String docker

    String picard_path
    String gatk_path

    # whether perform alignment or not to the input BAM files
    Boolean do_align

    # hard filtering params: both of these params are required
    String snp_filter_expr
    String indel_filter_expr

    ## TASK CALLS

    # scatter():
    # runs pipeline on each sample, in parallel (scatter-gather parallelism)
    # will produce parallelizable jobs running the same task on each input in an array
    # output: an array
    # see: https://support.terra.bio/hc/en-us/articles/360037128572-Scatter-gather-parallelism
    # see: https://github.com/openwdl/wdl/blob/main/versions/1.0/SPEC.md#scatter
    scatter(i in range(length(input_samples))) {
        String sample_name = input_samples[i]

        if (do_align) {

            call AlignAndSortBAM {
                input:
                sample_name = sample_name,
                fq1 = input_fastqs_1[i],
                fq2 = input_fastqs_2[i],

                ref = ref,
                sa = ref_sa,
                bwt = ref_bwt,
                amb = ref_amb,
                ann = ref_ann,
                pac = ref_pac,
                dict = ref_dict,
                fai = ref_index,

                docker = docker,
                mem_size_gb = small_mem_size_gb,
                disk_size = large_disk_size,
                picard_path = picard_path
            }
        }


        call MarkDuplicates {
            input:
            sample_name = sample_name,
            sorted_bam = AlignAndSortBAM.bam,

            docker = docker,
            picard_path = picard_path,
            mem_size_gb = small_mem_size_gb,
            disk_size = disk_size
        }

        call ReorderBam {
            input:
            bam = MarkDuplicates.bam,

            ref = ref,
            dict = ref_dict,

            docker = docker,
            picard_path = picard_path,
            mem_size_gb = med_mem_size_gb,
            disk_size = disk_size
        }

        call HaplotypeCaller {
            input:
            input_bam = ReorderBam.out,
            input_bam_index = ReorderBam.out_index,
            sample_name = sample_name,

            gvcf_name = "${sample_name}.g.vcf",
            gvcf_index = "${sample_name}.g.vcf.idx",

            ref = ref,
            ref_dict = ref_dict,
            ref_index = ref_index,

            mem_size_gb = med_mem_size_gb,
            disk_size = med_disk_size,
            docker = docker,
            gatk_path = gatk_path
        }
    }

    call CombineGVCFs {
        input:
        vcf_files = HaplotypeCaller.output_gvcf,
        vcf_index_files = HaplotypeCaller.output_gvcf_index,

        ref = ref,
        ref_dict = ref_dict,
        ref_index = ref_index,

        docker = docker,
        gatk_path = gatk_path,
        mem_size_gb = med_mem_size_gb,
        disk_size = disk_size
    }

    call GenotypeGVCFs {
        input:
        vcf_file = CombineGVCFs.out,
        vcf_index_file = CombineGVCFs.out_index,

        ref = ref,
        ref_dict = ref_dict,
        ref_index = ref_index,

        docker = docker,
        gatk_path = gatk_path,
        mem_size_gb = med_mem_size_gb,
        disk_size = disk_size
    }

    call HardFiltration {
        input:
        vcf = GenotypeGVCFs.output_vcf_name,
        vcf_index = GenotypeGVCFs.output_vcf_index_name,
        snp_filter_expr = snp_filter_expr,
        indel_filter_expr = indel_filter_expr,

        ref = ref,
        ref_dict = ref_dict,
        ref_index = ref_index,

        output_filename = "${run_name}.hard_filtered.vcf.gz",

        docker = docker,
        gatk_path = gatk_path,
        mem_size_gb = extra_large_mem_size_gb,
        disk_size = extra_large_disk_size
    }

    output {
        File gvcf = HardFiltration.out
    }
}


## TASK DEFINITIONS
# see run time attributes: https://cromwell.readthedocs.io/en/stable/RuntimeAttributes/

# aligns the fastq reads given the reference file (using bwa and samtools)
# and sorts the BAM file by coordinate (using picard)
# see: http://bio-bwa.sourceforge.net/bwa.shtml
# see: https://gatk.broadinstitute.org/hc/en-us/articles/360040098192-SortSam-Picard-
# see: https://www.biostars.org/p/368858/
task AlignAndSortBAM {
    String sample_name

    File fq1
    File fq2

    File ref
    File dict
    File amb
    File ann
    File bwt
    File fai
    File pac
    File sa

    Int disk_size
    Int mem_size_gb
    String docker
    String picard_path

    String read_group = "'@RG\\tID:FLOWCELL_${sample_name}\\tSM:${sample_name}\\tPL:ILLUMINA\\tLB:LIB_${sample_name}'"
    command {
        bwa mem -R ${read_group} ${ref} ${fq1} ${fq2} | samtools view -bS -> ${sample_name}.aligned.bam
        java -Xmx${mem_size_gb}G -jar ${picard_path} SortSam I=${sample_name}.aligned.bam O=${sample_name}.sorted.bam SO=coordinate
    }

    output {
        File bam = "${sample_name}.sorted.bam"
    }

    runtime {
        task_name: "AlignBAM"
        preemptible: 5
        docker: docker
        memory: mem_size_gb + " GB"
        disks: "local-disk "+ disk_size + " HDD"
    }

    parameter_meta {
        ref: "fasta file of reference genome"
        sample_name: "The name of the sample as indicated by the 1st column of the gatk.samples_file json input."
        fq_array: "An array containing the paths to the first and second fastq files."
        read_group: "The read group string that will be included in the bam header."
    }
}

# marks duplicate reads in BAM file
# see: https://gatk.broadinstitute.org/hc/en-us/articles/360037052812-MarkDuplicates-Picard-
task MarkDuplicates {
    File sorted_bam
    String sample_name

    Int disk_size
    Int mem_size_gb
    String docker
    String picard_path

    Int cmd_mem_size_gb = mem_size_gb - 1

    command {
        java -Xmx${mem_size_gb}G -jar ${picard_path} MarkDuplicates \
            I=${sorted_bam} \
            O=${sample_name}.marked_duplicates.bam \
            M=${sample_name}.marked_duplicates.metrics
    }

    output {
        File bam = "${sample_name}.marked_duplicates.bam"
    }

    runtime {
        preemptible: 3
        docker: docker
        memory: mem_size_gb + " GB"
        disks: "local-disk " + disk_size + " HDD"
    }
}


# reorder and index a BAM
# see: https://gatk.broadinstitute.org/hc/en-us/articles/360037426651-ReorderSam-Picard-
# see: https://gatk.broadinstitute.org/hc/en-us/articles/360037057932-BuildBamIndex-Picard-
task ReorderBam {
    File ref
    File dict
    File bam
    String bam_prefix = basename(bam, '.bam')

    Int disk_size
    Int mem_size_gb
    String docker
    String picard_path

    Int cmd_mem_size_gb = mem_size_gb - 1

    command {
        # reorder BAM
        java -Xmx${cmd_mem_size_gb}G -jar ${picard_path} ReorderSam \
            I=${bam} \
            O=${bam_prefix}.reordered.bam \
            R=${ref}

        # then index
        java -Xmx${cmd_mem_size_gb}G -jar ${picard_path} BuildBamIndex \
            I=${bam_prefix}.reordered.bam
    }

    output {
        File out = "${bam_prefix}.reordered.bam"
        File out_index = "${bam_prefix}.reordered.bai"
    }

    runtime {
        preemptible: 3
        docker: docker
        memory: mem_size_gb + " GB"
        disks: "local-disk " + disk_size + " HDD"
    }
}


# merge vcfs before genotyping
task CombineGVCFs {
    File ref
    File ref_dict
    File ref_index
    Array[File] vcf_files
    Array[File] vcf_index_files

    String gvcf_out = "combined_gvcfs.vcf.gz"
    String gvcf_out_index = "combined_gvcfs.vcf.gz.tbi"

    Int disk_size
    Int mem_size_gb
    String docker
    String gatk_path

    Int cmd_mem_size_gb = mem_size_gb - 1

    command {
        java -Xmx${cmd_mem_size_gb}G -jar ${gatk_path} \
            -T CombineGVCFs \
            -R ${ref} \
            -o ${gvcf_out} \
            --variant ${sep=" --variant " vcf_files}
    }
    output {
       File out = gvcf_out
       File out_index = gvcf_out_index
    }

    runtime {
        preemptible: 4
        docker:docker
        memory: mem_size_gb + " GB"
        disks: "local-disk " + disk_size + " HDD"
    }
}


# genotype gvcfs
task GenotypeGVCFs {
    File ref
    File ref_dict
    File ref_index
    File vcf_file
    File vcf_index_file
    String gvcf_out = "genotyped_gvcfs.vcf.gz"

    Int disk_size
    Int mem_size_gb
    String docker
    String gatk_path

    Int cmd_mem_size_gb = mem_size_gb - 1

    command {
        java -Xmx${cmd_mem_size_gb}G -jar ${gatk_path} \
            -T GenotypeGVCFs \
            -R ${ref} \
            -o ${gvcf_out} \
            --variant ${vcf_file} \
    }
    output {
        File output_vcf_name = gvcf_out
        File output_vcf_index_name = "${gvcf_out}.tbi"
    }

    runtime {
        preemptible: 4
        docker: docker
        memory: mem_size_gb + " GB"
        disks: "local-disk " + disk_size + " HDD"
    }
}

# hard-filter a vcf, if vqsr not available
# http://gatkforums.broadinstitute.org/gatk/discussion/2806/howto-apply-hard-filters-to-a-call-set
task HardFiltration {
    File ref
    File vcf
    File vcf_index
    File ref_dict
    File ref_index
    String output_filename

    String snp_filter_expr
    String indel_filter_expr

    Int disk_size
    Int mem_size_gb
    String docker
    String gatk_path

    Int cmd_mem_size_gb = mem_size_gb - 1

    command {
        # select snps
        java -Xmx${cmd_mem_size_gb}G -jar ${gatk_path} \
            -T SelectVariants \
            -R ${ref} \
            -V ${vcf} \
            -selectType SNP \
            -o raw_snps.g.vcf

        # filter snps
        java -Xmx${cmd_mem_size_gb}G -jar ${gatk_path} \
            -T VariantFiltration \
            -R ${ref} \
            -V ${vcf} \
            --filterExpression "${snp_filter_expr}" \
            --filterName "snp_filter" \
            -o filtered_snps.g.vcf

        # select indels
        java -Xmx${cmd_mem_size_gb}G -jar ${gatk_path}\
            -T SelectVariants \
            -R ${ref} \
            -V ${vcf} \
            -selectType INDEL \
            -o raw_indels.g.vcf

        # filter indels
        java -Xmx${cmd_mem_size_gb}G -jar ${gatk_path} \
            -T VariantFiltration \
            -R ${ref} \
            -V ${vcf} \
            --filterExpression "${indel_filter_expr}" \
            --filterName "indel_filter" \
            -o filtered_indels.g.vcf

        # combine variants
        java -Xmx${cmd_mem_size_gb}G -jar ${gatk_path}\
            -T CombineVariants \
            -R ${ref} \
            --variant filtered_snps.g.vcf \
            --variant filtered_indels.g.vcf \
            -o ${output_filename} \
            --genotypemergeoption UNSORTED
    }

    output {
        File out = "${output_filename}"
    }

    runtime {
        preemptible: 3
        docker:docker
        memory: mem_size_gb + " GB"
        disks: "local-disk " + disk_size + " HDD"
    }
}


# run haplotype caller
task HaplotypeCaller {
  File input_bam
  File input_bam_index

  String gvcf_name
  String gvcf_index

  File ref_dict
  File ref
  File ref_index
  String sample_name

  Int disk_size
  Int mem_size_gb
  Int cmd_mem_size_gb = mem_size_gb - 1

  String docker
  String gatk_path

  String out = "${sample_name}.g.vcf"

  command {
    java -Xmx${cmd_mem_size_gb}G -jar ${gatk_path} \
      -T HaplotypeCaller \
      -R ${ref} \
      -I ${input_bam} \
      -o ${gvcf_name} \
      -ERC "GVCF" \
      -ploidy 2 \
      -variant_index_type LINEAR \
      -variant_index_parameter 128000 \
      --read_filter OverclippedRead
  }

  output {
      #To track additional outputs from your task, please manually add them below
      File output_gvcf = "${gvcf_name}"
      File output_gvcf_index = "${gvcf_index}"
  }

  runtime {
    task_name: "HaplotypeCaller"
    preemptible: 3
    docker: docker
    memory: mem_size_gb + " GB"
    disks: "local-disk " + disk_size + " HDD"
  }

  parameter_meta {
      gatk: "Executable jar for the GenomeAnalysisTK"
      ref: "fasta file of reference genome"
      sample_name: "The name of the sample as indicated by the 1st column of the gatk.samples_file json input."
      in_bam: "The bam file to call HaplotypeCaller on."
      out: "VCF file produced by haplotype caller."
  }
}

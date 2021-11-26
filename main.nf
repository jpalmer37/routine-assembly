#!/usr/bin/env nextflow

import java.time.LocalDateTime

nextflow.enable.dsl = 2

include { hash_files } from './modules/hash_files.nf'
include { fastp } from './modules/fastp.nf'
include { fastp_json_to_csv } from './modules/fastp.nf'
include { shovill } from './modules/shovill.nf'
include { unicycler } from './modules/unicycler.nf'
include { prokka } from './modules/prokka.nf'
include { bakta } from './modules/bakta.nf'
include { quast } from './modules/quast.nf'
include { parse_quast_report } from './modules/quast.nf'
include { pipeline_provenance } from './modules/provenance.nf'
include { collect_provenance } from './modules/provenance.nf'


workflow {
  ch_start_time = Channel.of(LocalDateTime.now())
  ch_pipeline_name = Channel.of(workflow.manifest.name)
  ch_pipeline_version = Channel.of(workflow.manifest.version)

  ch_pipeline_provenance = pipeline_provenance(ch_pipeline_name.combine(ch_pipeline_version).combine(ch_start_time))

  if (params.samplesheet_input != 'NO_FILE') {
    ch_fastq = Channel.fromPath(params.samplesheet_input).splitCsv(header: true).map{ it -> [it['ID'], it['R1'], it['R2']] }
  } else {
    ch_fastq = Channel.fromFilePairs( params.fastq_search_path, flat: true ).map{ it -> [it[0].split('_')[0], it[1], it[2]] }.unique{ it -> it[0] }
  }

  run_shovill = params.unicycler ? false : true
  run_unicycler = run_shovill ? false : true
  run_prokka = params.bakta ? false : true
  run_bakta = run_prokka ? false : true

  main:
    hash_files(ch_fastq.map{ it -> [it[0], [it[1], it[2]]] }.combine(Channel.of("fastq-input")))

    fastp(ch_fastq)
    fastp_json_to_csv(fastp.out.json)

    if (run_shovill) {
      ch_assembly = shovill(fastp.out.trimmed_reads).assembly
    } else {
      ch_assembly = unicycler(fastp.out.trimmed_reads).assembly
    }

    if (run_prokka) {
      prokka(ch_assembly)
    } else if (run_bakta) {
      bakta(ch_assembly)
    }

    quast(ch_assembly)
    parse_quast_report(quast.out.tsv)
    
    ch_provenance = fastp.out.provenance
    
    if (run_shovill) {
      ch_provenance = ch_provenance.join(shovill.out.provenance).map{ it -> [it[0], [it[1], it[2]]] }
    }
    if (run_unicycler) {
      ch_provenance = ch_provenance.join(unicycler.out.provenance).map{ it -> [it[0], [it[1], it[2]]] }
    }
    if (run_prokka) {
      ch_provenance = ch_provenance.join(prokka.out.provenance).map{ it -> [it[0], it[1] << it[2]] }
    }
    if (run_bakta) {
      ch_provenance = ch_provenance.join(bakta.out.provenance).map{ it -> [it[0], it[1] << it[2]] }
    }
    ch_provenance = ch_provenance.join(quast.out.provenance).map{ it -> [it[0], it[1] << it[2]] }

    ch_provenance = ch_provenance.join(hash_files.out.provenance).map{ it -> [it[0], it[1] << it[2]] }
    ch_provenance = ch_provenance.join(ch_fastq.map{ it -> it[0] }.combine(ch_pipeline_provenance)).map{ it -> [it[0], it[1] << it[2]] }
    collect_provenance(ch_provenance)
}

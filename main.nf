#!/usr/bin/env nextflow

/*
 * nf-params-probe -- FD-7826
 *
 * Prints, for every probe parameter, whether the key reached Nextflow at all
 * and what value it holds. Distinguishing ABSENT from null is the whole point:
 * a key that never arrived falls back to nextflow.config, whereas a key that
 * arrived holding null overwrites nextflow.config silently.
 *
 * Note on the baseline: Nextflow itself never reads nextflow_schema.json, so
 * running this pipeline from the CLI without a params file applies no schema
 * defaults at all. The schema defaults you see in a Platform run are put there
 * by the launch form. That is exactly the machinery under test.
 */

import groovy.json.JsonOutput

// name : [ value in nextflow.config, value in the schema, what a correct launch should yield ]
def MATRIX = [
    p1_config_only     : ["'CONFIG'", 'not present',          'CONFIG'],
    p2_config_null     : ['null',     "default 'SCHEMA'",     'SCHEMA'],
    p3_agree           : ["'CONFIG'", "default 'CONFIG'",     'CONFIG'],
    p4_disagree        : ["'CONFIG'", "default 'SCHEMA'",     'SCHEMA'],
    p5_config_only_null: ['null',     'not present',          null    ],
    p6_schema_only     : ['not set',  "default 'SCHEMA'",     'SCHEMA'],
    p7_user_input      : ["''",       'required, no default', '<typed>'],
]

// containsKey() does not trigger the "Access to undefined parameter" warning,
// so we can ask "did this key arrive?" without polluting the log.
def received = { String name ->
    if( !params.containsKey(name) ) return 'ABSENT'
    final v = params[name]
    if( v == null )  return 'null'
    if( v == '' )    return "''"
    return v.toString()
}

def verdict = { String name, String got, expected ->
    if( expected == '<typed>' )              return got == 'ABSENT' || got == "''" ? 'not set' : 'ok'
    if( expected == null )                   return got == 'null' ? 'ok (null by design)' : "unexpected: ${got}"
    if( got == expected )                    return 'ok'
    if( got == 'null' )                      return 'NULLED  <-- params file carried an explicit null'
    if( got == 'ABSENT' )                    return 'ABSENT  <-- schema default never applied'
    return "differs (expected ${expected})"
}

workflow {
    log.info ''
    log.info '=' * 100
    log.info ' nf-params-probe'
    log.info '=' * 100
    log.info " Command line : ${workflow.commandLine}"
    log.info " Profiles     : ${workflow.profile}"
    log.info " Config files : ${workflow.configFiles.join(', ')}"
    log.info ''
    log.info String.format(' %-20s %-11s %-22s %-9s %s', 'Parameter', 'In config', 'In schema', 'Received', 'Verdict')
    log.info ' ' + '-' * 98

    MATRIX.each { name, row ->
        final got = received(name)
        log.info String.format(' %-20s %-11s %-22s %-9s %s', name, row[0], row[1], got, verdict(name, got, row[2]))
    }

    log.info ''
    log.info ' Full params map as Nextflow resolved it:'
    log.info JsonOutput.prettyPrint(JsonOutput.toJson(params.subMap(params.keySet().sort())))
    log.info '=' * 100
    log.info ''

    // The symptom under investigation: a null in a publishDir path silently
    // writes to the head node's local disk instead of the intended bucket.
    // failOnError:false keeps that illustrative rather than fatal, so the
    // table above always survives even when the path is nonsense.
    log.info " publishDir would resolve to: ${params.p2_config_null}/probe-reports"
    log.info ''

    WRITE_REPORT( MATRIX.collect { n, r -> "${n} = ${received(n)}" }.join('\n') )
}

process WRITE_REPORT {
    publishDir "${params.p2_config_null}/probe-reports", mode: 'copy', failOnError: false

    input:
    val report

    output:
    path 'params-probe.txt'

    script:
    """
    cat <<'EOF' > params-probe.txt
${report}
EOF
    """
}

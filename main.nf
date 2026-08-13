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
 * running this from the CLI without a params file applies no schema defaults
 * at all. The schema defaults you see in a Platform run are put there by the
 * launch form. That is exactly the machinery under test.
 *
 * Written in the conservative subset of the language that both the v1 parser
 * (Nextflow 25.x and earlier) and the strict v2 parser (26.x) accept.
 */

// [ name, value in nextflow.config, value in the schema, what a correct launch yields ]
def probeMatrix() {
    return [
        ['p1_config_only',      "'CONFIG'", 'not present',          'CONFIG'],
        ['p2_config_null',      'null',     "default 'SCHEMA'",     'SCHEMA'],
        ['p3_agree',            "'CONFIG'", "default 'CONFIG'",     'CONFIG'],
        ['p4_disagree',         "'CONFIG'", "default 'SCHEMA'",     'SCHEMA'],
        ['p5_config_only_null', 'null',     'not present',          'NULL_BY_DESIGN'],
        ['p6_schema_only',      'not set',  "default 'SCHEMA'",     'SCHEMA'],
        ['p7_user_input',       "''",       'required, no default', 'ANYTHING'],
        ['p8_profile_only',     'profile only', 'not present',      'REPORT_ONLY'],
        ['p9_required_default', 'null',     "REQUIRED, def 'SCHEMA'", 'SCHEMA'],
    ]
}

// containsKey() does not trigger the "Access to undefined parameter" warning,
// so we can ask "did this key arrive?" without polluting the log.
def receivedValue(Map allParams, String name) {
    if( !allParams.containsKey(name) )
        return 'ABSENT'
    def v = allParams.get(name)
    if( v == null )
        return 'null'
    if( v.toString() == '' )
        return "''"
    return v.toString()
}

def verdictFor(String got, String expected) {
    if( expected == 'REPORT_ONLY' )
        return (got == 'ABSENT') ? 'absent (no profile selected?)' : "reported: ${got}"
    if( expected == 'ANYTHING' )
        return (got == 'ABSENT' || got == "''") ? 'not set' : 'ok'
    if( expected == 'NULL_BY_DESIGN' )
        return (got == 'null') ? 'ok (null by design)' : "unexpected: ${got}"
    if( got == expected )
        return 'ok'
    if( got == 'null' )
        return 'NULL    <-- schema default not applied; config null stands'
    if( got == 'ABSENT' )
        return 'ABSENT  <-- schema default never applied'
    return "differs (expected ${expected})"
}

workflow {
    main:
    def rows = probeMatrix()

    println ''
    println '=' * 100
    println ' nf-params-probe'
    println '=' * 100
    println " Command line : ${workflow.commandLine}"
    println " Profiles     : ${workflow.profile}"
    println " Nextflow     : ${nextflow.version}"
    println ''
    println String.format(' %-20s %-11s %-22s %-9s %s', 'Parameter', 'In config', 'In schema', 'Received', 'Verdict')
    println ' ' + ('-' * 98)

    def summary = []
    rows.each { row ->
        def name = row[0]
        def got = receivedValue(params, name)
        println String.format(' %-20s %-11s %-22s %-9s %s', name, row[1], row[2], got, verdictFor(got, row[3]))
        summary.add("${name} = ${got}".toString())
    }

    println ''
    println ' Keys actually present in params, with their values:'
    params.keySet().sort().each { k ->
        def v = params.get(k)
        println String.format('   %-24s %s', k, (v == null ? 'null' : "'${v}'"))
    }

    println ''
    println " publishDir would resolve to: ${params.p2_config_null}/probe-reports"
    println '=' * 100
    println ''

    // The symptom under investigation: a null in a publishDir path silently
    // writes to the head node's local disk instead of the intended bucket.
    // failOnError:false keeps that illustrative rather than fatal, so the
    // table above always survives even when the path is nonsense.
    WRITE_REPORT( summary.join('\n') )
}

process WRITE_REPORT {
    publishDir "${params.p2_config_null}/probe-reports", mode: 'copy', failOnError: false

    input:
    val report

    output:
    path 'params-probe.txt'

    script:
    """
    cat <<'PROBE_EOF' > params-probe.txt
${report}
PROBE_EOF
    """
}

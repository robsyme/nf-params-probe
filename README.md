# nf-params-probe

A pipeline that does no science. Its only job is to report, for each of its
parameters, whether the value that reached Nextflow came from `nextflow.config`,
from `nextflow_schema.json`, or from something that overwrote both.

It exists to investigate how the Seqera Platform launch form resolves parameter
defaults, and in particular how a parameter can arrive as `null`.

## Why null matters

A `null` in a `-params-file` does not fall back to `nextflow.config`. It
overwrites it, and Nextflow says nothing:

```console
$ cat nextflow.config
params { registry = 'registry.example.com' }

$ nextflow run . | grep registry
registry = registry.example.com

$ echo '{"registry": null}' > p.json && nextflow run . -params-file p.json | grep registry
registry = null
```

A key that is *absent* from the params file behaves completely differently: the
config value stands. So `ABSENT` and `null` are the two outcomes worth telling
apart, and this pipeline reports them separately.

## The parameter matrix

Each parameter sits in a different relationship to the schema.

| Parameter | `nextflow.config` | `nextflow_schema.json` | A correct launch should yield |
|---|---|---|---|
| `p1_config_only` | `'CONFIG'` | not present | `CONFIG` |
| `p2_config_null` | `null` | default `'SCHEMA'` | `SCHEMA` |
| `p3_agree` | `'CONFIG'` | default `'CONFIG'` | `CONFIG` |
| `p4_disagree` | `'CONFIG'` | default `'SCHEMA'` | `SCHEMA` |
| `p5_config_only_null` | `null` | not present | `null` |
| `p6_schema_only` | not declared | default `'SCHEMA'` | `SCHEMA` |
| `p7_user_input` | `''` | required, no default | whatever you type |

`p1_config_only` is the interesting one for the launch form: it has no schema
field, so the form has nowhere to keep it. `p2_config_null` is the other:
the config and the schema disagree about its default.

## Running it

From the CLI. Note that Nextflow never reads `nextflow_schema.json`, so no
schema defaults are applied and `p2`/`p6` are expected to come back `null` and
`ABSENT`. That is the baseline, not a bug:

```console
$ echo '{"p7_user_input":"hello"}' > p.json
$ nextflow run robsyme/nf-params-probe -params-file p.json
```

From Seqera Platform. Add it to a Launchpad, fill in `p7_user_input`, leave
everything else alone, and launch. Every row should read `ok`. Anything reading
`NULLED` or `ABSENT` is the launch form losing a value.

## Reading the output

```
 Parameter            In config   In schema              Received  Verdict
 p1_config_only       'CONFIG'    not present            null      NULLED  <-- params file carried an explicit null
 p2_config_null       null        default 'SCHEMA'       SCHEMA    ok
```

`NULLED` means the params file contained `"p1_config_only": null`, which
silently replaced the config value. `ABSENT` means the schema default was never
applied and the key never arrived at all.

To see what was actually sent, read the launch record rather than guessing:

```console
$ tw runs view -i <run-id> -w <workspace>
# or
$ GET /api/workflow/<workflowId>/launch?workspaceId=<wsId>   ->  .launch.paramsText
```

## Cost

One process, one CPU, 1 GB, a few seconds. It writes a text file and publishes
it to `${params.p2_config_null}/probe-reports`, which is deliberate: if that
parameter is `null` you get the classic `publishDir path contains a variable
with a null value` warning and the file lands on the head node's local disk.

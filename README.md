# nf-params-probe

A pipeline that does no science. Its only job is to report, for each of its
parameters, whether the value that reached Nextflow came from `nextflow.config`,
from `nextflow_schema.json`, or from something that overwrote both.

It exists to investigate how the Seqera Platform launch form resolves pipeline
parameters, and in particular how a parameter can arrive as `null`.

## The two things it demonstrates

**A schema default only exists in the browser.** Nextflow never opens
`nextflow_schema.json`. The nf-schema plugin reads it but does not apply its
defaults. Only Platform's launch form acts on `default`. So a parameter that is
`null` in `nextflow.config` and defaulted in the schema resolves correctly from
the launch form and resolves to `null` from the API, the CLI, an Action or any
other automation.

**A pasted parameters document erases what it does not name.** Paste anything
into the launch form's Params file view and click away: the form rebuilds itself
from your document, and every parameter you did not mention is dropped. At
submit, each of those is sent as an explicit `null`.

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

| Parameter | `nextflow.config` | `nextflow_schema.json` | A correct launch yields |
|---|---|---|---|
| `p1_config_only` | `'CONFIG'` | not present | `CONFIG` |
| `p2_config_null` | `null` | default `'SCHEMA'` | `SCHEMA` |
| `p3_agree` | `'CONFIG'` | default `'CONFIG'` | `CONFIG` |
| `p4_disagree` | `'CONFIG'` | default `'SCHEMA'` | `CONFIG`, see below |
| `p5_config_only_null` | `null` | not present | `null` |
| `p6_schema_only` | not declared | default `'SCHEMA'` | `SCHEMA` |
| `p7_user_input` | `''` | **required**, no default | whatever you type |
| `p8_profile_only` | set in a profile only | not present | `PROFILE-PROD` / `PROFILE-DEV` |
| `p9_required_default` | `null` | **required**, default `'SCHEMA'` | `SCHEMA` |

Three of these carry most of the signal:

- `p1_config_only` and `p8_profile_only` have **no schema field**, so the form
  has nowhere to keep them and no way to show them to a user.
- `p9_required_default` is the shape that breaks in practice: required, given a
  default in the schema, and `null` in the config. The form fills it in; nothing
  else does.
- `p4_disagree` shows precedence. A non-null config value beats a schema
  default, so the schema's `'SCHEMA'` is never seen and is effectively dead code.

## Profiles

`prod` and `dev` each set `p8_profile_only`. They exist so the profile-change
code path in the launch form is reachable.

## Running it

**From the CLI.** Nextflow never reads the schema, so no schema defaults are
applied at all and `p2`, `p6` and `p9` come back `null` or `ABSENT`. That is the
baseline, not a bug:

```console
$ echo '{"p7_user_input":"hello"}' > p.json
$ nextflow run robsyme/nf-params-probe -params-file p.json -profile prod
```

**From Seqera Platform.** Add it to a Launchpad, fill in the two required
fields, leave everything else alone, and launch. Every row should read `ok`.

To reproduce the paste behaviour, go to the Parameters step, switch to the
Params file view, paste a document naming only some parameters, click away and
launch. Everything you did not name comes back `null`.

## Reading the output

```
 Parameter            In config   In schema              Received  Verdict
 p1_config_only       'CONFIG'    not present            null      NULL    <-- schema default not applied; config null stands
 p2_config_null       null        default 'SCHEMA'       SCHEMA    ok
 p6_schema_only       not set     default 'SCHEMA'       ABSENT    ABSENT  <-- schema default never applied
```

`null` means the key arrived holding null. `ABSENT` means the key never arrived
at all and the config value stands. The probe cannot tell, from inside the run,
whether a null came from the params file or from the config declaring it null,
so the verdict does not claim to know.

## Seeing what was actually submitted

Read the launch record. This is the only trustworthy source:

```console
$ curl -s -H "Authorization: Bearer $TOWER_ACCESS_TOKEN" \
    '<api-base>/workflow/<workflowId>/launch?workspaceId=<wsId>' \
    | jq -r '.launch.paramsText'
```

The api-base is `https://api.cloud.seqera.io` on Cloud, or `https://<host>/api`
on Enterprise.

Do **not** use the run's Parameters tab or `tw runs view --params` for this.
Both show the *resolved* parameters rather than what was submitted, and both
omit null-valued parameters entirely, so a parameter that was nulled is
invisible in exactly the place you would look for it.

## Requirements and cost

One process, one CPU, 1 GB, a few seconds. A container is declared
(`quay.io/nf-core/ubuntu:20.04`) because compute environments such as Seqera
Compute containerise every task and a process without one aborts the run.

The process publishes to `${params.p2_config_null}/probe-reports` on purpose. If
that parameter is `null` you get the classic `publishDir path contains a
variable with a null value` warning and the file lands on the head node's local
disk. `failOnError: false` keeps that illustrative rather than fatal, so the
parameter table always survives.

Written in the subset of the language that both the v1 parser (Nextflow 25.x and
earlier) and the strict v2 parser (26.x) accept.

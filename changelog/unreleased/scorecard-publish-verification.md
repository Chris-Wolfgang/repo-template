type: fix

`scorecard.yaml`: results publish to scorecard.dev again — the SARIF filter moved out of the `analysis` job into a separate `upload` job, because the webapp rejects a scorecard job that contains a `run:` step.

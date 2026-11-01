# HTM.Pony

Hierarchical Temporal Memory in Pony. A port of
[htm-community/htm](https://github.com/htm-community/htm) (MIT), with the
computation arranged as actors.

## What works today

The spatial pooler runs end to end. Columns are wired to receptive fields,
overlap counts the active inputs a column is connected to, and inhibition
chooses which columns represent the input. Global and local inhibition are both
implemented, and wiring takes a seed, so a seed and an input always give the
same representation.

The same computation also runs on messages. Column shards push their votes into
a ballot box, which closes a round when every vote has arrived, when a quorum
has arrived, or when a deadline expires. A pooler coordinator inhibits the
tally and pushes the representation back to whoever asked.

## What is not written yet

Permanence learning, duty cycles and boosting. The temporal memory. The CLA
temporal pooler.

## Building

Pony 0.77 or later, with corral.

```
cd test
corral run -- ponyc --debug
./test
```

## References

- [htm-community/htm](https://github.com/htm-community/htm) — the Go
  implementation this port follows
- [Numenta](https://numenta.org/) — HTM and Sparse Distributed Representations

#### pooler-training-value

```text
8 patterns of 8 bits in 64, shown 30 times each

seed 3, in full
bits off    learning  looking
0           1.000     1.000
1           0.960     0.916
2           0.934     0.851
3           0.819     0.717

bits on     learning  looking
0           1.000     1.000
1           0.981     0.897
2           0.943     0.843
3           0.932     0.825

two different patterns share 0.284 of an answer

how much more of the answer learning kept, on 1 to 3 bits
seed        bits off  bits on
3           +0.076    +0.097
5           +0.034    +0.080
11          +0.106    +0.007
23          +0.032    -0.016
41          +0.118    +0.048
mean        +0.073    +0.043

learning kept more of the answer on 5 of 5 seeds when a pattern lost bits,
and on 4 of 5 when it gained bits it never had.
Losing bits is where the learning pays most.
```

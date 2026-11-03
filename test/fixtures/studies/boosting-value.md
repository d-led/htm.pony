#### boosting-value

```text
200 columns, 20 of them allowed to win, over five inputs of twenty bits.
No permanence moves, so only a boost can change who wins. A checkpoint is a count
of the inputs a pooler has seen.

counted: how many columns have never won

        boosting                    no boost
seed    @50      @100     @200      @50      @100     @200     
3       120      0        0         120      120      120      
5       122      0        0         122      122      122      
11      116      0        0         116      116      116      
23      116      0        0         116      116      116      
41      121      0        0         121      121      121      

after 200 inputs, columns never heard: 0.0 with boosting, 119.0 without
boosting had heard every column on 5 of 5 seeds.
without it the count cannot move: nothing but a boost changes a winner here,
so a pooler that may not boost keeps the winners it started with.
```

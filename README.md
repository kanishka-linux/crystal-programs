## Installation

```
$ brew install crystal

$ shards install
```

## Running programs

```
$ crystal run tax_calc.cr --release

$ crystal run domain_suffix.cr --release
```

## Setting  up LSP for vim/nvim editor

```
$ brew install crystalline

After that add absolute path of crystalline as a command
in the vim/nvim init/config script
```

## Benchmarks

```

$ crystal run tax_calc.cr --release

calc-tax    4.58M   (218.36ns) (± 2.37%)  576B/op  171.56× slower
calc-tax-v2 785.67M (  1.27ns) (± 2.15%)  0.0B/op          fastest
```

```
$ crystal run domain_suffix.cr --release

original-strip-domains 333.21k (3.00µs)   (± 0.76%)  2.99kB/op   4.48× slower
new-strip-domains      1.49M   (670.33ns) (± 1.66%)    976B/op        fastest

original-strip-suffix  236.46k (  4.23µs) (± 0.77%)  4.01kB/op   4.15× slower
new-strip-suffix       980.97k (  1.02µs) (± 1.68%)  1.28kB/op        fastest
```

`calc-tax-v2, new-strip-domains, new-strip-suffix are the refactored code`

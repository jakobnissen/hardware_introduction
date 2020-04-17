# What scientists must know about hardware to write fast code

This document is present both in a Jupyter Notebook (.ipynb) format and a Literate.jl (.jl) format. I recommend reading the .ipynb format. It may be rendered in your browser here on GitHub, or preferably run in Jupyter using an IJulia kernel.

### This notebook covers:
* Why you must minimize disk access
* What a CPU cache is, and how to use it effectively
* Memory alignment
* How to read assembly code and why you must do it
* Why you should reduce allocations
* SIMD vectorization
* Struct of arrays vs array of structs
* Special CPU instructions
* Function inlining
* Loop unrolling
* Branch prediction
* Multithreading
* Why GPUs are fast at some things and slow at others

### How to contribute

Pull requests (PRs) are welcome. *Please only modify the `.jl` file in your PR*. Unlike the .ipynb file, .jl files are plain text files and play much more nicely with git, making it easier to review your pull request.

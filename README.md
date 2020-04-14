# What you must know about hardware to write fast code
*A brief guide for scientific programmers*

### This notebook covers:
* Why you must minimize disk access
* What is a CPU cache, and how to use it effectively
* Memory alignment
* How to read assembly code and why you must do it
* Why you must reduce your allocations
* SIMD vectorization
* Struct of arrays vs array of structs
* Special CPU instructions
* Function inlining
* Loop Unrolling
* Branch prediction
* Multithreading
* Why GPUs are fast at some things and slow at others

### How to read this
This is a Jupyter notebook. To read it, you must have Jupyter installed. However, because version control is terrible with notebook files, the source code is a Julia script. You can convert it to a notebook using the `Literate.jl` Julia package:

1. First, install Julia. Get the official binaries from the Julia website.
2. Launch a Julia terminal.
3. Install `Literate.jl`. To do this, type `]` to go from the `julia>` prompt to the package prompt. In the package prompt, type in `add Literate`. Return to the `julia>` prompt by pressing backspace.
4. Import `Literate` by typing `using Literate`.
5. Generate the notebook by typing in: `Literate.notebook("hardware_introduction.jl", "literate_output/"; execute=false)`
6. Exit Julia by running `exit()`. You can now find the notebook in the newly created directory `literate_output`.

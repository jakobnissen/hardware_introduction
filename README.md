# What scientists must know about hardware to write fast code

This blog post is hosted on the BioJulia website: https://biojulia.net/post/hardware/

This document is written as a [Pluto notebook](https://github.com/fonsp/Pluto.jl). If you can, I recommend running the code in a Pluto notebook so you can play around with it and learn. Alternatively, read it on BioJulia's website.

PR's are welcome.

### This notebook covers:
* Why you must limit your disk read/writes
* What a CPU cache is, and how to use it effectively
* Memory alignment
* How to read assembly code and why you must do it
* Why you should reduce allocations
* Why immutable datastructures ususally are fastest
* SIMD vectorization
* Struct of arrays vs array of structs
* Specialized CPU instructions
* Function inlining
* Loop unrolling
* Branch prediction
* The effects of memory dependencies in the CPU pipeline
* Multithreading
* Why GPUs are fast at some things and slow at others

# What scientists must know about hardware to write fast code

This document is hosted at https://viralinstruction.com/posts/hardware/

It is written as a [Pluto notebook](https://plutojl.org). If you can, I recommend running the code in a Pluto notebook so you can play around with it and learn. Alternatively, you can read the HTML file in your browser.

PRs are welcome.

### This notebook covers:
* Why you must limit your disk read/writes
* What a CPU cache is, and how to use it effectively
* Memory alignment
* How to read assembly code and why you must do it
* Why you should reduce allocations
* Why immutable datastructures usually are fastest
* SIMD vectorization
* Struct of arrays vs array of structs
* Specialized CPU instructions
* Function inlining
* Loop unrolling
* Branch prediction
* The effects of memory dependencies in the CPU pipeline
* Multithreading
* Why GPUs are fast at some things and slow at others

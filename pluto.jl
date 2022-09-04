### A Pluto.jl notebook ###
# v0.19.11

using Markdown
using InteractiveUtils

# ╔═╡ 675e66aa-8aef-11eb-27be-5fe273e33297
# Load packages
begin
    using BenchmarkTools
    using PlutoUI
end

# ╔═╡ 15f5c31a-8aef-11eb-3f19-cf0a4e456e7a
md"""
# What scientists must know about hardware to write fast code

**Find this notebook at https://github.com/jakobnissen/hardware_introduction**

Programming is used in many fields of science today, where individual scientists often have to write custom code for their own projects. For most scientists, however, computer science is not their field of expertise; They have learned programming by necessity. I count myself as one of them. While we may be reasonably familiar with the *software* side of programming, we rarely have even a basic understanding of how computer *hardware* impacts code performance.

The aim of this tutorial is to give non-professional programmers a *brief* overview of the features of modern hardware that you must understand in order to write fast code. It will be a distillation of what have learned the last few years. This tutorial will use Julia because it allows these relatively low-level considerations to be demonstrated easily in a high-level, interactive language.

## What this notebook is not
#### This is not a guide to the Julia programming language
To write fast code, you must first understand your programming language and its idiosyncrasies. But this is *not* a guide to the Julia programming language. I recommend reading the [performance tips section](https://docs.julialang.org/en/v1/manual/performance-tips/) of the Julia documentation.

#### This is not an explanation of specific data structures or algorithms
Besides knowing your language, you must also know your own code to make it fast. You must understand the idea behind big-O notation, why some algorithms are faster than others, and how different data structures work internally. Without knowing *what an `Array` is*, how could you possibly optimize code making use of arrays?

This too, is outside the scope of this paper. However, I would say that as a minimum, a programmer should have an understanding of:

* How a binary integer is represented in memory
* How a floating point number is represented in memory (learning this is also necessary to understand computational inaccuracies from floating point operations, which is a must when doing scientific programming)
* The memory layout of a `String` including ASCII and UTF-8 encoding
* The basics of how an `Array` is structured, and what the difference between a dense array of e.g. integers and an array of references to objects are
* The principles behind how a `Dict` (i.e. hash table) and a `Set` works

Furthermore, I would also recommend familiarizing yourself with:

* Heaps
* Deques
* Tuples

#### This is not a tutorial on benchmarking your code
To write fast code *in practice*, it is necessary to profile your code to find bottlenecks where your machine spends the majority of the time. One must benchmark different functions and approaches to find the fastest in practice. Julia (and other languages) have tools for exactly this purpose, but I will not cover them here.
"""

# ╔═╡ 5dd2329a-8aef-11eb-23a9-7f3c325bcf74
md"""## Setting up this notebook

If you don't already have these packages installed, uncomment these lines and run them:
"""

# ╔═╡ 7490def0-8aef-11eb-19ce-4b11ce5a9328
# begin
#     using Pkg
#     Pkg.add(["BenchmarkTools", "PlutoUI"])
# end

# ╔═╡ 800d827e-8c20-11eb-136a-97a622a7c1e6
TableOfContents()

# ╔═╡ 9a24985a-8aef-11eb-104a-bd9abf0adc6d
md"""
## The basic structure of computer hardware

For now, we will work with a simplified mental model of a computer. Through this document, I will add more details to our model as they become relevant.

$$[CPU] ↔ [RAM] ↔ [DISK]$$

In this simple, uh, "diagram", the arrows represent data flow in either direction. The diagram shows three important parts of a computer:

* The central processing unit (CPU) is a chip the size of a stamp. This is where all the computation actually occurs, the brain of the computer.
* Random access memory (RAM, or just "memory") is the short-term memory of the computer. This memory requires electrical power to maintain, and is lost when the computer is shut down. RAM serves as a temporary storage of data between the disk and the CPU. Much of time spent "loading" various applications and operating systems is actually spent moving data from disk to RAM and unpacking it there. A typical consumer laptop has around $10^{11}$ bits of RAM memory.
* The disk is a mass storage unit. This data on disk persists after power is shut down, so the disk contains the long-term memory of the computer. It is also much cheaper per gigabyte than RAM, with consumer PCs having around $10^{13}$ bits of disk space.
"""

# ╔═╡ a2fad250-8aef-11eb-200f-e5f8caa57a67
md"""
## Avoid accessing disk too often
When discussing software performance, it's useful to distinguish between *throughput* and *latency*. Latency is the time it takes from something begins until it is finished. Throughput is a measure of how much stuff gets done in a set amount of time.

On the surface, the relationship between latency and throughput seems obvious: If an operation takes $N$ seconds to compute, then $1/N$ operations can be done per second. So you would think:

Naive equation: $$throughput = \frac{1}{latency}$$

In reality, it's not so simple. For example, imagine an operation that has a 1 second "warmup" before it begins, but afterwards completes in 0.1 seconds. The latency is thus 1.1 seconds, but it's throughput after the initial warmup is 10 ops/second.

Or, imagine a situation with an operation with a latency of 1 second, but where 8 operations can be run concurrently. In bulk, these operations can be run with a throughput of 8 ops/second.

One place where it's useful to distinguish between latency and throughput is when programs read from the disk. Most modern computers use a type of disk called a *solid state drive (SSD)*. In round numbers, current (2021) SSD's have latencies around 100 µs, and read/write throughputs of well over 1 GB/s. Older, or cheaper mass-storage disks are of the *hard disk drive (HDD)* type. These have latencies 100 times larger, at near 10 ms, and 10 times lower throughput of 100 MB/s.

Even the latest, fastest SSDs has latencies thousands of times slower than RAM, whose latency is below 100 nanoseconds. Disk latency is incurred whenever a read or write happen. To write fast code, you must therefore at all costs avoid repeatedly reading from, or writing to disk.

The following example serves to illustrate the difference in latency: The first function opens a file, accesses one byte from the file, and closes it again. The second function randomly accesses 1,000,000 integers from RAM.
"""

# ╔═╡ cdde6fe8-8aef-11eb-0a3c-77e28f7a2c09
md"""
Benchmarking this is a little tricky, because the *first* invocation will include the compilation times of both functions. And in the *second* invocation, your operating system will have stored a copy of the file (or *cached* the file) in RAM, making the file seek almost instant. To time it properly, run it once, then *change the file* to another not-recently-opened file, and run it again. So in fact, we should update our computer diagram:

$$[CPU] ↔ [RAM] ↔ [DISK CACHE] ↔ [DISK]$$

On my computer, finding a single byte in a file (including opening and closing the file) takes about 500 µs, and accessing 1,000,000 integers from memory takes 200 milliseconds. So RAM latency is on the order of 2,500 times lower than disk's. Therefore, repeated access to files *must* be avoided in high performance computing.

Only a few years back, SSDs were uncommon and HDD throughput was lower than today. Therefore, old texts will often warn people not to have your program depend on the disk at all for high throughput. That advice is mostly outdated today, as most programs are incapable of bottlenecking at the throughput of even cheap, modern SSDs of 1 GB/s. The advice today still stands only for programs that need *frequent* individual reads/writes to disk, where the high *latency* accumulates. In these situations, you should indeed keep your data in RAM.

The worst case for performance is if you need to read/write a large file in tiny chunks, for example one single byte at a time. In these situations, great speed improvements can be found by *buffering* the file. When  buffering, you read in larger chunks, the *buffer*, to memory, and when you want to read from the file, you check if it's in the buffer. If not, read another large chunk into your buffer from the file. This approach minimizes disk latency. Both your operating system and your programming language will make use of caches, however, sometimes [it is necessary to manually buffer your files](https://github.com/JuliaLang/julia/issues/34195).

"""

# ╔═╡ f58d428c-8aef-11eb-3127-89d729e23823
md"""
## Avoid cache misses
The RAM is faster than the disk, and the CPU in turn is faster than RAM. A CPU ticks like a clock, with a speed of about 3 GHz, i.e. 3 billion ticks per second. One "tick" of this clock is called a *clock cycle*. While this is a simplification, you may imagine that every cycle, the CPU executes a single, simple command called a *CPU instruction* which does one operation on a small piece of data. The clock speed then can serve as a reference for other timings in a computer. It is worth realizing just how quick a clock cycle is: In one cycle, a photon will travel only around 10 cm. In fact, modern CPUs are so fast that a significant constraint on their physical layout is that one must take into account the time needed for electricity to move through the wires inside them, so called wire delays.

On this scale, reading from RAM takes around 500 clock cycles. Similarly to how the high latency of disks can be mitigated by copying data to the faster RAM, data from RAM is copied to a smaller memory chip physically on the CPU, called a *cache*. The cache is faster because it is physically on the CPU chip (reducing wire delays), and because it uses a faster type of storage, static RAM, instead of the slower (but cheaper to manufacture) dynamic RAM which is what the main RAM is made of. Because the cache must be placed on the CPU, limiting its size, and because it is more expensive to produce, a typical CPU cache only contains around $10^8$ bits, around 1000 times less than RAM. There are actually multiple layers of CPU cache, but here we simplify it and just refer to "the cache" as one single thing:

$$[CPU] ↔ [CPU CACHE] ↔ [RAM] ↔ [DISK CACHE] ↔ [DISK]$$

When the CPU requests a piece of data from the RAM, say a single byte, it will first check if the memory is already in cache. If so, it will read it from there. This is much faster, usually just one or a few clock cycles, than access to RAM. If not, we have a *cache miss*, where your program will stall for around 100 nanoseconds while your computer copies data from RAM into the cache.

It is not possible, except in very low-level languages, to manually manage the CPU cache. Instead, you must make sure to use your cache effectively.

First, you strive to use as little memory as possible. With less memory, it is more likely that your data will be in cache when the CPU needs it. Remember, a CPU can do approximately 500 small operations in the time wasted by a single cache miss.

Effective use of the cache comes down to *locality*, temporal and spacial locality:
* By *temporal locality*, I mean that data you recently accessed likely resides in cache already. Therefore, if you must access a piece of memory multiple times, make sure you do it close together in time.
* By *spacial locality*, I mean that you should access data from memory addresses close to each other. Your CPU does not copy *just* the requested bytes to cache. Instead, your CPU will always copy data in larger chunks called *cache lines* (usually 512 consecutive bits, depending on the CPU model).

To illustrate this, let's compare the performance of the `random_access` function above when it's run on a short (8 KiB) vector, compared to a long (16 MiB) one. The first one is small enough that after just a few accessions, all the data has been copied to cache. The second is so large that new indexing causes cache misses most of the time.

Notice the large discrepancy in time spent - a difference of around 70x.
"""

# ╔═╡ c6da4248-8c19-11eb-1c16-093695add9a9
md"""
We can play around with the function `random_access` from before. What happens if, instead of accessing the array randomly, we access it *in the worst possible order*?

For example, we could use the following function:
"""

# ╔═╡ d4c67b82-8c1a-11eb-302f-b79c86412ce5
md"""
`linear_access` does nearly the same computation as `random_access`, but accesses every 15th element. An `UInt` in Julia is 8 bytes (64 bits), so a step size of 15 means there are $15 * 64 = 960$ bits between each element; larger than the 64 byte cache line. That means *every single* access will cause a cache miss - in contrast to `random_access` with a large vector, where only *most* accesses forces cache misses.
"""

# ╔═╡ 0f2ac53c-8c1b-11eb-3841-27f4ea1e9617
md"""
Surprise! The linear access pattern is more than 20 times faster! How can that be?

Next to the cache of the CPU lies a small circuit called the *prefetcher*. This electronic circuit collects data on which memory is being accessed by the CPU, and looks for patterns. When it detects a pattern, it will *prefetch* whatever data it predicts will soon be accessed, so that it already resides in cache when the CPU requests the data.

Our function `linear_access`, depite having worse *cache usage* than *random_access*, fetched the data in a completely predictable pattern, which allowed the prefetcher to do its job.

In summary, we have seen that
* A *cache miss* incurs a penalty equivalent to roughly 500 CPU operations, so is absolutely critical for performance to avoid these
* To reduce cache misses:
  - Use smaller data so it more easily fits in cache
  - Access data in a predicatable, regular pattern to allow the prefetcher to do its job
  - Access data close together in memory instead of far apart
  - When accessing data close together in memory, do so close together in time, so when it's accessed the second time, it's still in cache.

Cache usage has implications for your data structures. Hash tables such as `Dict`s and `Set`s are inherently cache inefficient and almost always cause cache misses, whereas arrays don't. Hence, while many operations of hash tables are $O(1)$ (i.e. they complete in constant time), their cost per operation is high.

Many of the optimizations in this document indirectly impact cache use, so this is important to have in mind.
"""

# ╔═╡ 12f1228a-8af0-11eb-0449-230ae20bfa7a
md"""
## Keep your data aligned to memory
As just mentioned, your CPU will move entire cache lines of usually 512 consecutive bits (64 bytes) to and from main RAM to cache at a time. Your entire main memory is segmented into cache lines. For example, memory addresses 0 to 63 is one cache line, addresses 64 to 127 is the next, 128 to 191 the next, et cetera. Your CPU may only request one of these cache lines from memory, and not e.g. the 64 bytes from address 30 to 93.

This means that some data structures can straddle the boundaries between cache lines. If I request a 64-bit (8 byte) integer at adress 60, the CPU must first generate two memory requests from the single requested memory address (namely to get cache lines 0-63 and 64-127), and then retrieve the integer from both cache lines, wasting time.

The time wasted can be significant. In a situation where in-cache memory access proves the bottleneck, the slowdown can approach 2x. In the following example, I use a pointer to repeatedly access an array at a given offset from a cache line boundary. If the offset is in the range `0:56`, the integers all fit within one single cache line, and the function is fast. If the offset is in `57:63` all integers will straddle cache lines.
"""

# ╔═╡ 3a1efd5a-8af0-11eb-21a2-d1011f16555c
md"The consequences of unaligned memory access are very CPU-dependent. On my current CPU, I see a ~15% performance decrease. On my old computer where I originally wrote this notebook, the penalty was around 100%. Old processors can do [even worse things](https://www.kernel.org/doc/Documentation/unaligned-memory-access.txt) - incredibly, the CPU inside the Game Boy Advance from 2001 would _silently perform a different read!_ 😱

Fortunately, the compiler does a few tricks to make it less likely that you will access misaligned data. First, Julia (and other compiled languages) always places new objects in memory at the boundaries of cache lines. When an object is placed right at the boundary, we say that it is *aligned*. Julia also aligns the beginning of larger arrays:"

# ╔═╡ 5b10a2b6-8af0-11eb-3fe7-4b78b4c22550
md"Note that if the beginning of an array is aligned, then it's not possible for 1-, 2-, 4-, or 8-byte objects to straddle cache line boundaries, and everything will be aligned.

It would still be possible for an e.g. 7-byte object to be misaligned in an array. In an array of 7-byte objects, the 10th object would be placed at byte offset $7 \times (10-1) = 63$, and the object would straddle the cache line. However, the compiler usually does not allow struct with a nonstandard size for this reason. If we define a 7-byte struct:"

# ╔═╡ 6061dc94-8af0-11eb-215a-4f3af731774e
struct AlignmentTest
    a::UInt32 # 4 bytes +
    b::UInt16 # 2 bytes +
    c::UInt8  # 1 byte = 7 bytes?
end;

# ╔═╡ 624eae74-8af0-11eb-025b-8b68dc55f31e
md"Then we can use Julia's introspection to get the relative position of each of the three integers in an `AlignmentTest` object in memory:"

# ╔═╡ d4c8c38c-8ee6-11eb-0b49-33fbfbd214f3
let
    T = AlignmentTest
    println("Size of $T: ", sizeof(T), "bytes")
    for fieldno in 1:fieldcount(T)
        print("Name: ", fieldname(T, fieldno), '\t')
        print("Size: ", sizeof(fieldtype(T, fieldno)), '\t')
        print("Offset: ", fieldoffset(T, fieldno), '\n')
    end
end

# ╔═╡ 7b979410-8af0-11eb-299c-af0a5d740c24
md"""
We can see that, despite an `AlignmentTest` only having 4 + 2 + 1 = 7 bytes of actual data, it takes up 8 bytes of memory, and accessing an `AlignmentTest` object from an array will always be aligned.

As a coder, there are only a few situations where you can face alignment issues. I can come up with two:

1. If you manually create an object with a strange size, e.g. by accessing a dense integer array with pointers. This can save memory, but will waste time. [My implementation of a Cuckoo filter](https://github.com/jakobnissen/Probably.jl) does this to save space.
2. During matrix operations. If you have a matrix the columns are sometimes unaligned because it is stored densely in memory. E.g. in a 15x15 matrix of `Float32`s, only the first column is aligned, all the others are not. This can have serious effects when doing matrix operations: [I've seen benchmarks](https://juliasimd.github.io/LoopVectorization.jl/latest/examples/matrix_vector_ops/) where an 80x80 matrix/vector multiplication is 2x faster than a 79x79 one due to alignment issues.
"""

# ╔═╡ 8802ff60-8af0-11eb-21ac-b9fdbeac7c24
md"""
## Digression: Assembly code
To run, any program must be translated, or *compiled* to CPU instructions. The CPU instructions are what is actually running on your computer, as opposed to the code written in your programming language, which is merely a *description* of the program. CPU instructions are usually presented to human beings in *assembly*. Assembly is a programming language which has a one-to-one correspondance with CPU instructions.

Viewing assembly code will be useful to understand some of the following sections which pertain to CPU instructions.

In Julia, we can easily inspect the compiled assembly code using the `code_native` function or the equivalent `@code_native` macro. We can do this for a simple function:
"""

# ╔═╡ a36582d4-8af0-11eb-2b5a-e577c5ed07e2
# View assembly code generated from this function call
function foo(x)
    s = zero(eltype(x))
    @inbounds for i in eachindex(x)
        s = x[i ⊻ s]
    end
    return s
end;

# ╔═╡ a74a9966-8af0-11eb-350f-6787d2759eba
 @code_native foo([UInt(1)])

# ╔═╡ ae9ee028-8af0-11eb-10c0-6f2db3ab8025
md"""
Let's break it down:

The lines beginning with `;` are comments, and explain which section of the code the following instructions come from. They show the nested series of function calls, and where in the source code they are. You can see that `eachindex`, calls `axes1`, which calls `axes`, which calls `size`. Under the comment line containing the `size` call, we see the first CPU instruction. The instruction name is on the far left, `movq`. The name is composed of two parts, `mov`, the kind of instruction (to move content to or from a register), and a suffix `q`, short for "quad", which means 64-bit integer. There are the following suffixes:  `b` (byte, 8 bit), `w` (word, 16 bit), `l`, (long, 32 bit) and `q` (quad, 64 bit).

The next two columns in the instruction, `24(%rdi)` and `%rax` are the arguments to `movq`. These are the names of the registers (we will return to registers later) where the data to operate on are stored.

You can also see (in the larger display of assembly code) that the code is segmented into sections beginning with a name starting with "L", for example, when I ran it, there's a section `L32`. These sections are jumped between using if-statements, or *branches*. Here, section `L32` marks the actual loop. You can see the following two instructions in the `L32` section:

```
; ││┌ @ promotion.jl:401 within `=='
     cmpq    $1, %rdi
; │└└
     jne     L32
```

The first instruction `cmpq` (compare quad) compares the data in registry `rdi`, which hold the data for the number of iterations left (plus one), with the number 1, and sets certain flags (wires) in the CPU based on the result. The next instruction `jne` (jump if not equal) makes a jump if the "equal" flag is not set in the CPU, which happens if there is one or more iterations left. You can see it jumps to `L32`, meaning this section repeat.
"""

# ╔═╡ b73b5eaa-8af0-11eb-191f-cd15de19bc38
md"""
#### Fast instruction, slow instruction
Not all CPU instructions are equally fast. Below is a table of selected CPU instructions with *very rough* estimates of how many clock cycles they take to execute. You can find much more detailed tables [in this document](https://www.agner.org/optimize/instruction_tables.pdf). Here, I'll summarize the speed of instructions on modern Intel CPUs. It's very similar for all modern CPUs.

You will see that the time is given both as latency, and reciprocal throughput (that is, $1/throughput$). The reason is that CPUs contain multiple circuits for some operations that can operate in parallel. So while float multiplication has a latency of 5 clock cycles, if 10 floating point ops can be computed in parallel in 10 different circuits, it has a throughput of 2 ops/second, and so a reciprocal throughput of 0.5.

The following table measures time in clock cycles:

|Instruction             |Latency|Rec. throughp.|
|------------------------|-------|--------------|
|move data               |  1 |  0.25
|and/or/xor              |  1 |  0.25
|test/compare            |  1 |  0.25
|do nothing              |  1 |  0.25
|int add/subtract        |  1 |  0.25
|bitshift                |  1 |  0.5
|float multiplication    |  5 |  0.5
|vector int and/or/xor   |  1 |  0.5
|vector int add/sub      |  1 |  0.5
|vector float add/sub    |  4 |  0.5
|vector float multiplic. |  5 |  0.5
|lea                     |  3 |  1
|int multiplic           |  3 |  1
|float add/sub           |  3 |  1
|float multiplic.        |  5 |  1
|float division          | 15 |  5
|vector float division   | 13 |  8
|integer division        | 50 | 40


The `lea` instruction takes three inputs, A, B and C, where A must be 1, 2, 4, or 8, and calculates AB + C. We'll come back to what the "vector" instructions do later.

For comparison, we may also add some *very rough* estimates of other sources of delays:

|Delay                  |Cycles|
|-----------------------|----|
|move memory from cache |        1
|misaligned memory read |       10
|cache miss             |      500
|read from disk         | 5000000
"""

# ╔═╡ c0c757b2-8af0-11eb-38f1-3bc3ec4c43bc
md"If you have an inner loop executing millions of times, it may pay off to inspect the generated assembly code for the loop and check if you can express the computation in terms of fast CPU instructions. For example, if you have an integer you know to be 0 or above, and you want to divide it by 8 (discarding any remainder), you can instead do a bitshift, since bitshifts are way faster than integer division:
"

# ╔═╡ c5472fb0-8af0-11eb-04f1-95a1f7b6b9e0
begin
    divide_slow(x) = div(x, 8)
    divide_fast(x) = x >>> 3;
end;

# ╔═╡ ce0e65d4-8af0-11eb-0c86-2105c26b62eb
md"However, modern compilers are pretty clever, and will often figure out the optimal instructions to use in your functions to obtain the same result, by for example replacing an integer divide `idivq` instruction with a bitshift right (`shrq`) where applicable to be faster. You need to check the assembly code yourself to see:"

# ╔═╡ d376016a-8af0-11eb-3a15-4322759143d1
# Calling it with these keywords removes comments in the assembly code
@code_native debuginfo=:none dump_module=false divide_slow(UInt(1))

# ╔═╡ d70c56bc-8af0-11eb-1220-09e78dba26f7
md"## Allocations and immutability
As already mentioned, main RAM is much slower than the CPU cache. However, working in main RAM comes with an additional disadvantage: Programs are handed a bunch of RAM by the operating system (OS) to work with. Within that chunk of memory, the program itself needs to keep track of what RAM is in use by which objects. If the program didn't keep track, the creation of one object in memory could overwrite another object, causing data loss. Therefore, every creation and destruction of data in RAM requires book-keeping, that takes time.

The creation of new objects in RAM is termed *allocation*, and the destruction is called *deallocation*. Really, the (de)allocation is not really *creation* or *destruction* per se, but rather the act of starting and stopping keeping track of the memory. Memory that is not kept track of will eventually be overwritten by other data. Allocation and deallocation take a significant amount of time depending on the size of objects, from a few tens of nanoseconds to a few microseconds per allocation.

In programming languages such as Julia, Python, R and Java, deallocation is automatically done using a program called the *garbage collector* (GC). This program keeps track of which objects are rendered unreachable by the programmer, and deallocates them. For example, if you do:"

# ╔═╡ dc24f5a0-8af0-11eb-0332-2bc0834d426c
begin
    thing = [1,2,3]
    thing = nothing
end

# ╔═╡ e3c136de-8af0-11eb-06f1-9393c0f95fbb
md"Then there is no way to get the original array `[1,2,3]` back, it is unreachable. Hence it is simply wasting RAM, and doing nothing. It is *garbage*. Allocating and deallocating objects sometimes cause the GC to start its scan of all objects in memory and deallocate the unreachable ones, which causes significant lag. You can also start the garbage collector manually:"

# ╔═╡ e836dac8-8af0-11eb-1865-e3feeb011fc4
GC.gc()

# ╔═╡ ecfd04e4-8af0-11eb-0962-f548d2eabad3
md"The following example illustrates the difference in time spent in a function that allocates a vector with the new result relative to one which simply modifies the vector, allocating nothing:"

# ╔═╡ f0e24b50-8af0-11eb-1a0e-5d925f3743e0
begin
    function increment(x::Vector{<:Integer})
        y = similar(x)
        @inbounds for i in eachindex(x)
            y[i] = x[i] + 1
        end
        return y
    end

    function increment!(x::Vector{<:Integer})
        @inbounds for i in eachindex(x)
            x[i] = x[i] + 1
        end
        return x
    end
end;

# ╔═╡ 22512ab2-8af1-11eb-260b-8d6c16762547
md"""
On my computer, the allocating function is more than 15x slower on average. Also note the high maximum time spend on the allocating function. This is due to a few properties of the code:
* First, the allocation itself takes time
* Second, the allocated objects eventually have to be deallocated, also taking time
* Third, repeated allocations triggers the GC to run, causing overhead
* Fourth, more allocations sometimes means less efficient cache use because you are using more memory

Note that I used the mean time instead of the median, since for this function the GC only triggers approximately every 30'th call, but it consumes 30-40 µs when it does. All this means performant code should keep allocations to a minimum.

The `@btime` macro, and other benchmarking tools, tell you the number of allocations. This information is given because it is assumed that any programmer who cares to benchmark their code will be interested in reducing allocations.

#### Not all objects need to be allocated
Inside RAM, data is kept on either the *stack* or the *heap*. The stack is a simple data structure with a beginning and end, similar to a `Vector` in Julia. The stack can only be modified by adding or subtracting elements from the end, analogous to a `Vector` with only the two mutating operations `push!` and `pop!`. These operations on the stack are very fast. When we talk about "allocations", however, we talk about data on the heap. Unlike the stack, the heap has an unlimited size (well, it has the size of your computer's RAM), and can be modified arbitrarily, deleting and accessing any objects. You can think of the stack like a `Vector`, and the heap like a `Dict`.

Intuitively, it may seem obvious that all objects need to be placed in RAM, must be able to be retrieved and deleted at any time by the program, and therefore need to be allocated on the heap. And for some languages, like Python, this is true. However, this is not true in Julia and other efficient, compiled languages. Integers, for example, can often be placed on the stack.

Why do some objects need to be heap allocated, while others can be stack allocated? To be stack-allocated, the compiler needs to know for certain that:

* The object is a reasonably small size, so it fits on the stack. For technical reasons, the stack can't just be hundreds of megabytes in size.
* The compiler can predict exactly *when* it needs to create and destroy the object so it can destroy it timely by simply popping the stack (similar to calling `pop!` on a `Vector`). This is usually the case for local variables in compiled languages.

Julia has even more constrains on stack-allocated objects.
* The object should have a fixed size known at compile time.
* The compiler must know that object never changes. The CPU is free to copy stack-allocated objects, and for immutable objects, there is no way to distinguish a copy from the original. This bears repeating: *With immutable objects, there is no way to distinguish a copy from the original*. This gives the compiler and the CPU certain freedoms when operating on it. The latter point is also why objects are immutable by default in Julia, and leads to one other performance tip: Use immutable objects wherever possible.

What does this mean in practice? In Julia, it means if you want fast stack-allocated objects:
* Your object must be created, used and destroyed in a fully compiled function so the compiler knows for certain when it needs to create, use and destroy the object. If the object is returned for later use (and not immediately returned to another, fully compiled function), we say that the object *escapes*, and must be allocated.
* Your type must be limited in size. I don't know exactly how large it has to be, but 100 bytes is fine.
* The exact memory layout of your type must be known by the compiler (it nearly always is).
"""

# ╔═╡ 2a7c1fc6-8af1-11eb-2909-554597aa2949
begin
    abstract type AllocatedInteger end

    struct StackAllocated <: AllocatedInteger
        x::Int
    end

    mutable struct HeapAllocated <: AllocatedInteger
        x::Int
    end
end

# ╔═╡ 2e3304fe-8af1-11eb-0f6a-0f84d58326bf
md"We can inspect the code needed to instantiate a `HeapAllocated` object with the code needed to instantiate a `StackAllocated` one:"

# ╔═╡ 33350038-8af1-11eb-1ff5-6d42d86491a3
@code_native debuginfo=:none dump_module=false HeapAllocated(1)

# ╔═╡ 3713a8da-8af1-11eb-2cb2-1957455227d0
md"Notice the `callq` instruction in the `HeapAllocated` one. This instruction calls out to other functions, meaning that in fact, much more code is really needed to create a `HeapAllocated` object that what is displayed. In constrast, the `StackAllocated` really only needs a few instructions:"

# ╔═╡ 59f58f1c-8af1-11eb-2e88-997e9d4bcc48
@code_native debuginfo=:none dump_module=false StackAllocated(1)

# ╔═╡ 5c86e276-8af1-11eb-2b2e-3386e6795f37
md"
Because immutable objects dont need to be stored on the heap and can be copied freely, immutables are stored *inline* in arrays. This means that immutable objects can be stored directly inside the array's memory. Mutable objects have a unique identity and location on the heap. They are distinguishable from copies, so cannot be freely copied, and so arrays contain reference to the memory location on the heap where they are stored. Accessing such an object from an array then means first accessing the array to get the memory location, and then accessing the object itself using that memory location. Beside the double memory access, objects are stored less efficiently on the heap, meaning that more memory needs to be copied to CPU caches, meaning more cache misses. Hence, even when stored on the heap in an array, immutables can be stored more effectively.
"

# ╔═╡ 6849d9ec-8af1-11eb-06d6-db49af4796bc
md"We can verify that, indeed, the array in the `data_stack` stores the actual data of a `StackAllocated` object, whereas the `data_heap` contains pointers (i.e. memory addresses):"

# ╔═╡ 74a3ddb4-8af1-11eb-186e-4d80402adfcf
md"## Registers and SIMD
It is time yet again to update our simplified computer schematic. A CPU operates only on data present in *registers*. These are small, fixed size slots (e.g. 8 bytes in size) inside the CPU itself. A register is meant to hold one single piece of data, like an integer or a floating point number. As hinted in the section on assembly code, each instruction usually refers to one or two registers which contain the data the operation works on:

$$[CPU] ↔ [REGISTERS] ↔ [CACHE] ↔ [RAM] ↔ [DISK CACHE] ↔ [DISK]$$

To operate on data structures larger than one register, the data must be broken up into smaller pieces that fits inside the register. For example, when adding two 128-bit integers on my computer:"

# ╔═╡ 7a88c4ba-8af1-11eb-242c-a1813a9e6741
@code_native debuginfo=:none dump_module=false UInt128(5) + UInt128(11)

# ╔═╡ 7d3fcbd6-8af1-11eb-0441-2f88a9d59966
md"""There is no register that can do 128-bit additions. First the lower 64 bits must be added using a `addq` instruction, fitting in a register. Then the upper bits are added with a `adcq` instruction, which adds the digits, but also uses the carry bit from the previous instruction. Finally, the results are moved 64 bits at a time using `movq` instructions.

The small size of the registers serves as a bottleneck for CPU throughput: It can only operate on one integer/float at a time. In order to sidestep this, modern CPUs contain specialized 256-bit registers (or 128-bit in older CPUs, or 512-bit in the brand new ones) than can hold 4 64-bit integers/floats at once, or 8 32-bit integers, etc. Confusingly, the data in such wide registers are termed "vectors." The CPU have access to instructions that can perform various CPU operations on vectors, operating on 4 64-bit integers in one instruction. This is called "single instruction, multiple data," *SIMD*, or *vectorization*. Notably, a 4x64 bit operation is *not* the same as a 256-bit operation, e.g. there is no carry-over with between the 4 64-bit integers when you add two vectors. Instead, a 256-bit vector operation is equivalent to 4 individual 64-bit operations.

We can illustrate this with the following example:"""

# ╔═╡ 8c2ed15a-8af1-11eb-2e96-1df34510e773
md"""
Here, two 8×32 bit vectors are added together in one single instruction. You can see the CPU makes use of a single `vpaddd` (vector packed add double) instruction to add 8 32-bit integers, as well as the corresponding move instruction `vmovdqu`. Note that vector CPU instructions begin with `v`.

It's worth mentioning the interaction between SIMD and alignment: If a series of 256-bit (32-byte) SIMD loads are misaligned, then up to half the loads could cross cache line boundaries, as opposed to just 1/8th of 8-byte loads. Thus, alignment is a much more serious issue when using SIMD. Since array beginnings are always aligned, this is usually not an issue, but in cases where you are not guaranteed to start from an aligned starting point, such as with matrix operations, this may make a significant difference. In brand new CPUs with 512-bit registers, the issues is even worse as the SIMD size is the same as the cache line size, so *all* loads would be misaligned if the initial load is.

SIMD vectorization of e.g. 64-bit integers may increase throughput by almost 4x, so it is of huge importance in high-performance programming. Compilers will automatically vectorize operations if they can. What can prevent this automatic vectorization?

#### SIMD needs uninterrupted iteration of fixed length
Because vectorized operations operate on multiple data at once, it is not possible to interrupt the loop at an arbitrary point. For example, if 4 64-bit integers are processed in one clock cycle, it is not possible to stop a SIMD loop after 3 integers have been processed. Suppose you had a loop like this:

```julia
for i in 1:8
    if foo()
        break
    end
    # do stuff with my_vector[i]
end
```

Here, the loop could end on any iteration due to the break statement. Therefore, any SIMD instruction which loaded in multiple integers could operate on data *after* the loop is supposed to break, i.e. data which is never supposed to be read. This would be wrong behaviour, and so, the compiler cannot use SIMD instructions.

A good rule of thumb is that SIMD needs:
* A loop with a predetermined length, so it knows when to stop, and
* A loop with no branches (i.e. if-statements) in the loop

In fact, even boundschecking, i.e. checking that you are not indexing outside the bounds of a vector, causes a branch. After all, if the code is supposed to raise a bounds error after 3 iterations, even a single SIMD operation would be wrong! To achieve SIMD vectorization then, all boundschecks must be disabled.

Fortunately, in the latest versions of Julia, the compiler has been pretty smart at figuring out when it can SIMD even when boundschecking.

To demonstrate the significant impact of SIMDd, we can use a function that uses an input function to break a loop. We can then compare the speed of the function when given a function that the compiler knows will never break the loop and so can SIMDd, with a function that might break the loop."""

# ╔═╡ 94182f88-8af1-11eb-207a-37083c1ead68
begin
	# The loop in the function breaks if pred(x[i])
	# returns `true`, and therefore cannot be SIMDd
    function sum_predicate(pred, x::Vector)
        n = zero(eltype(x))
        for i in eachindex(x)
			y = x[i]
			pred(y) && break
			n += y
        end
        return n
    end
end;

# ╔═╡ aa3931fc-8af1-11eb-2f42-f582b8e639ad
md"""
On my computer, the SIMD code is 10x faster than the non-SIMD code. SIMD alone accounts for only about 4x improvements (since we moved from 64-bits per iteration to 256 bits per iteration). The rest of the gain comes from not spending time checking the bounds and from automatic loop unrolling (explained later), which is also made possible by the `@inbounds` annotation.

#### SIMD needs a loop where loop order doesn't matter
SIMD can change the order in which elements in an array is processed. If the result of any iteration depends on any previous iteration such that the elements can't be re-ordered, the compiler will usually not SIMD-vectorize. Often when a loop won't auto-vectorize, it's due to subtleties in which data moves around in registers means that there will be some hidden memory dependency between elements in an array.

Imagine we want to sum some 64-bit integers in an array using SIMD. For simplicity, let's say the array has 8 elements, `A`, `B`, `C` ... `H`. In an ordinary non-SIMD loop, the additions would be done like so:

$$(((((((A + B) + C) + D) + E) + F) + G) + H)$$

Whereas when loading the integers using SIMD, four 64-bit integers would be loaded into one vector `<A, B, C, D>`, and the other four into another `<E, F, G, H>`. The two vectors would be added: `<A+E, B+F, C+G, D+H>`. After the loop, the four integers in the resulting vector would be added. So the overall order would be:

$$((((A + E) + (B + F)) + (C + G)) + (D + H))$$

Perhaps surprisingly, addition of floating point numbers can give different results depending on the order (i.e. float addition is not associative):
"""

# ╔═╡ c01bf4b6-8af1-11eb-2f17-bfe0c93d48f9
begin
    x = eps(1.0) * 0.4
    1.0 + (x + x) == (1.0 + x) + x
end

# ╔═╡ c80e05ba-8af1-11eb-20fc-235b45f2eb4b
md"for this reason, float addition will not auto-vectorize:"

# ╔═╡ e3931226-8af1-11eb-0da5-fb3c1c22d12e
md"However, high-performance programming languages usually provide a command to tell the compiler it's alright to re-order the loop, even for non-associative loops. In Julia, this command is the `@simd` macro:"

# ╔═╡ e793e300-8af1-11eb-2c89-e7bc1be249f0
function sum_simd(x::Vector)
    n = zero(eltype(x))
    # Here we add the `@simd` macro to allow SIMD of floats
    @inbounds @simd for i in eachindex(x)
        n += x[i]
    end
    return n
end;

# ╔═╡ f0a4cb58-8af1-11eb-054c-03192285b5e2
md"""
Julia also provides the macro `@simd ivdep` which further tells the compiler that there are no memory-dependencies in the loop order. However, I *strongly discourage* the use of this macro, unless you *really* know what you're doing. In general, the compiler knows best when a loop has memory dependencies, and misuse of `@simd ivdep` can very easily lead to bugs that are hard to detect.
"""

# ╔═╡ f5c28c92-8af1-11eb-318f-5fa059d8fd80
md"""
## Struct of arrays
If we create an array containing four `AlignmentTest` objects `A`, `B`, `C` and `D`, the objects will lie end to end in the array, like this:

    Objects: |      A        |       B       |       C       |        D      |
    Fields:  |   a   | b |c| |   a   | b |c| |   a   | b |c| |   a   | b |c| |
    Byte:     1               9              17              25              33

Note again that byte no. 8, 16, 24 and 32 are empty to preserve alignment, wasting memory.
Now suppose you want to do an operation on all the `.a` fields of the structs. Because the `.a` fields are scattered 8 bytes apart, SIMD operations are much less efficient (loading up to 4 fields at a time) than if all the `.a` fields were stored together (where 8 fields could fit in a 256-bit register). When working with the `.a` fields only, the entire 64-byte cache lines would be read in, of which only half, or 32 bytes would be useful. Not only does this cause more cache misses, we also need instructions to pick out the half of the data from the SIMD registers we need.

The memory structure we have above is termed an "array of structs," because, well, it is an array filled with structs. Instead we can strucure our 4 objects `A` to `D` as a "struct of arrays." Conceptually, it could look like:
"""

# ╔═╡ fc2d2f1a-8af1-11eb-11a4-8700f94e866e
struct AlignmentTestVector
    a::Vector{UInt32}
    b::Vector{UInt16}
    c::Vector{UInt8}
end

# ╔═╡ 007cd39a-8af2-11eb-053d-f584d68f7d2f
md"""
With the following memory layout for each field:

    Object: AlignmentTestVector
    .a |   A   |   B   |   C   |   D   |
    .b | A | B | C | D |
    .c |A|B|C|D|

Alignment is no longer a problem, no space is wasted on padding. When running through all the `a` fields, all cache lines contain full 64 bytes of relevant data, so SIMD operations do not need extra operations to pick out the relevant data:
"""

# ╔═╡ 72fbb3ec-8ee8-11eb-3836-11092ef74e86
function Base.rand(::Type{AlignmentTest})
    AlignmentTest(rand(UInt32), rand(UInt16), rand(UInt8))
end;

# ╔═╡ abb45d6a-8aef-11eb-37a4-7b10847b39b4
begin
    # Open a file
    function test_file(path)
        open(path) do file
            # Go to 1000'th byte of file and read it
            seek(file, 1000)
            read(file, UInt8)
        end
    end

    # Randomly access data N times
    function random_access(data::Vector{UInt}, N::Integer)
        n = rand(UInt)
        mask = length(data) - 1
        @inbounds for i in 1:N
            n = (n >>> 7) ⊻ data[n & mask + 1]
        end
        return n
    end
end;

# ╔═╡ bff99828-8aef-11eb-107b-a5c67101c735
let
    data = rand(UInt, 2^24)
    @time test_file("../alen/src/main.rs")
    @time random_access(data, 1000000)
    nothing
end

# ╔═╡ b73605ca-8ee4-11eb-1a0d-bb6678de91c6
begin
    @btime random_access($(rand(UInt, 1024)), 2^20) seconds=1
    @btime random_access($(rand(UInt, 2^24)), 2^20) seconds=1
    nothing
end

# ╔═╡ ffca4c72-8aef-11eb-07ac-6d5c58715a71
function linear_access(data::Vector{UInt}, N::Integer)
    n = rand(UInt)
    mask = length(data) - 1
    for i in 1:N
        n = (n >>> 7) ⊻ data[(15 * i) & mask + 1]
    end
    return n
end;

# ╔═╡ e71e4798-8ee4-11eb-3ea2-fdbbcdcf7410
let
    data = rand(UInt, 2^24)
    @btime random_access($data, 2^20) seconds=1
    @btime linear_access($data, 2^20) seconds=1
    nothing
end

# ╔═╡ 18e8e4b6-8af0-11eb-2f17-2726f162e9b0
function alignment_test(data::Vector{UInt}, offset::Integer)
    # Jump randomly around the memory.
    n = rand(UInt)
    mask = (length(data) - 9) ⊻ 7
    GC.@preserve data begin # protect the array from moving in memory
        ptr = pointer(data)
        iszero(UInt(ptr) & 63) || error("Array not aligned")
        ptr += (offset & 63)
        for i in 1:4096
            n = (n >>> 7) ⊻ unsafe_load(ptr, (n & mask + 1) % Int)
        end
    end
    return n
end;

# ╔═╡ 1f38f8c6-8ee5-11eb-1c01-f3706534a9cf
let
    data = rand(UInt, 256 + 8)
    @btime alignment_test($data, 0) seconds=1
    @btime alignment_test($data, 60) seconds=1
    nothing
end

# ╔═╡ 3fae31a0-8af0-11eb-1ea8-7980e7875039
let
    memory_address = reinterpret(UInt, pointer(rand(1024)))
    @assert iszero(memory_address % 64) # should not error!
end

# ╔═╡ 11c500e8-8ee2-11eb-3291-4382b60c5a2b
let
    data = rand(UInt, 2^10)
    show(stdout, MIME"text/plain"(), @benchmark increment($data) seconds=1)
    println('\n')
    show(stdout, MIME"text/plain"(), @benchmark increment!($data) seconds=1)
end

# ╔═╡ 61ee9ace-8af1-11eb-34bd-c5af962c8d82
let
    Base.:+(x::Int, y::AllocatedInteger) = x + y.x
    Base.:+(x::AllocatedInteger, y::AllocatedInteger) = x.x + y.x

    data_stack = [StackAllocated(i) for i in rand(UInt16, 1000000)]
    data_heap = [HeapAllocated(i.x) for i in data_stack]

    @btime sum($data_stack) seconds=1
    @btime sum($data_heap) seconds=1
    nothing
end

# ╔═╡ 6ba266f4-8af1-11eb-10a3-3daf6e473142
let
    data_stack = [StackAllocated(i) for i in rand(UInt16, 1)]
    data_heap = [HeapAllocated(i.x) for i in data_stack]

    println(rpad("First object of data_stack:", 36), data_stack[1])
    println(
        rpad("First data in data_stack array:", 36),
        unsafe_load(pointer(data_stack)),
        '\n'
    )

    println(rpad("First object of data_heap:", 36), data_heap[1])
    first_data = unsafe_load(Ptr{UInt}(pointer(data_heap)))
    println(rpad("First data in data_heap array:", 36), repr(first_data))
    println(
        "Data at address ",
        repr(first_data), ": ",
        unsafe_load(Ptr{HeapAllocated}(first_data))
    )
end

# ╔═╡ 84c0d56a-8af1-11eb-30f3-d137b377c31f
let
    add_tuple(a, b) = a .+ b

    # Create a tuple of 8 32-bit integers.
    # could also have created 4 64-bit numbers etc.
    numbers = ntuple(i -> rand(UInt32), 8)
    @code_native debuginfo=:none dump_module=false add_tuple(numbers, numbers)
    nothing
end

# ╔═╡ a0286cdc-8af1-11eb-050e-072acdd4f0a0
let
    # Make sure the vector is small so we don't time cache misses
    data = rand(UInt64, 4096)

	# For a function that always returns false, the compiler
	# knows it can never break, and so will SIMD
    @btime sum_predicate(Returns(false), $data) seconds=1

	# This function has a 1/2^64 risk of returning true;
	# while practically impossible, the compiler cannot
	# guarantee it won't break the loop, and so will not SIMD
    @btime sum_predicate(iszero, $data) seconds=1
    nothing
end

# ╔═╡ cc99d9ce-8af1-11eb-12ec-fbd6df3becc8
let
    data = rand(Float64, 4096)
    @btime sum_predicate(Returns(false), $data) seconds=1
    @btime sum_predicate(iszero, $data) seconds=1
    nothing
end

# ╔═╡ e8d2ec8e-8af1-11eb-2018-1fa4df5b47ad
let
    data = rand(Float64, 4096)
    @btime sum_predicate(Returns(false), $data) seconds=1
    @btime sum_simd($data) seconds=1
    nothing
end

# ╔═╡ 054d848a-8af2-11eb-1f98-67f5d0b9f4ec
let
    N  = 1_000_000
    array_of_structs = [rand(AlignmentTest) for i in 1:N]
    struct_of_arrays = AlignmentTestVector(
        rand(UInt32, N),
        rand(UInt16, N),
        rand(UInt8, N)
    )

    @btime sum(x -> x.a, $array_of_structs) seconds=1
    @btime sum($struct_of_arrays.a) seconds=1
    nothing
end

# ╔═╡ 0dfc5054-8af2-11eb-098d-35f4e69ae544
md"""
## Specialized CPU instructions

Most code makes use of only a score of simple CPU instructions like move, add, multiply, bitshift, and, or, xor, jumps, and so on. However, CPUs in the typical modern laptop support a *lot* of CPU instructions. Usually, if an operation is used heavily in consumer laptops, CPU manufacturers will add specialized instructions to speed up these operations. Depending on the hardware implementation of the instructions, the speed gain from using these instructions can be significant.

Julia only exposes a few specialized instructions, including:

* The number of set bits in an integer is effectively counted with the `popcnt` instruction, exposed via the `count_ones` function.
* The `tzcnt` instructions counts the number of trailing zeros in the bits an integer, exposed via the `trailing_zeros` function
* The order of individual bytes in a multi-byte integer can be reversed using the `bswap` instruction, exposed via the `bswap` function. This can be useful when having to deal with [endianness](https://en.wikipedia.org/wiki/Endianness).

The following example illustrates the performance difference between a manual implementation of the `count_ones` function, and the built-in version, which uses the `popcnt` instruction:
"""

# ╔═╡ 126300a2-8af2-11eb-00ea-e76a979aef45
function manual_count_ones(x)
    n = 0
    while x != 0
        n += x & 1
        x >>>= 1
    end
    return n
end;

# ╔═╡ 14e46866-8af2-11eb-0894-bba824f266f0
let
    data = rand(UInt, 10000)
    @btime sum(manual_count_ones, $data) seconds=1
    @btime sum(count_ones, $data) seconds=1
    nothing
end

# ╔═╡ 1e7edfdc-8af2-11eb-1429-4d4220bad0f0
md"""
The timings you observe here will depend on whether your compiler is clever enough to realize that the computation in the first function can be expressed as a `popcnt` instruction, and thus will be compiled to that. On my computer, the compiler is not able to make that inference, and the second function achieves the same result more than 100x faster.

#### Call any CPU instruction
Julia makes it possible to call CPU instructions direcly. This is not generally advised, since not all your users will have access to the same CPU with the same instructions, and so your code will crash on users working on computers of different brands.

The latest CPUs contain specialized instructions for AES encryption and SHA256 hashing. If you wish to call these instructions, you can call Julia's backend compiler, LLVM, directly. In the example below, I create a function which calls the `vaesenc` (one round of AES encryption) instruction directly:
"""

# ╔═╡ 25a47c54-8af2-11eb-270a-5b58c3aafe6e
begin
    # This is a 128-bit CPU "vector" in Julia
    const __m128i = NTuple{2, VecElement{Int64}}

    # Define the function in terms of LLVM instructions
    aesenc(a, roundkey) = ccall(
        "llvm.x86.aesni.aesenc", llvmcall, __m128i,
        (__m128i, __m128i), a, roundkey
    )
end;

# ╔═╡ 2dc4f936-8af2-11eb-1117-9bc10e619ec6
md"(Thanks to Kristoffer Carlsson for [the example](http://kristofferc.github.io/post/intrinsics/)). We can verify it works by checking the assembly of the function, which should contain only a single `vaesenc` instruction, as well as the `retq` (return) and the `nopw` (do nothing, used as a filler to align the CPU instructions in memory) instruction:"

# ╔═╡ 76a4e83c-8af2-11eb-16d7-75eaabcb21b6
@code_native debuginfo=:none dump_module=false aesenc(
	__m128i((1, 1)), __m128i((1, 1))
)

# ╔═╡ 797264de-8af2-11eb-0cb0-adf3fbc95c90
md"""Algorithms which makes use of specialized instructions can be extremely fast. [In a blog post](https://mollyrocket.com/meowhash), the video game company Molly Rocket unveiled a new non-cryptographic hash function using AES instructions which reached unprecedented speeds."""

# ╔═╡ 80179748-8af2-11eb-0910-2b825104159d
md"## Inlining
Consider the assembly of this function:"

# ╔═╡ 36b723fc-8ee9-11eb-1b92-451b992acc0c
f() = error();

# ╔═╡ 8af63980-8af2-11eb-3028-83a935bac0db
md"""
This code contains the `callq` instruction, which calls another function. A function call comes with some overhead depending on the arguments of the function and other things. While the time spent on a function call is measured in nanoseconds, it can add up if the function called is in a tight loop.

However, if we show the assembly of this function:
"""

# ╔═╡ 50ab0cf6-8ee9-11eb-3e04-af5fef7f2850
call_plus(x) = x + 1;

# ╔═╡ 93af6754-8af2-11eb-0fe6-216d76e683de
@code_native debuginfo=:none dump_module=false call_plus(1)

# ╔═╡ a105bd68-8af2-11eb-31f6-3335b4fb0f08
md"""
The function `call_plus` calls `+`, and is compiled to a single `leaq` instruction (as well as some filler `retq` and `nopw`). But `+` is a normal Julia function, so `call_plus` is an example of one regular Julia function calling another. Why is there no `callq` instruction to call `+`?

The compiler has chosen to *inline* the function `+` into `call_plus`. That means that instead of calling `+`, it has copied the *content* of `+` directly into `call_plus`. The advantages of this is:
* There is no overhead from the function call
* There is no need to construct a `Tuple` to hold the arguments of the `+` function
* Whatever computations happens in `+` is compiled together with `call_plus`, allowing the compiler to use information from one in the other and possibly simplify some calculations.

So why aren't *all* functions inlined then? Inlining copies code, increases the size of it and consuming RAM. Furthermore, the *CPU instructions themselves* also needs to fit into the CPU cache (although CPU instructions have their own cache) in order to be efficiently retrieved. If everything was inlined, programs would be enormous and grind to a halt. Inlining is only an improvement if the inlined function is small.

Instead, the compiler uses heuristics (rules of thumb) to determine when a function is small enough for inlining to increase performance. These heuristics are not bulletproof, so Julia provides the macros `@noinline`, which prevents inlining of small functions (useful for e.g. functions that raises errors, which must be assumed to be called rarely), and `@inline`, which does not *force* the compiler to inline, but *strongly suggests* to the compiler that it ought to inline the function.

If code contains a time-sensitive section, for example an inner loop, it is important to look at the assembly code to verify that small functions in the loop is inlined. For example, in [this line in my kmer hashing code](https://github.com/jakobnissen/Kash.jl/blob/b9a6e71acf9651d3614f92d5d4b29ffd136bcb5c/src/kmersketch.jl#L41), overall minhashing performance drops by a factor of two if this `@inline` annotation is removed.

An extreme difference between inlining and no inlining can be demonstrated thus:
"""

# ╔═╡ a843a0c2-8af2-11eb-2435-17e2c36ec253
begin
    @noinline noninline_poly(x) = x^3 - 4x^2 + 9x - 11
    inline_poly(x) = x^3 - 4x^2 + 9x - 11

    function time_function(F, x::AbstractVector)
        n = 0
        for i in x
            n += F(i)
        end
        return n
    end
end;

# ╔═╡ b4d9cbb8-8af2-11eb-247c-d5b16e0de13f
let
    data = rand(UInt, 1024)
    @btime time_function(noninline_poly, $data) seconds=1
    @btime time_function(inline_poly, $data) seconds=1
    nothing
end

# ╔═╡ bc0a2f22-8af2-11eb-3803-f54f84ddfc46
md"""
## Unrolling
Consider a function that sums a vector of 64-bit integers. If the vector's data's memory offset is stored in register `%r9`, the length of the vector is stored in register `%r8`, the current index of the vector in `%rcx` and the running total in `%rax`, the assembly of the inner loop could look like this:

```
L1:
    ; add the integer at location %r9 + %rcx * 8 to %rax
    addq   (%r9,%rcx,8), %rax

    ; increment index by 1
    addq   $1, %rcx

    ; compare index to length of vector
    cmpq   %r8, %rcx

    ; repeat loop if index is smaller
    jb     L1
```

For a total of 4 instructions per element of the vector. The actual code generated by Julia will be similar to this, but also incluce extra instructions related to bounds checking that are not relevant here (and of course will include different comments).

However, if the function is written like this:

```julia
function sum_vector(v::Vector{Int})
    n = 0
    i = 1
    for chunk in 1:div(length(v), 4)
        n += v[i + 0]
        n += v[i + 1]
        n += v[i + 2]
        n += v[i + 3]
        i += 4
    end
    return n
end
```

The result is obviously the same if we assume the length of the vector is divisible by four. If the length is not divisible by four, we could simply use the function above to sum the first $N - rem(N, 4)$ elements and add the last few elements in another loop. Despite the functionally identical result, the assembly of the loop is different and may look something like:

```
L1:
    addq   (%r9,%rcx,8), %rax
    addq   8(%r9,%rcx,8), %rax
    addq   16(%r9,%rcx,8), %rax
    addq   24(%r9,%rcx,8), %rax
    addq   $4, %rcx
    cmpq   %r8, %rcx
    jb     L1
```

For a total of 7 instructions per 4 additions, or 1.75 instructions per addition. This is less than half the number of instructions per integer! The speed gain comes from simply checking less often when we're at the end of the loop. We call this process *unrolling* the loop, here by a factor of four. Naturally, unrolling can only be done if we know the number of iterations beforehand, so we don't "overshoot" the number of iterations. Often, the compiler will unroll loops automatically for extra performance, but it can be worth looking at the assembly. For example, this is the assembly for the innermost loop generated on my computer for `sum([1])`:

    L144:
        vpaddq  16(%rcx,%rax,8), %ymm0, %ymm0
        vpaddq  48(%rcx,%rax,8), %ymm1, %ymm1
        vpaddq  80(%rcx,%rax,8), %ymm2, %ymm2
        vpaddq  112(%rcx,%rax,8), %ymm3, %ymm3
        addq    $16, %rax
        cmpq    %rax, %rdi
        jne L144

Where you can see it is both unrolled by a factor of four, and uses 256-bit SIMD instructions, for a total of 128 bytes, 16 integers added per iteration, or 0.44 instructions per integer.

Notice also that the compiler chooses to use 4 different `ymm` SIMD registers, `ymm0` to `ymm3`, whereas in my example assembly code, I just used one register `rax`. This is because, if you use 4 independent registers, then you don't need to wait for one `vpaddq` to complete (remember, it had a ~3 clock cycle latency) before the CPU can begin the next.

The story for unrolling is similar to that for SIMD: The compiler will only unroll a loop if it can tell _for sure_ that it will not overshoot the number of iterations. For example, compare the two following functions:
"""

# ╔═╡ f0bc1fdc-8ee9-11eb-2916-d71e1cf36375
let
    data = fill(false, 2^20)

    # any: Stops as soon as it finds a `true`
    @btime any($data) seconds=1

    # foldl: Loops over all values in the array
    @btime foldl(|, $data) seconds=1

    data[1] = true
    @btime any($data) seconds=1
    @btime foldl(|, $data) seconds=1
    nothing
end

# ╔═╡ 36a2872e-8eeb-11eb-0999-4153ced71678
md"""
The _first_ function stops and returns as soon as it finds a `true` value - but this break in the loop disables SIMD and unrolling. The _second_ function continues throughout the entire array, even if the very first value is `true`. While this enables SIMD and unrolling, it's obviously wasteful if it sees a `true` right in the beginning. Hence, the first is better when we expect to see the first `true` before around 1/4th of the way though the array, the latter better otherwise.

We can create a compromise by manually unrolling. In the functions below, `check128` checks 128 entries using `inbounds`, without stopping underway to check if it's found a `true`, and is thus unrolled and SIMDd. `unroll_compromise` then uses `check128`, but breaks out of the loop as soon as it finds a `true.`
"""

# ╔═╡ 9ca70cfc-8eeb-11eb-361b-b929089ca109
begin
    @inline function check128(data, i)
        n = false
        @inbounds for j in 0:127
            n |= data[i+j]
        end
        n
    end

    function unroll_compromise(data)
        found = false
        i = 1
        while !found & (i ≤ length(data))
            check128(data, i) && return true
            i += 128
        end
        return false
    end
end;

# ╔═╡ d4a43094-8eeb-11eb-106f-3b54253aa663
let
    data = fill(false, 2^20)
    @btime foldl(|, $data) seconds=1
    @btime unroll_compromise($data) seconds=1

    data[1] = true
    @btime any($data) seconds=1
    @btime unroll_compromise($data) seconds=1
    nothing
end

# ╔═╡ 270950ac-8eed-11eb-365d-df9d36d090bc
md"""
We see excellent performance for both arrays with no `trues`, and for the one with a `true` right in the beginning.

Unfortunately, I'm not aware of any way to automatically generate this kind of unrolling, where you want a compromise between unrolling smaller chunks, and including branches in between each chunk. Perhaps in the future, this desire can be communicated to the compiler, such that the optimal code is automatically generated.
"""

# ╔═╡ c36dc5f8-8af2-11eb-3f35-fb86143a54d2
md"""
## Avoid unpredicable branches
As mentioned previously, CPU instructions take multiple cycles to complete, but may be queued into the CPU before the previous instruction has finished computing. So what happens when the CPU encounters a branch (i.e. a jump instruction)? It can't know which instruction to queue next, because that depends on the instruction that it just put into the queue and which has yet to be executed.

Modern CPUs make use of *branch prediction*. The CPU has a *branch predictor* circuit, which guesses the correct branch based on which branches were recently taken. In essense, the branch predictor attempts to learn simple patterns in which branches are taken in code, while the code is running. After queueing a branch, the CPU immediately queues instructions from whatever branch predicted by the branch predictor. The correctness of the guess is verified later, when the queued branch is being executed. If the guess was correct, great, the CPU saved time by guessing. If not, the CPU has to empty the pipeline and discard all computations since the initial guess, and then start over. This process causes a delay of a few nanoseconds.

For the programmer, this means that the speed of an if-statement depends on how easy it is to guess. If it is trivially easy to guess, the branch predictor will be correct almost all the time, and the if statement will take no longer than a simple instruction, typically 1 clock cycle. In a situation where the branching is random, it will be wrong about 50% of the time, and each misprediction may cost many clock cycles.

Branches caused by loops are among the easiest to guess. If you have a loop with 1000 elements, the code will loop back 999 times and break out of the loop just once. Hence the branch predictor can simply always predict "loop back", and get a 99.9% accuracy.

We can demonstrate the performance of branch misprediction with a simple function:
"""

# ╔═╡ c96f7f50-8af2-11eb-0513-d538cf6bc619
# Copy all odd numbers from src to dst.
function copy_odds_branches!(dst::Vector{T}, src::Vector{T}) where {T <: Integer}
    write_index = 1
    @inbounds for i in eachindex(src) # <--- this branch is trivially easy to predict
        v = src[i]
        if isodd(v)  # <--- this is the branch we want to predict
            dst[write_index] = v
            write_index += 1
        end
    end
    return dst
end;

# ╔═╡ cf90c600-8af2-11eb-262a-2763ae29b428
let
    dst = rand(UInt32, 2^18)
    src_random = rand(UInt32, 2^18)
    src_all_odd = [(2*i+1) % UInt32 for i in src_random]
    @btime copy_odds_branches!($dst, $src_random) seconds=1
    @btime copy_odds_branches!($dst, $src_all_odd) seconds=1
    nothing
end

# ╔═╡ d53422a0-8af2-11eb-0417-b9740c4a571c
md"""
In the first case, the integers are random, and about half the branches will be mispredicted causing delays. In the second case, the branch is always taken, the branch predictor is quickly able to pick up the pattern and will reach near 100% correct prediction. As a result, on my computer, the latter is around 8x faster.

Note that if you use smaller vectors and repeat the computation many times, as the `@btime` macro does, the branch predictor is able to learn the pattern of the small random vectors by heart, and will reach much better than random prediction. This is especially pronounced in the most modern CPUs (and in particular the CPUs sold by AMD, I hear) where the branch predictors have gotten much better. This "learning by heart" is an artifact of the loop in the benchmarking process. You would not expect to run the exact same computation repeatedly on real-life data:
"""

# ╔═╡ dc5b9bbc-8af2-11eb-0197-9b5da5087f0d
let
    src_random = rand(UInt32, 128)
    dst = similar(src_random)
    src_all_odd = [(2i+1) % UInt32 for i in src_random]

    @btime copy_odds_branches!($dst, $src_random) seconds=1
    @btime copy_odds_branches!($dst, $src_all_odd) seconds=1
    nothing
end

# ╔═╡ e735a302-8af2-11eb-2ce7-01435b60fdd9
md"""
Because branches are very fast if they are predicted correctly, highly predictable branches caused by error checks are not of much performance concern, assuming that the code essensially never errors. Hence a branch like bounds checking is very fast. You should only remove bounds checks if absolutely maximal performance is critical, or if the bounds check happens in a loop which would otherwise SIMD-vectorize.

If branches cannot be easily predicted, it is often possible to re-phrase the function to avoid branches all together. For example, in the `copy_odds!` example above, we could instead write it like so:
"""

# ╔═╡ eb158e60-8af2-11eb-2227-59d6404e3335
function copy_odds_branchless!(dst::Vector{T}, src::Vector{T}) where {T <: Integer}
    write_index = 1
    @inbounds for i in eachindex(src)
        v = src[i]
        dst[write_index] = v
        write_index += isodd(v)
    end
    return dst
end;

# ╔═╡ ee579dca-8af2-11eb-140f-a96778b7b39f
let
    dst = rand(UInt32, 2^18)
    src_random = rand(UInt32, 2^18)
    src_all_odd = [(2*i+1) % UInt32 for i in src_random]
    @btime copy_odds_branchless!($dst, $src_random) seconds=1
    @btime copy_odds_branchless!($dst, $src_all_odd) seconds=1
    nothing
end

# ╔═╡ f969eed2-8af2-11eb-1e78-5b322a7f4ebd
md"""
Which contains no other branches than the one caused by the loop itself (which is easily predictable), and results in speeds slightly worse than the perfectly predicted one, but much better for random data.

The compiler will often remove branches in your code when the same computation can be done using other instructions. When the compiler fails to do so, Julia offers the `ifelse` function, which sometimes can help elide branching.
"""

# ╔═╡ 72e1b146-8c1c-11eb-2c56-b1342271c2f6
md"""
## Be aware of memory dependencies

Thinking about it more deeply, why *is* the perfectly predicted example above faster than the solution that avoids having that extra branch there at all?

Let's look at the assembly code. Here, I've just cut out the assembly for the loop (since almost all time is spent there)

For the branch-ful version, we have:
```julia
1 L48:
2     incq	%rsi
3     cmpq	%rsi, %r9
4     je	L75
5 L56:
6     movq	(%rdx,%rsi,8), %rcx
7     testb	$1, %cl
8     je	L48
9     movq	%rcx, -8(%r8,%rdi,8)
10	incq	%rdi
11	jmp	L48
```

And for the branch-less, we have:
```julia
1 L48:
2	movq	(%r9,%rcx,8), %rdx
3	incq	%rcx
4	movq	%rdx, -8(%rsi,%rdi,8)
5	andl	$1, %edx
6	addq	%rdx, %rdi
7	cmpq	%rcx, %r8
8	jne	L48
```

The branch-ful executes 9 instructions per iteration (remember, all iterations had uneven numbers), whereas the branch-less executes only 7. Looking at the table for how long instructions take, you will find all these instructions are fast. So what gives?

To understand what is happening, we need to go a little deeper into the CPU. In fact, the CPU does not execute CPU instructions in a linear fashion as the assembly code would have you believe. Instead, a more accurate (but still simplified) picture is the following:

1. The CPU reads in CPU instructions. It then on-the-fly translates these CPU instructions to a set of even lower-level instructions called _micro-operations_ or _µops_. The important difference between µops and CPU instructions is that while only a few different registers can be referred to by the instructions, the actual processor has many more registers, which can be addressed by µops. Code written with µops is called _microcode_.

2. This microcode is loaded into an internal array called the *reorder buffer* for storage. A CPU may hold more than 200 instructions in the reorder buffer at a time. The purpose of this storage is to allow execution of microcode in a highly parallel way. The code is then sent to execution in bulk.

3. Finally, results from the reorder buffer is then shipped out to memory in the correct order.

The existance of a re-order buffer has two important implications (that I know about) for how you should think about your code:

First, your code is executed in large chunks often in parallel, not necessarily in the same order as it was loaded in. Therefore, _a program with more, slower CPU instructions can be faster than a program with fewer, faster instructions_, if the former program manages to execute more of them in parallel.

Second, branch prediction (as discussed in the previous section) does not happen just for the upcoming branch, but instead for a large amount of future branches, simultaneously.

When visualizing how the code of the small `copy_odds_branches!` loop above is executed, you may imagine that the branch predictor predicts all branches, say, 6 iterations of the loop into the future, loads the microcode of all 6 future iterations into the reorder buffer, executes them all in parallel, and _then_ verifies - still in parallel - that its branches were guessed correctly.

 Indicentally, this bulk processing is why a branch mispredict is so bad for performance - if a branch turns out to be mispredicted, all the work in the reorder buffer must be scrapped, the and the CPU must start over with fetching new instructions, compile them to microcode, fill the buffer et cetera.

Let's think about the implications re-order buffer for a moment. Other than creating hard-to-predict branches, what kind of code can re write that messes up that workflow for the CPU?

What if we do this?
"""

# ╔═╡ 7732b6d8-8dab-11eb-0bc2-19690386ec27
function read_indices(dst::Vector{T}, src::Vector{T}) where {T <: Integer}
    i = 1
    while i ≤ lastindex(src) - 1
        i = src[i] + 1
        dst[i] = i
    end
    return dst
end;

# ╔═╡ 29463b02-8dab-11eb-0bf5-23a3f4075b32
let
    dst = rand(UInt32, 2^18)
    src = UInt32.(eachindex(dst))
    @btime read_indices($dst, $src) seconds=1
    nothing
end

# ╔═╡ a5d93434-8dac-11eb-34bf-91061089f0ef
md"""
If you think about it, `read_indices` does strictly less work than any of the `copy_odds` functions. It doesn't even check if the numbers it copies are odd. Yet it's more than three times slower than `copy_odds_branches`!

The difference is *memory dependencies*. We humans, seeing that the input data is simply a range of numbers, can tell _precisely_ what the function should do at every iteration: Simply copy the next number over. But the compiler _can't_ predict what the next number it loads will be, and therefore where it needs to store the loaded number. We say that the code has a memory dependency on the number it loads from `src`.

In that case, the reorder buffer is of no use. All the instructions get loaded in, but are simply kept idle in the reorder buffer, because they simply *cannot* be executed until it's "their turn".

Going back to the original example, that is why the perfectly predicted `copy_odds_branches!` performs better than `code_odds_branchless!`. Even though the latter has fewer instructions, it has a memory dependency: The index of `dst` where the odd number gets stored to depends on the last loop iteration. So fewer instructions can be executed at a time compared to the former function, where the branch predictor predicts several iterations ahead and allow for the parallel computation of multiple iterations.
"""

# ╔═╡ 0b6d234e-8af3-11eb-1ba9-a1dcf1497785
md"""
## Variable clock speed

A modern laptop CPU optimized for low power consumption consumes roughly 25 watts of power on a chip as small as a stamp (and thinner than a human hair). Without proper cooling, this will cause the temperature of the CPU to skyrocket and melting the plastic of the chip, destroying it. Typically, CPUs have a maximal operating temperature of about 100 degrees C. Power consumption, and therefore heat generation, depends among many factors on clock speed, higher clock speeds generate more heat.

Modern CPUs are able to adjust their clock speeds according to the CPU temperature to prevent the chip from destroying itself. Often, CPU temperature will be the limiting factor in how quick a CPU is able to run. In these situations, better physical cooling for your computer translates directly to a faster CPU. Old computers can often be revitalized simply by removing dust from the interior, and replacing the cooling fans and [CPU thermal paste](https://en.wikipedia.org/wiki/Thermal_grease)!

As a programmer, there is not much you can do to take CPU temperature into account, but it is good to know. In particular, variations in CPU temperature often explain observed difference in performance:

* CPUs usually work fastest at the beginning of a workload, and then drop in performance as it reaches maximal temperature
* SIMD instructions usually require more power than ordinary instructions, generating more heat, and lowering the clock frequency. This can offset some performance gains of SIMD, but SIMD will nearly always be more efficient when applicable. One exception is the relatively recent 512-bit SIMD instructions. In current (2021) CPUs, these instructions draw so much power that the resulting clock frequency lowering actually leads to overall performance decrease for some workloads. This problem will probably be solved in the near future, either by the power draw begin reduced, by consumer chips abandoning 512-bit SIMD, or by compilers refusing to compile to these instructions.
"""

# ╔═╡ 119d269c-8af3-11eb-1fdc-b7ac75b89cf2
md"""
## Multithreading
In the bad old days, CPU clock speed would increase every year as new processors were brought onto the market. Partially because of heat generation, this acceleration slowed down once CPUs hit the 3 GHz mark. Now we see only minor clock speed increments every processor generation. Instead of raw speed of execution, the focus has shifted on getting more computation done per clock cycle. CPU caches, CPU pipelining (i.e. the entire re-order buffer "workflow"), branch prediction and SIMD instructions are all important contibutions in this area, and have all been covered here.

Another important area where CPUs have improved is simply in numbers: Almost all CPU chips contain multiple smaller CPUs, or *cores* inside them. Each core has their own small CPU cache, and does computations in parallel. Furthermore, many CPUs have a feature called *hyper-threading*, where two *threads* (i.e. streams of instructions) are able to run on each core. The idea is that whenever one process is stalled (e.g. because it experiences a cache miss or a branch misprediction), the other process can continue on the same core. The CPU "pretends" to have twice the amount of processors.

Hyperthreading only really matters when your threads are sometimes prevented from doing work. Besides CPU-internal causes like cache misses, a thread can also be paused because it is waiting for an external resource like a webserver or data from a disk. If you are writing a program where some threads spend a significant time idling, the core can be used by the other thread, and hyperthreading can show its value.

Let's see our first parallel program in action. First, we need to make sure that Julia actually was started with the correct number of threads. To do this, start Julia with the `-t` option - e.g. `-t 8` for 8 threads. I have set Julia to have 4 threads:
"""

# ╔═╡ 1886f60e-8af3-11eb-2117-eb0014d2fca1
Threads.nthreads()

# ╔═╡ 1a0e2998-8af3-11eb-031b-a3448fd65041
# Spend about half the time waiting, half time computing
function half_asleep(start::Bool)
    a, b = 1, 0
    for iteration in 1:5
        start && sleep(0.1)
		t1 = time()
		while time() - t1 < 0.1
			for i in 1:100000
            	a, b = a + b, a
			end
        end
        start || sleep(0.1)
    end
    return a
end;

# ╔═╡ 1ecf434a-8af3-11eb-3c49-cb21c6a80bfc
function parallel_sleep(n_jobs)
    jobs = []
    for job in 1:n_jobs
        push!(jobs, Threads.@spawn half_asleep(isodd(job)))
    end
    return sum(fetch, jobs)
end;

# ╔═╡ 2192c228-8af3-11eb-19d8-81db4f3c0d81
let
    parallel_sleep(1); # run once to compile it
    for njobs in (1, 4, 8, 16, 32)
        @time parallel_sleep(njobs);
    end
end

# ╔═╡ 2d0bb0a6-8af3-11eb-384d-29fbb0f66f24
md"""
You can see that with this task, my computer can run 8 jobs in parallel almost as fast as it can run 1. But 16 jobs takes much longer. This is because 4 can run at the same time, and 4 more can sleep for a total of 8 concurrent jobs.

For CPU-constrained programs, the core is kept busy with only one thread, and there is not much to do as a programmer to leverage hyperthreading. Actually, for the most optimized programs, it usually leads to better performance to *disable* hyperthreading. Most workloads are not that optimized and can really benefit from hyperthreading, however.

#### Parallelizability
Multithreading is more difficult that any of the other optimizations, and should be one of the last tools a programmer reaches for. However, it is also an impactful optimization. Scientific compute clusters usually contain many (e.g. hundreds, or thousands) of CPUs with tens of CPU cores each, offering a massive potential speed boost ripe for picking.

A prerequisite for efficient use of multithreading is that your computation is able to be broken up into multiple chunks that can be worked on independently. Luckily the majority of compute-heavy tasks (at least in my field of work, bioinformatics), contain sub-problems that are *embarassingly parallel*. This means that there is a natural and easy way to break it into sub-problems that can be processed independently. For example, if a certain __independent__ computation is required for 100 genes, it is natural to use one thread for each gene. The size of the problem is also important. There is a small overhead involved with spawning (creating) a thread, and fetching the result from the computation of a thread. Therefore, for it to pay off, each thread should have a task that takes at least a few microseconds to complete.

Let's have an example of a small embarrasingly parallel problem. We want to construct a [Julia set](https://en.wikipedia.org/wiki/Julia_set). Julia sets are named after Gaston Julia, and have nothing to do with the Julia language. Julia sets are (often) fractal sets of complex numbers. By mapping the real and complex component of the set's members to the X and Y pixel value of a screen, one can generate the LSD-trippy images associated with fractals.

The Julia set I create below is defined thus: We define a function $f(z) = z^2 + C$, where $C$ is some constant. We then record the number of times $f$ can be applied to any given complex number $z$ before $|z| > 2$. The number of iterations correspond to the brightness of one pixel in the image. We simply repeat this for a range of real and imaginary values in a grid to create an image.

First, let's see a non-parallel solution:
"""

# ╔═╡ 316e5074-8af3-11eb-256b-c5b212f7e0d3
begin
    const SHIFT = Complex{Float32}(-0.221, -0.713)

    f(z::Complex) = z^2 + SHIFT

    "Set the brightness of a particular pixel represented by a complex number"
    function mandel(z)
        n = 0
        while ((abs2(z) < 4) & (n < 255))
            n += 1
            z = f(z)
        end
        return n
    end

    "Set brightness of pixels in one column of pixels"
    function fill_column!(M::Matrix, x, real)
        for (y, im) in enumerate(range(-1.0f0, 1.0f0, length=size(M, 1)))
            M[y, x] = mandel(Complex{Float32}(real, im))
        end
    end

    "Create a Julia fractal image"
    function julia_single_threaded()
        M = Matrix{UInt8}(undef, 5000, 5000)
        for (x, real) in enumerate(range(-1.0f0, 1.0f0, length=size(M, 2)))
            fill_column!(M, x, real)
        end
        return M
    end
end;

# ╔═╡ 37cd1f1c-8ee9-11eb-015c-ade9efc27708
@code_native debuginfo=:none dump_module=false f()

# ╔═╡ 39a85a58-8af3-11eb-1334-6f50ed9acd31
@time julia_single_threaded();

# ╔═╡ 3e83981a-8af3-11eb-3c87-77797adb7e1f
md"That took around 2 seconds on my computer. Now for a parallel one:"

# ╔═╡ 3e1c4090-8af3-11eb-33d0-b9c299fef20d
begin
    function recursive_fill_columns!(M::Matrix, cols::UnitRange)
        F, L = first(cols), last(cols)
        # If only one column, fill it using fill_column!
        if F == L
            r = range(-1.0f0,1.0f0,length=size(M, 1))[F]
            fill_column!(M, F, r)
        # Else divide the range of columns in two, spawning a new task for each half
        else
            mid = div(L+F,2)
            p = Threads.@spawn recursive_fill_columns!(M, F:mid)
            recursive_fill_columns!(M, mid+1:L)
            wait(p)
        end
    end

    function julia_multi_threaded()
        M = Matrix{UInt8}(undef, 5000, 5000)
        recursive_fill_columns!(M, 1:size(M, 2))
        return M
    end
end;

# ╔═╡ 4be905b4-8af3-11eb-0344-dbdc7e94ddf3
@time julia_multi_threaded();

# ╔═╡ 4e8f6cb8-8af3-11eb-1746-9384995d7022
md"""
This is almost exactly 4 times as fast! With 4 threads, this is close to the best case scenario, only possible for near-perfect embarrasingly parallel tasks.

Despite the potential for great gains, in my opinion, multithreading should be one of the last resorts for performance improvements, for three reasons:

1. Implementing multithreading is harder than other optimization methods in many cases. In the example shown, it was very easy. In a complicated workflow, it can get messy quickly.
2. Multithreading can cause hard-to-diagnose and erratic bugs. These are almost always related to multiple threads reading from, and writing to the same memory. For example, if two threads both increment an integer with value `N` at the same time, the two threads will both read `N` from memory and write `N+1` back to memory, where the correct result of two increments should be `N+2`! Infuriatingly, these bugs appear and disappear unpredictably, since they are causing by unlucky timing. These bugs of course have solutions, but it is tricky subject outside the scope of this document.
3. Finally, achieving performance by using multiple threads is really achieving performance by consuming more resources, instead of gaining something from nothing. Often, you pay for using more threads, either literally when buying cloud compute time, or when paying the bill of increased electricity consumption from multiple CPU cores, or metaphorically by laying claim to more of your users' CPU resources they could use somewhere else. In contrast, more *efficent* computation costs nothing.
"""

# ╔═╡ 54d2a5b8-8af3-11eb-3273-85d551fceb7b
md"""
## GPUs
So far, we've covered only the most important kind of computing chip, the CPU. But there are many other kind of chips out there. The most common kind of alternative chip is the *graphical processing unit* or GPU.

As shown in the above example with the Julia set, the task of creating computer images are often embarassingly parallel with an extremely high degree of parallelizability. In the limit, the value of each pixel is an independent task. This calls for a chip with a high number of cores to do effectively. Because generating graphics is a fundamental part of what computers do, nearly all commercial computers contain a GPU. Often, it's a smaller chip integrated into the motherboard (*integrated graphics*, popular in small laptops). Other times, it's a large, bulky card.

GPUs have sacrificed many of the bells and whistles of CPUs covered in this document such as specialized instructions, SIMD and branch prediction. They also usually run at lower frequencies than CPUs. This means that their raw compute power is many times slower than a CPU. To make up for this, they have a high number of cores. For example, the high-end gaming GPU NVIDIA RTX 2080Ti has 4,352 cores. Hence, some tasks can experience 10s or even 100s of times speedup using a GPU. Most notably for scientific applications, matrix and vector operations are highly parallelizable.

Unfortunately, the laptop I'm writing this document on has only integrated graphics, and there is not yet a stable way to interface with integrated graphics using Julia, so I cannot show examples.

There are also more esoteric chips like TPUs (explicitly designed for low-precision tensor operations common in deep learning) and ASICs (an umbrella term for highly specialized chips intended for one single application). At the time of writing, these chips are uncommon, expensive, poorly supported and have limited uses, and are therefore not of any interest for non-computer science researchers.
"""

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
BenchmarkTools = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"

[compat]
BenchmarkTools = "~1.1.3"
PlutoUI = "~0.7.39"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

[[AbstractPlutoDingetjes]]
deps = ["Pkg"]
git-tree-sha1 = "8eaf9f1b4921132a4cff3f36a1d9ba923b14a481"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.1.4"

[[ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.1"

[[Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[BenchmarkTools]]
deps = ["JSON", "Logging", "Printf", "Statistics", "UUIDs"]
git-tree-sha1 = "42ac5e523869a84eac9669eaceed9e4aa0e1587b"
uuid = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
version = "1.1.4"

[[ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "eb7f0f8307f71fac7c606984ea5fb2817275d6e4"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.4"

[[CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "0.5.2+0"

[[Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.6.0"

[[FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"

[[FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "335bfdceacc84c5cdf16aadc768aa5ddfc5383cc"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.4"

[[Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "8d511d5b81240fc8e6802386302675bdf47737b9"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.4"

[[HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "c47c5fa4c5308f27ccaac35504858d8914e102f9"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.4"

[[IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "f7be53659ab06ddc986428d3a9dcc95f6fa6705a"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.2"

[[InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "3c837543ddb02250ef42f4738347454f95079d4e"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.3"

[[LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.3"

[[LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "7.84.0+0"

[[LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.10.2+0"

[[Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[LinearAlgebra]]
deps = ["Libdl", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.0+0"

[[Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2022.2.1"

[[NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.2.0"

[[OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.20+0"

[[Parsers]]
deps = ["Dates"]
git-tree-sha1 = "3d5bf43e3e8b412656404ed9466f1dcbf7c50269"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.4.0"

[[Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.8.0"

[[PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "Markdown", "Random", "Reexport", "UUIDs"]
git-tree-sha1 = "8d1f54886b9037091edf146b517989fc4a09efec"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.39"

[[Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[Random]]
deps = ["SHA", "Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.0"

[[Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.0"

[[Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[Tricks]]
git-tree-sha1 = "6bac775f2d42a611cdfcd1fb217ee719630c4175"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.6"

[[UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.2.12+3"

[[libblastrampoline_jll]]
deps = ["Artifacts", "Libdl", "OpenBLAS_jll"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.1.1+0"

[[nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.48.0+0"

[[p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.4.0+0"
"""

# ╔═╡ Cell order:
# ╟─15f5c31a-8aef-11eb-3f19-cf0a4e456e7a
# ╟─5dd2329a-8aef-11eb-23a9-7f3c325bcf74
# ╠═7490def0-8aef-11eb-19ce-4b11ce5a9328
# ╠═675e66aa-8aef-11eb-27be-5fe273e33297
# ╟─800d827e-8c20-11eb-136a-97a622a7c1e6
# ╟─9a24985a-8aef-11eb-104a-bd9abf0adc6d
# ╟─a2fad250-8aef-11eb-200f-e5f8caa57a67
# ╠═abb45d6a-8aef-11eb-37a4-7b10847b39b4
# ╠═bff99828-8aef-11eb-107b-a5c67101c735
# ╟─cdde6fe8-8aef-11eb-0a3c-77e28f7a2c09
# ╟─f58d428c-8aef-11eb-3127-89d729e23823
# ╠═b73605ca-8ee4-11eb-1a0d-bb6678de91c6
# ╟─c6da4248-8c19-11eb-1c16-093695add9a9
# ╠═ffca4c72-8aef-11eb-07ac-6d5c58715a71
# ╟─d4c67b82-8c1a-11eb-302f-b79c86412ce5
# ╠═e71e4798-8ee4-11eb-3ea2-fdbbcdcf7410
# ╟─0f2ac53c-8c1b-11eb-3841-27f4ea1e9617
# ╟─12f1228a-8af0-11eb-0449-230ae20bfa7a
# ╠═18e8e4b6-8af0-11eb-2f17-2726f162e9b0
# ╠═1f38f8c6-8ee5-11eb-1c01-f3706534a9cf
# ╟─3a1efd5a-8af0-11eb-21a2-d1011f16555c
# ╠═3fae31a0-8af0-11eb-1ea8-7980e7875039
# ╟─5b10a2b6-8af0-11eb-3fe7-4b78b4c22550
# ╠═6061dc94-8af0-11eb-215a-4f3af731774e
# ╟─624eae74-8af0-11eb-025b-8b68dc55f31e
# ╠═d4c8c38c-8ee6-11eb-0b49-33fbfbd214f3
# ╟─7b979410-8af0-11eb-299c-af0a5d740c24
# ╟─8802ff60-8af0-11eb-21ac-b9fdbeac7c24
# ╠═a36582d4-8af0-11eb-2b5a-e577c5ed07e2
# ╠═a74a9966-8af0-11eb-350f-6787d2759eba
# ╟─ae9ee028-8af0-11eb-10c0-6f2db3ab8025
# ╟─b73b5eaa-8af0-11eb-191f-cd15de19bc38
# ╟─c0c757b2-8af0-11eb-38f1-3bc3ec4c43bc
# ╠═c5472fb0-8af0-11eb-04f1-95a1f7b6b9e0
# ╟─ce0e65d4-8af0-11eb-0c86-2105c26b62eb
# ╠═d376016a-8af0-11eb-3a15-4322759143d1
# ╟─d70c56bc-8af0-11eb-1220-09e78dba26f7
# ╠═dc24f5a0-8af0-11eb-0332-2bc0834d426c
# ╟─e3c136de-8af0-11eb-06f1-9393c0f95fbb
# ╠═e836dac8-8af0-11eb-1865-e3feeb011fc4
# ╟─ecfd04e4-8af0-11eb-0962-f548d2eabad3
# ╠═f0e24b50-8af0-11eb-1a0e-5d925f3743e0
# ╠═11c500e8-8ee2-11eb-3291-4382b60c5a2b
# ╟─22512ab2-8af1-11eb-260b-8d6c16762547
# ╠═2a7c1fc6-8af1-11eb-2909-554597aa2949
# ╟─2e3304fe-8af1-11eb-0f6a-0f84d58326bf
# ╠═33350038-8af1-11eb-1ff5-6d42d86491a3
# ╟─3713a8da-8af1-11eb-2cb2-1957455227d0
# ╠═59f58f1c-8af1-11eb-2e88-997e9d4bcc48
# ╟─5c86e276-8af1-11eb-2b2e-3386e6795f37
# ╠═61ee9ace-8af1-11eb-34bd-c5af962c8d82
# ╟─6849d9ec-8af1-11eb-06d6-db49af4796bc
# ╠═6ba266f4-8af1-11eb-10a3-3daf6e473142
# ╟─74a3ddb4-8af1-11eb-186e-4d80402adfcf
# ╠═7a88c4ba-8af1-11eb-242c-a1813a9e6741
# ╟─7d3fcbd6-8af1-11eb-0441-2f88a9d59966
# ╠═84c0d56a-8af1-11eb-30f3-d137b377c31f
# ╟─8c2ed15a-8af1-11eb-2e96-1df34510e773
# ╠═94182f88-8af1-11eb-207a-37083c1ead68
# ╠═a0286cdc-8af1-11eb-050e-072acdd4f0a0
# ╟─aa3931fc-8af1-11eb-2f42-f582b8e639ad
# ╠═c01bf4b6-8af1-11eb-2f17-bfe0c93d48f9
# ╟─c80e05ba-8af1-11eb-20fc-235b45f2eb4b
# ╠═cc99d9ce-8af1-11eb-12ec-fbd6df3becc8
# ╟─e3931226-8af1-11eb-0da5-fb3c1c22d12e
# ╠═e793e300-8af1-11eb-2c89-e7bc1be249f0
# ╠═e8d2ec8e-8af1-11eb-2018-1fa4df5b47ad
# ╟─f0a4cb58-8af1-11eb-054c-03192285b5e2
# ╟─f5c28c92-8af1-11eb-318f-5fa059d8fd80
# ╠═fc2d2f1a-8af1-11eb-11a4-8700f94e866e
# ╟─007cd39a-8af2-11eb-053d-f584d68f7d2f
# ╠═72fbb3ec-8ee8-11eb-3836-11092ef74e86
# ╠═054d848a-8af2-11eb-1f98-67f5d0b9f4ec
# ╟─0dfc5054-8af2-11eb-098d-35f4e69ae544
# ╠═126300a2-8af2-11eb-00ea-e76a979aef45
# ╠═14e46866-8af2-11eb-0894-bba824f266f0
# ╟─1e7edfdc-8af2-11eb-1429-4d4220bad0f0
# ╠═25a47c54-8af2-11eb-270a-5b58c3aafe6e
# ╟─2dc4f936-8af2-11eb-1117-9bc10e619ec6
# ╠═76a4e83c-8af2-11eb-16d7-75eaabcb21b6
# ╟─797264de-8af2-11eb-0cb0-adf3fbc95c90
# ╟─80179748-8af2-11eb-0910-2b825104159d
# ╠═36b723fc-8ee9-11eb-1b92-451b992acc0c
# ╠═37cd1f1c-8ee9-11eb-015c-ade9efc27708
# ╟─8af63980-8af2-11eb-3028-83a935bac0db
# ╠═50ab0cf6-8ee9-11eb-3e04-af5fef7f2850
# ╠═93af6754-8af2-11eb-0fe6-216d76e683de
# ╟─a105bd68-8af2-11eb-31f6-3335b4fb0f08
# ╠═a843a0c2-8af2-11eb-2435-17e2c36ec253
# ╠═b4d9cbb8-8af2-11eb-247c-d5b16e0de13f
# ╟─bc0a2f22-8af2-11eb-3803-f54f84ddfc46
# ╠═f0bc1fdc-8ee9-11eb-2916-d71e1cf36375
# ╟─36a2872e-8eeb-11eb-0999-4153ced71678
# ╠═9ca70cfc-8eeb-11eb-361b-b929089ca109
# ╠═d4a43094-8eeb-11eb-106f-3b54253aa663
# ╟─270950ac-8eed-11eb-365d-df9d36d090bc
# ╟─c36dc5f8-8af2-11eb-3f35-fb86143a54d2
# ╠═c96f7f50-8af2-11eb-0513-d538cf6bc619
# ╠═cf90c600-8af2-11eb-262a-2763ae29b428
# ╟─d53422a0-8af2-11eb-0417-b9740c4a571c
# ╠═dc5b9bbc-8af2-11eb-0197-9b5da5087f0d
# ╟─e735a302-8af2-11eb-2ce7-01435b60fdd9
# ╠═eb158e60-8af2-11eb-2227-59d6404e3335
# ╠═ee579dca-8af2-11eb-140f-a96778b7b39f
# ╟─f969eed2-8af2-11eb-1e78-5b322a7f4ebd
# ╟─72e1b146-8c1c-11eb-2c56-b1342271c2f6
# ╠═7732b6d8-8dab-11eb-0bc2-19690386ec27
# ╠═29463b02-8dab-11eb-0bf5-23a3f4075b32
# ╟─a5d93434-8dac-11eb-34bf-91061089f0ef
# ╟─0b6d234e-8af3-11eb-1ba9-a1dcf1497785
# ╟─119d269c-8af3-11eb-1fdc-b7ac75b89cf2
# ╠═1886f60e-8af3-11eb-2117-eb0014d2fca1
# ╠═1a0e2998-8af3-11eb-031b-a3448fd65041
# ╠═1ecf434a-8af3-11eb-3c49-cb21c6a80bfc
# ╠═2192c228-8af3-11eb-19d8-81db4f3c0d81
# ╟─2d0bb0a6-8af3-11eb-384d-29fbb0f66f24
# ╠═316e5074-8af3-11eb-256b-c5b212f7e0d3
# ╠═39a85a58-8af3-11eb-1334-6f50ed9acd31
# ╟─3e83981a-8af3-11eb-3c87-77797adb7e1f
# ╠═3e1c4090-8af3-11eb-33d0-b9c299fef20d
# ╠═4be905b4-8af3-11eb-0344-dbdc7e94ddf3
# ╟─4e8f6cb8-8af3-11eb-1746-9384995d7022
# ╟─54d2a5b8-8af3-11eb-3273-85d551fceb7b
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002

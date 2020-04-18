# # What scientists must know about hardware to write fast code
# 
# Programming is used in many fields of science today, where individual scientists often have to write custom code for their own projects. For most scientists, however, computer science is not their field of expertise; They have learned programming by necessity. I count myself as one of them. While we may be reasonably familiar with the *software* side of programming, we rarely have even a basic understanding of how computer *hardware* impacts code performance.
# 
# The aim of this tutorial is to give non-professional programmers a *brief* overview of the features of modern hardware that you must understand in order to write fast code. It will be a distillation of what have learned the last few years. This tutorial will use Julia because it allows these relatively low-level considerations to be demonstrated easily in a high-level, interactive language.
# 
# ### This is not a guide to the Julia programming language
# To write fast code, you must first understand your programming language and its idiosyncrasies. But this is *not* a guide to the Julia programming language. I recommend reading the [performance tips section](https://docs.julialang.org/en/v1/manual/performance-tips/) of the Julia documentation.
# 
# ### This is not an explanation of specific datastructures or algorithms
# Besides knowing your language, you must also know your own code to make it fast. You must understand the idea behind big-O notation, why some algorithms are faster than others, and how different data structures work internally. Without knowing *what an `Array` is*, how could you possibly optimize code making use of arrays?
# 
# This too, is outside the scope of this paper. However, I would say that as a minimum, a programmer should have an understanding of:
# 
# * How a binary integer is represented in memory
# * How a floating point number is represented in memory (learning this is also necessary to understand computational inacurracies from floating point operations, which is a must when doing scientific programming)
# * The memory layout of a `String` including ASCII and UTF-8 encoding
# * The basics of how an `Array` is structured, and what the difference between a dense array of e.g. integers and an array of references to objects are
# * The principles behind how a `Dict` (i.e. hash table) and a `Set` works
# 
# Furthermore, I would also recommend familiarizing yourself with:
# 
# * Heaps
# * Deques
# * Tuples
# 
# ### This is not a tutorial on benchmarking your code
# To write fast code *in practice*, it is necessary to profile your code to find bottlenecks where your machine spends the majority of the time. One must benchmark different functions and approaches to find the fastest in practice. Julia (and other languages) have tools for exactly this purpose, but I will not cover them here.

# ## Content
# 
# * [Minimize disk writes](#disk)
# * [CPU cache](#cachemisses)
# * [Alignment](#alignment)
# * [Inspect generated assembly](#assembly)
# * [Minimize allocations](#allocations)
# * [Exploit SIMD vectorization](#simd)
# * [Struct of arrays](#soa)
# * [Use specialized CPU instructions](#instructions)
# * [Inline small functions](#inlining)
# * [Unroll tight loops](#unrolling)
# * [Avoid unpredictable branches](#branches)
# * [Multithreading](#multithreading)
# * [GPUs](#gpus)

# ## Before you begin: Install packages

## Install packages
using Pkg

Pkg.add("BenchmarkTools", io=devnull)
Pkg.add("StaticArrays", io=devnull)

using StaticArrays
using BenchmarkTools
#----------------------------------------------------------------------------

# ## The basic structure of computer hardware
# 
# For now, we will work with a simplified mental model of a computer. Through this document, I will add more details to our model as they become relevant.
# 
# <br>
# <center><font size=5>
# [CPU] ↔ [RAM] ↔ [DISK]
# </font></center>
# 
# In this simple diagram, the arrows represent data flow in either direction. The diagram shows three important parts of a computer:
# 
# * The central processing unit (CPU) is a chip the size of a stamp. This is where all the computation actually occurs, the brain of the computer.
# * Random access memory (RAM, or just "memory") is the short-term memory of the computer. This memory requires electrical power to maintain, and is lost when the computer is shut down. RAM serves as a temporary storage of data between the disk and the CPU. Much of time spent "loading" various applications and operating systems is actually spent moving data from disk to RAM and unpacking it there. A typical consumer laptop has around $10^{11}$ bits of RAM memory.
# * The disk is a mass storage unit. This data on disk persists after power is shut down, so the disk contains the long-term memory of the computer. It is also much cheaper per gigabyte than RAM, with consumer PCs having around $10^{13}$ bits of disk space.

# ## Avoid write to disk where possible<a id='disk'></a>
# Even with a fast mass storage unit such as a solid state drive (SSD) or even the newer Optane technology, disks are many times, usually thousands of times, slower than RAM. In particular, *seeks*, i.e. switching to a new point of the disk to read from or write to, is slow. As a consequence, writing a large chunk of data to disk is much faster than writing many small chunks.
# 
# To write fast code, you must therefore make sure to have your working data in RAM, and limit disk writes as much as possible.
# 
# The following example serves to illustrate the difference in speed:

## Open a file
function test_file(path)
    open(path) do file
        ## Go to 1000'th byte of file and read it
        seek(file, 1000)
        read(file, UInt8)
    end
end
@time test_file("../some_file.txt")

## This test may seem weirdly constructed, but I use a Set to force cache misses to compare
## main RAM (and not cache) with disk.
data = Set(1:10000000)
function test_RAM(data)
    n = 0
    for i in 1:25000
        n += i in data
    end
    n
end

@time test_RAM(data);
#----------------------------------------------------------------------------

# Benchmarking this is a little tricky, because the *first* invokation will include the compilation times of both functions. And in the *second* invokation, your operating system will have stored a copy of the file (or *cached* the file) in RAM, making the file seek almost instant. To time it properly, run it once, then *change the file*, and run it again. So in fact, we should update our computer diagram:
# 
# <br>
# <center><font size=5>
# [CPU] ↔ [RAM] ↔ [DISK CACHE] ↔ [DISK]
# </font></center>
# 
# On my computer, finding a single byte in a file takes about 13 miliseconds, and finding 25,000 integers from a `Set` takes 9.5 miliseconds. So RAM is on the order of 34,000 times faster than disk.
# 
# When working with data too large to fit into RAM, load in the data chunk by chunk, e.g. one line at a time, and operate on that. That way, you don't need *random access* to your file and thus need to waste time on extra seeks, but only sequential access. And you *must* strive to write your program such that any input files are only read through *once*, not multiple times.
# 
# If you need to read a file byte by byte, for example when parsing a file, great speed improvements can be found by *buffering* the file. When  buffering, you read in larger chunks, the *buffer*, to memory, and when you want to read from the file, you check if it's in the buffer. If not, read another large chunk into your buffer from the file. This approach minimizes disk reads. Both your operating system and your programming language will make use of caches, however, sometimes [it is necessary to manually buffer your files](https://github.com/JuliaLang/julia/issues/34195).

# ## CPU cache<a id='cachemisses'></a>
# The RAM is faster than the disk, and the CPU in turn is faster than RAM. A CPU ticks like a clock, with a speed of about 3 GHz, i.e. 3 billion ticks per second. One "tick" of this clock is called a *clock cycle*. While this is not really true, you may imagine that every cycle, the CPU executes a single, simple command called a *CPU instruction* which does one operation on a small piece of data. The clock speed then can serve as a reference for other timings in a computer. It is worth realizing that in a single clock cycle, a photon will travel only around 10 cm, and this puts a barrier to how fast memory (which is placed some distance away from the CPU) can operate. In fact, modern computers are so fast that a significant bottleneck in their speed is the delay caused by the time needed for electricity to move through the wires inside the computer.
# 
# On this scale, reading from RAM takes around 100 clock cycles. Similarly to how the slowness of disks can be mitigated by copying data to the faster RAM, data from RAM is copied to a smaller memory chip physically on the CPU, called a *cache*. The cache is faster because it is physically on the CPU chip (reducing wire delays), and because it uses a faster type of RAM, static RAM, instead of the slower (but cheaper to manufacture) dynamic RAM. Because it must be placed on the CPU, limiting its size, and because it is more expensive to produce, a typical CPU cache only contains around $10^8$ bits, around 1000 times less than RAM. There are actually multiple layers of CPU cache, but here we simplify it and just refer to "the cache" as one single thing:
# 
# <br>
# <center><font size=5>
# [CPU] ↔ [CPU CACHE] ↔ [RAM] ↔ [DISK CACHE] ↔ [DISK]
# </font></center>
# 
# When the CPU requests a piece of data from the RAM, say a single byte, it will first check if the memory is already in cache. If so, it will read from it from there. This is much faster, usually just a few clock cycles, than access to RAM. If not, we have a *cache miss*, and your program will stall for tens of nanoseconds while your computer copies data from RAM into the cache.
# 
# It is not possible, except in very low-level languages, to manually manage the CPU cache. Instead, you must make sure to use your cache effectively.
# 
# Effective use of the cache comes down to *locality*, temporal and spacial locality:
# * By *temporal locality*, I mean that data you recently accessed likely resides in cache already. Therefore, if you must access a piece of memory multiple times, make sure you do it close together in time.
# * By *spacial locality*, I mean that you should access data from memory addresses close to each other. Your CPU does not copy *just* the requested bytes to cache. Instead, your CPU will always copy larger chunk of data (usually 512 consecutive bits).
# 
# From this information, one can deduce a number of simple tricks to improve performance:
# * Use as little memory as possible. When your data takes up less memory, it is more likely that your data will be in cache. Remember, a CPU can do approximately 100 small operations in the time wasted by a single cache miss.
# 
# * When reading data from RAM, read it sequentially, such that you mostly have the next data you will be using in cache, instead of in a random order. In fact, modern CPUs will detect if you are reading in data sequentially, and *prefetch* upcoming data, that is, fetching the next chunk while the current chunk is being processed, reducing delays caused by cache misses.
# 
# The following example illustrates two simple functions that iterate over a random array, xor'ing the data. The first function iterates linearly over the array. The second instead uses the current result (which is random) to determine the next index, thus it jumps erratically over the array. On my computer, the second function is *more than 10 times slower* than the first.

function linear_access(data)
    x = 0
    for i in eachindex(data)
        x ⊻= data[i]
    end
    x
end

function random_access(data)
    x = 0
    for i in eachindex(data)
        x ⊻= data[x & 0x00000000000fffff + 1]
    end
    x
end

data = rand(UInt, 0x00000000000fffff);
#----------------------------------------------------------------------------

@btime linear_access(data)
@btime random_access(data);
#----------------------------------------------------------------------------

# This also has implications for your data structures. Hash tables such as `Dict`s and `Set`s are inherently cache inefficient and almost always cause cache misses, whereas arrays don't.
# 
# Many of the optimizations in this document indirectly impact cache use, so this is important to have in mind.

# ## Memory alignment<a id='alignment'></a>
# As just mentioned, your CPU will move 512 consecutive bits (64 bytes) to and from main RAM to cache at a time. These 64 bytes are called a *cache line*. Your entire main memory is segmented into cache lines. For example, memory addresses 0 to 63 is one cache line, addresses 64 to 127 is the next, 128 to 191 the next, et cetera. Your CPU may only request one of these cache lines from memory, and not e.g. the 64 bytes from address 30 to 93.
# 
# This means that some data structures can straddle the boundaries between cache lines. If I request a 64-bit (8 byte) integer at adress 60, this can cause *two* cache misses, the first to get the 0-63 cache line, and the second to get the 64-127 cache line. Even disregaridng the time-consuming cache misses, the CPU must generate two memory addresses from the single requested memory address, and then retrieve the integer from both cache lines, wasting time.
# 
# The time wasted can be significant. In a situation where cache misses provides the bottleneck, the slowdown can approach 2x. In the following example, I use a pointer to repeatedly access an array at a given offset from a cache line boundary. If the offset is in the range `0:56`, the integers all fit within one single cache line, and the function is fast. If the offset is in `57:63` all integers will straddle cache lines.

function alignment_test(data::Vector{UInt}, offset::Integer)
    n = zero(UInt)
    mask = length(data) - 8
    GC.@preserve data begin #### protect the array from moving in memory
        ptr = pointer(data) + (offset & 63)
        for i in 1:1024
            n ⊻= unsafe_load(ptr, (n & mask + 1) % Int)
        end
    end
    return n
end
data = rand(UInt, 256);
#----------------------------------------------------------------------------

@btime alignment_test(data, 10)
@btime alignment_test(data, 60);
#----------------------------------------------------------------------------

# The above example is paticularly bad, having a near 2x slowdown.
# 
# Fortunately, the compiler does a few tricks to make it less likely that you will access misaligned data. First, Julia (and other compiled languages) always places new objects in memory at the boundaries of cache lines. When an object is placed right at the boundary, we say that it is *aligned*. Julia also aligns the beginning of arrays:

memory_address = reinterpret(UInt, pointer(data))
@assert iszero(memory_address % 64)
#----------------------------------------------------------------------------

# Note that if the beginning of an array is aligned, then it's not possible for 1-, 2-, 4-, or 8-byte objects to straddle cache line boundaries, and everything will be aligned.
# 
# It would still be possible for an e.g. 7-byte object to be misaligned in an array. In an array of 7-byte objects, the 10th object would be placed at byte offset $7 \times (10-1) = 63$, and the object would straddle the cache line. However, the compiler usually does not allow struct with a nonstandard size for this reason. If we define a 7-byte struct:

struct AlignmentTest
    a::UInt32 #### 4 bytes +
    b::UInt16 #### 2 bytes +
    c::UInt8  #### 1 byte = 7 bytes?
end
#----------------------------------------------------------------------------

# Then we can use Julia's introspection to get the relative position of each of the three integers in an `AlignmentTest` object in memory:

function get_mem_layout(T)
    for fieldno in 1:fieldcount(T)
        println("Name: ", fieldname(T, fieldno), "\t",
                "Size: ", sizeof(fieldtype(T, fieldno)), " bytes\t",
                "Offset: ", fieldoffset(T, fieldno), " bytes.")
    end
end

println("Size of AlignmentTest: ", sizeof(AlignmentTest), " bytes.")
get_mem_layout(AlignmentTest)
#----------------------------------------------------------------------------

# We can see that, despite an `AlignmentTest` only having 4 + 2 + 1 = 7 bytes of actual data, it takes up 8 bytes of memory, and accessing an `AlignmentTest` object from an array will always be aligned.
# 
# As a coder, there are only a few situations where you can face alignment issues. I can come up with two:
# 
# 1. If you manually create object with a strange size, e.g. by accessing a dense integer array with pointers. This can save memory, but will waste time. [My implementation of a Cuckoo filter](https://github.com/jakobnissen/Probably.jl) does this to save space.
# 2. During matrix operations. If you have a matrix the columns are sometimes unaligned because it is stored densely in memory. E.g. in a 15x15 matrix of `Float32`s, only the first column is aligned, all the others are not. This can have serious effects when doing matrix operations: [I've seen benchmarks](https://chriselrod.github.io/LoopVectorization.jl/latest/examples/matrix_vector_ops/) where an 80x80 matrix/vector multiplication is 2x faster than a 79x79 one due to alignment issues.

# ## Assembly code<a id='assembly'></a>
# To run, any program must be translated, or *compiled* to CPU instructions. The CPU instructions are what is actually running on your computer, as opposed to the code written in your programming language, which is merely a *description* of the program. CPU instructions are usually presented to human beings in *assembly*. Assembly is a programming language which has a one-to-one correspondance with CPU instructions.
# 
# Viewing assembly code will be useful to understand some of the following sections which pertain to CPU instructions.
# 
# In Julia, we can easily inspect the compiled assembly code using the `code_native` function or the equivalent `@code_native` macro. Let's use the `linear_access` function from earlier:

## View assembly code generated from this function call
@code_native linear_access(data)
#----------------------------------------------------------------------------

# Let's break the first 11 lines down:
# 
# ```
# 	.section	__TEXT,__text,regular,pure_instructions
# ; ┌ @ In[3]:3 within `linear_access'
# ; │┌ @ abstractarray.jl:212 within `eachindex'
# ; ││┌ @ abstractarray.jl:95 within `axes1'
# ; │││┌ @ abstractarray.jl:75 within `axes'
# ; ││││┌ @ In[3]:2 within `size'
# 	movq	24(%rsi), %rax
# ; ││││└
# ; ││││┌ @ tuple.jl:139 within `map'
# ; │││││┌ @ range.jl:320 within `OneTo' @ range.jl:311
# ; ││││││┌ @ promotion.jl:412 within `max'
# 	testq	%rax, %rax
# ; │└└└└└└
# ```
# 
# The lines beginning with `;` are comments, and explain which section of the code the following instructions come from. They show the nested series of function calls, and where in the source code they are. You can see that `linear_access` calls `eachindex`, which calls `axes1`, which calls `axes`, which calls `size` and `map`, etc. Under the comment line containing the `size` call, we see the first CPU instruction. The instruction name is on the far left, `movq`. The name is composed of two parts, `mov`, the kind of instruction (to move content to or from a register), and a suffix `q`, short for "quad", which means 64-bit integer. There are the following suffixes:  `b` (byte, 8 bit), `w` (word, 16 bit), `l`, (long, 32 bit) and `q` (quad, 64 bit).
# 
# The next two columns in the instruction, `24(%rsi)` and `%rax` are the arguments to `movq`. These are the names of the registers (we will return to registers later) where the data to operate on are stored.
# 
# You can also see (in the larger display of assembly code) that the code is segmented into sections beginning with a name starting with "L", for example the last section `L131`. These sections are jumped between using if-statements, or *branches*. For example, the actual loop is marked with `L48`. You can see the following two instructions in the `L48` section:
# 
# ```
#     cmpq    %r8, %rcx
# 	jb      L48
# ```
# The first instruction `cmpq` (compare quad) compares the data in the two registers, which hold the data for the length of the array, and the array index, respectively, and sets certain flags (wires) in the CPU based on the result. The next instruction `jb` (jump if below) makes a jump if the "below" flag is set in the CPU, which happens if the index is lower than the array length. You can see it jumps to `L48`, meaning this section repeat.

# ### Fast instruction, slow instruction
# Not all CPU instructions are equally fast. Below is a table of selected CPU instructions with *very rough* estimates of how many clock cycles they take to execute.
# 
# __Fast instructions__ (about 1 clock cycle each)
# ```
# and
# or
# bitshifts
# xor
# add integer
# subtract integer
# bitwise invert
# ```
# 
# __Somewhat fast instructions__
# ```
# float addition (3 cycles)
# multiplication, float or integer (depending on operand size) (5 cycles)
# ```
# 
# __Slow instructions__
# ```
# float divison (25 cycles)
# integer division (30 cycles)
# ```
# 
# __As reference__
# ```
# read from cache (1-5 cycles)
# read to ram (cache miss) (100 cycles)
# memory allocation (400 cycles)
# ```
# 
# If you have an inner loop executing millions of times, it may pay off to inspect the generated assembly code for the loop and check if you can express the computation in terms of fast CPU instructions. For example, if you have an integer you know to be 0 or above, and you want to divide it by 8 (discarding any remainder), you can instead do a bitshift:

divide_slow(x) = div(x, 8)
divide_fast(x) = x >>> 3;
#----------------------------------------------------------------------------

# However, modern compilers are pretty clever, and will often figure out the optimal instructions to use in your functions to obtain the same result, by for example replacing an integer divide `idivq` instruction with a bitshift right (`shrq`) where applicable to be faster. You need to check the assembly code yourself to see:

## Calling it with debuginfo=:none removes the comments in the assembly code
code_native(divide_slow, (UInt,), debuginfo=:none)
#----------------------------------------------------------------------------

# ## Allocations and immutability<a id='allocations'></a>
# As already mentioned, main RAM is much slower than the CPU cache. However, working in main RAM comes with an additional disadvantage: Your operating system (OS) keeps track of which process have access to which memory. If every process had access to all memory, then it would be trivially easy to make a program that scans your RAM for secret data such as bank passwords - or for one program to accidentally overwrite the memory of another program. Instead, every process is allocated a bunch of memory by the OS, and is only allowed to read or write to the allocated data.
# 
# The creation of new objects in RAM is termed *allocation*, and the destruction is called *deallocation*. Really, the (de)allocation is not really *creation* or *destruction* per se, but rather the act of starting and stopping keeping track of the memory. Memory that is not kept track of will eventually be overwritten by other data. Allocation and deallocation take a significant amount of time depending on the size of objects, from a few tens to hundreds of nanoseconds per allocation.
# 
# In programming languages such as Julia, Python, R and Java, deallocation is automatically done using a program called the *garbage collector* (GC). This program keeps track of which objects are rendered unreachable by the programmer, and deallocates them. For example, if you do:

thing = [1,2,3]
thing = nothing
#----------------------------------------------------------------------------

# Then there is no way to get the original array `[1,2,3]` back, it is unreachable. Hence it is simply wasting RAM, and doing nothing. It is *garbage*. Allocating and deallocating objects sometimes cause the GC to start its scan of all objects in memory and deallocate the unreachable ones, which causes significant lag. You can also start the garbage collector manually:

GC.gc()
#----------------------------------------------------------------------------

# The following example illustrates the difference in time spent in a function that allocates a vector with the new result relative to one which simply modifies the vector, allocating nothing:

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

data = rand(UInt, 2^10);
#----------------------------------------------------------------------------

@btime increment(data);
@btime increment!(data);
#----------------------------------------------------------------------------

# On my computer, the allocating function is about 5x slower. This is due to a few properties of the code:
# * First, the allocation itself takes time
# * Second, the allocated objects eventually have to be deallocated, also taking time
# * Third, repeated allocations triggers the GC to run, causing overhead
# * Fourth, more allocations sometimes means less efficient cache use because you are using more memory
# 
# For these reasons, performant code should keep allocations to a minimum. Note that the `@btime` macro prints the number and size of the allocations. This information is given because it is assumed that any programmer who cares to benchmark their code will be interested in reducing allocations.
# 
# ### Not all objects need to be allocated
# Inside RAM, data is kept on either the *stack* or the *heap*. The stack is a simple data structure with a beginning and end, similar to a `Vector` in Julia. The stack can only be modified by adding or subtracting elements from the end, analogous to a `Vector` with only the two mutating operations `push!` and `pop!`. These operations on the stack are very fast. When we talk about "allocations", however, we talk about data on the heap. Only the heap gives true random access.
# 
# Intuitively, it may seem obvious that all objects need to be placed in RAM, must be able to be retrieved at any time by the program, and therefore need to be allocated on the heap. And for some languages, like Python, this is true. However, this is not true in Julia. Integers, for example, can often be placed on the stack.
# 
# Why do some objects need to be heap allocated, while others can be stack allocated? To be stack-allocated, the compiler needs to know for certain that:
# 
# * The object is a fixed, predetermined size, and not too big (max tens of bytes). This is needed for technical reasons for the stack to operate.
# * That the object never changes. The CPU is free to copy stack-allocated objects, and for immutable objects, there is no way to distinguish a copy from the original. This bears repeating: *With immutable objects, there is no way to distinguish a copy from the original*. This gives the compiler and the CPU certain freedoms when operating on it.
# * The compiler can predict exactly *when* it needs to access the program so it can reach it by simply popping the stack. This is usually the case in compiled languages.
# 
# Objects that contain heap-allocated objects have significantly higher overhead in both memory consumption and time spent. In Julia, we have a concept of a *bitstype*, which is an object that recursively contain no heap-allocated objects. Heap allocated objects are objects of types `String`, `Array`, `Ref` and `Symbol`, mutable objects, or objects containing any of the previous. Bitstypes are more performant exactly because they are immutable, fixed in size and can be stack allocated.
# 
# The latter point is also why objects are immutable by default in Julia, and leads to one other performance tip: Use immutable objects whereever possible.

abstract type AllocatedInteger end

struct StackAllocated <: AllocatedInteger
    x::Int
end

mutable struct HeapAllocated <: AllocatedInteger
    x::Int
end
#----------------------------------------------------------------------------

# We can inspect the code needed to instantiate a `HeapAllocated` object with the code needed to instantiate a `StackAllocated` one:

@code_native HeapAllocated(1)
#----------------------------------------------------------------------------

# Notice the `callq` instructions in the `HeapAllocated` one. This instruction calls out to other functions, meaning that in fact, much more code is really needed to create a `HeapAllocated` object that what is displayed. In constrast, the `StackAllocated` really only needs a few instructions:

@code_native StackAllocated(1)
#----------------------------------------------------------------------------

# Because bitstypes dont need to be stored on the heap and can be copied freely, bitstypes are stored *inline* in arrays. This means that bitstype objects can be stored directly inside the array's memory. Non-bitstypes have a unique identity and location on the heap. They are distinguishable from copies, so cannot be freely copied, and so arrays contain reference to the memory location on the heap where they are stored. Accessing such an object from an array then means first accessing the array to get the memory location, and then accessing the object itself using that memory location. Beside the double memory access, objects are stored less efficiently on the heap, meaning that more memory needs to be copied to CPU caches, meaning more cache misses. Hence, even when stored on the heap in an array, bitstypes can be stored more effectively.

Base.:+(x::Int, y::AllocatedInteger) = x + y.x
Base.:+(x::AllocatedInteger, y::AllocatedInteger) = x.x + y.x

data_stack = [StackAllocated(i) for i in rand(UInt16, 1000000)]
data_heap = [HeapAllocated(i.x) for i in data_stack]

@btime sum(data_stack)
@btime sum(data_heap);
#----------------------------------------------------------------------------

# We can verify that, indeed, the array in the `data_stack` stores the actual data of a `StackAllocated` object, whereas the `data_heap` contains pointers (i.e. memory addresses):

println("First object of data_stack: ", data_stack[1])
println("First data in data_stack array: ", unsafe_load(pointer(data_stack)), '\n')

println("First object of data_heap: ", data_heap[1])
first_data = unsafe_load(Ptr{UInt}(pointer(data_heap)))
println("First data in data_heap array: ", repr(first_data))
println("Data at address ", repr(first_data), ": ",
        unsafe_load(Ptr{HeapAllocated}(first_data)))
#----------------------------------------------------------------------------

# ## Registers and SIMD<a id='simd'></a>
# It is time yet again to update our simplified computer schematic. A CPU operates only on data present in *registers*. These are small, fixed size slots (e.g. 8 bytes in size) inside the CPU itself. A register is meant to hold one single piece of data, like an integer or a floating point number. As hinted in the section on assembly code, each instruction usually refers to one or two registers which contain the data the operation works on:
# 
# <br>
# <center><font size=5>
# [CPU] ↔ [REGISTERS] ↔ [CPU CACHE] ↔ [RAM] ↔ [DISK CACHE] ↔ [DISK]
# </font></center>
# 
# To operate on data structures larger than one register, the data must be broken up into smaller pieces that fits inside the register. For example, when adding two 128-bit integers on my computer:

@code_native UInt128(5) + UInt128(11)
#----------------------------------------------------------------------------

# There is no register that can do 128-bit additions. First the lower 64 bits must be added using a `addq` instruction, fitting in a register. Then the upper bits are added with a `adcxq` instruction, which adds the digits, but also uses the carry bit from the previous instruction. Finally, the results are moved 64 bits at a time using `movq` instructions.
# 
# The small size of the registers serves as a bottleneck for CPU throughput: It can only operate on one integer/float at a time. In order to sidestep this, modern CPUs contain specialized 256-bit registers (or 128-bit in older CPUs, or 512-bit in the brand new ones) than can hold 4 64-bit integers/floats at once, or 8 32-bit integers, etc. Confusingly, the data in such wide registers are termed "vectors". The CPU have access to instructions that can perform various CPU operations on vectors, operating on 4 64-bit integers in one instruction. This is called "single instruction, multiple data", *SIMD*, or *vectorization*. Notably, a 4x64 bit operation is *not* the same as a 256-bit operation, e.g. there is no carry-over with between the 4 64-bit integers when you add two vectors. Instead, a 256-bit vector operation is equivalent to 4 individual 64-bit operations.
# 
# We can illustrate this with the following example:

## Create a single statically-sized vector of 8 32-bit integers
## I could also have created 4 64-bit ones, etc.
a = @SVector Int32[1,2,3,4,5,6,7,8]

## Don't add comments to output
code_native(+, (typeof(a), typeof(a)), debuginfo=:none)
#----------------------------------------------------------------------------

# Here, two 8\*32 bit vectors are added together in one single instruction. You can see the CPU makes use of a single `vpaddd` (vector packed add double) instruction to add 8 32-bit integers, as well as the corresponding move instruction `vmovdqu`. Note that vector CPU instructions begin with `v`.
# 
# ### Automatic vectorization
# SIMD vectorization of e.g. 64-bit integers may increase throughput by almost 4x, so it is of huge importance in high-performance programming. Compilers will automatically vectorize operations if they can. What can prevent this automatic vectorization?
# 
# Because vectorized operations operates on multiple data at once, it is not possible to interrupt the loop at an arbitrary point. For example, if 4 64-bit integers are processed at a time, it is not possible to stop the loop after 3 integers have been processed. Suppose you had a loop like this:
# 
# ```
# for i in 1:8
#     if foo()
#         break
#     end
#     # do stuff with my_vector[i]
# end
# ```
# 
# Here, the loop could end on any iteration due to the break statement. Therefore, any SIMD instruction which loaded in multiple integers could operate on data *after* the loop is supposed to break, i.e. data which is never supposed to be read. This would be wrong behaviour, and so, the compiler cannot use SIMD instructions.
# 
# A good rule of thumb is that you should not have any branches (i.e. if-statements) in the loop at all if you want it to SIMD-vectorize. In fact, even boundschecking, i.e. checking that you are not indexing outside the bounds of a vector, causes a branch. After all, if the code is supposed to raise a bounds error after 3 iterations, even a single SIMD operation would be wrong! To achieve SIMD vectorization then, all boundschecks must be disabled. We can use this do demonstrate the impact of SIMD:

function sum_nosimd(x::Vector)
    n = zero(eltype(x))
    for i in eachindex(x)
        n += x[i]
    end
    return n
end

function sum_simd(x::Vector)
    n = zero(eltype(x))
    ## By removing the boundscheck, we allow automatic SIMD
    @inbounds for i in eachindex(x)
        n += x[i]
    end
    return n
end

## Make sure the vector is small enough to fit in cache so we don't time cache misses
data = rand(UInt64, 4096);
#----------------------------------------------------------------------------

@btime sum_nosimd(data)
@btime sum_simd(data);
#----------------------------------------------------------------------------

# On my computer, the SIMD code is 10x faster than the non-SIMD code. SIMD alone accounts for only about 4x improvements (since we moved from 64-bits per iteration to 256 bits per iteration). The rest of the gain comes from not spending time checking the bounds and from automatic loop unrolling (explained later), which is also made possible by the `@inbounds` annotation.
# 
# It's worth mentioning the interaction between SIMD and alignment: If a series of 256-bit (32-byte) SIMD loads are misaligned, then up to half the loads could cross cache line boundaries, as opposed to just 1/8th of 8-byte loads. Thus, alignment is a much more serious issue when using SIMD. Since array beginnings are always aligned, this is usually not an issue, but in cases where you are not guaranteed to start from an aligned starting point, such as with matrix operations, this may make a significant difference. In brand new CPUs with 512-bit registers, the issues is even worse as the SIMD size is the same as the cache line size, so *all* loads would be misaligned if the initial load is.

# ## Struct of arrays<a id='soa'></a>
# If we create an array containing four `AlignmentTest` objects `A`, `B`, `C` and `D`, the objects will lie end to end in the array, like this:
#     
#     Objects: |      A        |       B       |       C       |        D      |
#     Fields:  |   a   | b |c| |   a   | b |c| |   a   | b |c| |   a   | b |c| |
#     Byte:     1               9              17              25              33
#     
# Note again that byte no. 8, 16, 24 and 32 are empty to preserve alignment, wasting memory.
# Now suppose you want to do an operation on all the `.a` fields of the structs. Because the `.a` fields are scattered 8 bytes apart, SIMD operations are much less efficient (loading up to 4 fields at a time) than if all the `.a` fields were stored together (where 8 fields could fit in a 256-bit register). When working with the `.a` fields only, the entire 64-byte cache lines would be read in, of which only half, or 32 bytes would be useful. Not only does this cause more cache misses, we also need instructions to pick out the half of the data from the SIMD registers we need.
# 
# The memory structure we have above is termed an "array of structs", because, well, it is an array filled with structs. Instead we can strucure our 4 objects `A` to `D` as a "struct of arrays". Conceptually, it could look like:

struct AlignmentTestVector
    a::Vector{UInt32}
    b::Vector{UInt16}
    c::Vector{UInt8}
end   
#----------------------------------------------------------------------------

# With the following memory layout for each field:
# 
#     Object: AlignmentTestVector
#     .a |   A   |   B   |   C   |   D   |
#     .b | A | B | C | D |
#     .c |A|B|C|D|
#     
# Alignment is no longer a problem, no space is wasted on padding. When running through all the `a` fields, all cache lines contain full 64 bytes of relevant data, so SIMD operations do not need extra operations to pick out the relevant data:

Base.rand(::Type{AlignmentTest}) = AlignmentTest(rand(UInt32), rand(UInt16), rand(UInt8))

array_of_structs = [rand(AlignmentTest) for i in 1:1000000]
struct_of_arrays = AlignmentTestVector(rand(UInt32, 1000000), rand(UInt16, 1000000), rand(UInt8, 1000000));

@btime sum(x -> x.a, array_of_structs)
@btime sum(struct_of_arrays.a);
#----------------------------------------------------------------------------

# ## Specialized CPU instructions<a id='instructions'></a>
# 
# Most code makes use of only a score of CPU instructions like move, add, multiply, bitshift, and, or, xor, jumps, and so on. However, CPUs in the typical modern laptop support a *lot* of CPU instructions. Typically, if a certain operation is used heavily in consumer laptops, CPU manufacturers will add specialized instructions to speed up these operations. Depending on the hardware implementation of the instructions, the speed gain from using these instructions can be significant.
# 
# Julia only exposes a few specialized instructions, including:
# 
# * The number of set bits in an integer is effectively counted with the `popcnt` instruction, exposed via the `count_ones` function.
# * The `tzcnt` instructions counts the number of trailing zeros in the bits an integer, exposed via the `trailing_zeros` function
# * The order of individual bytes in a multi-byte integer can be reversed using the `bswap` instruction, exposed via the `bswap` function. This can be useful when having to deal with [endianness](https://en.wikipedia.org/wiki/Endianness).
# 
# The following example illustrates the performance difference between a manual implementation of the `count_ones` function, and the built-in version, which uses the `popcnt` instruction:

function manual_count_ones(x)
    n = 0
    while x != 0
        n += x & 1
        x >>>= 1
    end
    return n
end

data = rand(UInt, 10000)
@btime sum(manual_count_ones, data)
@btime sum(count_ones, data);
#----------------------------------------------------------------------------

# The timings you observe here will depend on whether your compiler is clever enough to realize that the computation in the first function can be expressed as a `popcnt` instruction, and thus will be compiled to that. On my computer, the compiler is not able to make that inference, and the second function achieves the same result more than 100x faster.
# 
# ### Call any CPU instruction
# Julia makes it possible to call CPU instructions direcly. This is not generally advised, since not all your users will have access to the same CPU with the same instructions.
# 
# The latest CPUs contain specialized instructions for AES encryption and SHA256 hashing. If you wish to call these instructions, you can call Julia's backend compiler, LLVM, directly. In the example below, I create a function which calls the `vaesenc` (one round of AES encryption) instruction directly:

## This is a 128-bit CPU "vector" in Julia
const __m128i = NTuple{2, VecElement{Int64}}

## Define the function in terms of LLVM instructions
aesenc(a, roundkey) = ccall("llvm.x86.aesni.aesenc", llvmcall, __m128i, (__m128i, __m128i), a, roundkey);
#----------------------------------------------------------------------------

# We can verify it works by checking the assembly of the function, which should contain only a single `vaesenc` instruction, as well as the `retq` (return) and the `nopw` (do nothing, used as a filler to align the CPU instructions in memory) instruction:

@code_native aesenc(__m128i((213132, 13131)), __m128i((31231, 43213)))
#----------------------------------------------------------------------------

# Algorithms which makes use of specialized instructions can be extremely fast. [In a blog post](https://mollyrocket.com/meowhash), the video game company Molly Rocket unveiled a new non-cryptographic hash function using AES instructions which reached unprecedented speeds.

# ## Inlining<a id='inlining'></a>
# Consider the assembly of this function:

## Simply throw an error
f() = error()
@code_native f()
#----------------------------------------------------------------------------

# This code contains the `callq` instruction, which calls another function. A function call comes with some overhead depending on the arguments of the function and other things. While the time spent on a function call is measured in microseconds, it can add up if the function called is in a tight loop.
# 
# However, if we show the assembly of this function:

call_plus(x) = x + 1
code_native(call_plus, (Int,), debuginfo=:none)
#----------------------------------------------------------------------------

# The function `call_plus` calls `+`, and is compiled to a single `leaq` instruction (as well as some filler `retq` and `nopw`). But `+` is a normal Julia function, so `call_plus` is an example of one regular Julia function calling another. Why is there no `callq` instruction to call `+`?
# 
# The compiler has chosen to *inline* the function `+` into `call_plus`. That means that instead of calling `+`, it has copied the *content* of `+` directly into `call_plus`. The advantages of this is:
# * There is no overhead from the function call
# * There is no need to construct a `Tuple` to hold the arguments of the `+` function
# * Whatever computations happens in `+` is compiled together with `call_plus`, allowing the compiler to use information from one in the other and possibly simplify some calculations.
# 
# So why aren't *all* functions inlined then? Inlining copies code, increases the size of it and consuming RAM. Furthermore, the *CPU instructions themselves* also needs to fit into the CPU cache (although CPU instructions have their own cache) in order to be efficiently retrieved. If everything was inlined, programs would be enormous and grind to a halt. Inlining is only an improvement if the inlined function is small.
# 
# Instead, the compiler uses heuristics (rules of thumb) to determine when a function is small enough for inlining to increase performance. These heuristics are not bulletproof, so Julia provides the macros `@noinline`, which prevents inlining of small functions (useful for e.g. functions that raises errors, which must be assumed to be called rarely), and `@inline`, which does not *force* the compiler to inline, but *strongly suggests* to the compiler that it ought to inline the function.
# 
# If code contains a time-sensitive section, for example an inner loop, it is important to look at the assembly code to verify that small functions in the loop is inlined. For example, in [this line in my kmer hashing code](https://github.com/jakobnissen/Kash.jl/blob/b9a6e71acf9651d3614f92d5d4b29ffd136bcb5c/src/kmersketch.jl#L41), overall minhashing performance drops by a factor of two if this `@inline` annotation is removed.
# 
# An extreme difference between inlining and no inlining can be demonstrated thus:

@noinline noninline_poly(x) = x^3 - 4x^2 + 9x - 11
inline_poly(x) = x^3 - 4x^2 + 9x - 11

function time_function(F, x::AbstractVector)
    n = 0
    for i in x
        n += F(i)
    end
    return n
end;
#----------------------------------------------------------------------------

@btime time_function(noninline_poly, data)
@btime time_function(inline_poly, data);
#----------------------------------------------------------------------------

# ## Unrolling<a id='unrolling'></a>
# Consider a function that sums a vector of 64-bit integers. If the vector's data's memory offset is stored in register `%r9`, the length of the vector is stored in register `%r8`, the current index of the vector in `%rcx` and the running total in `%rax`, the assembly of the inner loop could look like this:
# 
# ```
# L1:
#     ; add the integer at location %r9 + %rcx * 8 to %rax
#     addq   (%r9,%rcx,8), %rax
# 
#     ; increment index by 1
#     addq   $1, %rcx
# 
#     ; compare index to length of vector
#     cmpq   %r8, %rcx
# 
#     ; repeat loop if index is smaller
#     jb     L1
# ```
# 
# For a total of 4 instructions per element of the vector. The actual code generated by Julia will be similar to this, but also incluce extra instructions related to bounds checking that are not relevant here (and of course will include different comments).
# 
# However, if the function is written like this:
# 
# ```
# function sum_vector(v::Vector{Int})
#     n = 0
#     i = 1
#     for chunk in 1:div(length(v), 4)
#         n += v[i + 0]
#         n += v[i + 1]
#         n += v[i + 2]
#         n += v[i + 3]
#         i += 4
#     end
#     return n
# end
# ```
# 
# The result is obviously the same if we assume the length of the vector is divisible by four. If the length is not divisible by four, we could simply use the function above to sum the first N - rem(N, 4) elements and add the last few elements in another loop. Despite the functionally identical result, the assembly of the loop is different and may look something like:
# 
# ```
# L1:
#     addq   (%r9,%rcx,8), %rax
#     addq   8(%r9,%rcx,8), %rax
#     addq   16(%r9,%rcx,8), %rax
#     addq   24(%r9,%rcx,8), %rax
#     addq   $4, %rcx
#     cmpq   %r8, %rcx
#     jb     L1
# ```
# 
# For a total of 7 instructions per 4 additions, or 1.75 instructions per addition. This is less than half the number of instructions per integer! The speed gain comes from simply checking less often when we're at the end of the loop. We call this process *unrolling* the loop, here by a factor of four. Naturally, unrolling can only be done if we know the number of iterations beforehand, so we don't "overshoot" the number of iterations. Often, the compiler will unroll loops automatically for extra performance, but it can be worth looking at the assembly. For example, this is the assembly for the innermost loop generated on my computer for `sum([1])`:
# 
#     L144:
#         vpaddq  16(%rcx,%rax,8), %ymm0, %ymm0
#         vpaddq  48(%rcx,%rax,8), %ymm1, %ymm1
#         vpaddq  80(%rcx,%rax,8), %ymm2, %ymm2
#         vpaddq  112(%rcx,%rax,8), %ymm3, %ymm3
#         addq    $16, %rax
#         cmpq    %rax, %rdi
#         jne L144
# 
# Where you can see it is both unrolled by a factor of four, and uses 256-bit SIMD instructions, for a total of 128 bytes, 16 integers added per iteration, or 0.44 instructions per integer.

# ## Branch prediction<a id='branches'></a>
# When a CPU executes instructions, every instruction needs to go through multiple steps, classically the three "fetch", "decode" and "execute" steps, each taking one clock cycle or more. Thus, a CPU instruction must take multiple clock cycles. However, the steps use different circuits of the CPU, and so while one instruction is being executed, another is being decoded and a third is being fetched. This results in much faster throughput, in theory one instruction per cycle.
# 
# This also means that CPU instructions are being "queued" into the *pipeline* some time before they are actually executed in the final execute step. So what happens when the CPU encounters a branch (i.e. a jump instruction)? It can't know which instruction to queue next, because that depends on the instruction that it just put into the queue and which has yet to be executed.
# 
# Modern CPUs make use of *branch prediction*. The CPU has a *branch predictor* circuit, which guesses the correct branch based on which branches were recently taken. In essense, the branch predictor attempts to learn simple patterns in which branches are taken in code, while the code is running. After queueing a branch, the CPU immediately queues instructions from whatever branch predicted by the branch predictor. The correctness of the guess is verified later, when the queued branch is being executed. If the guess was correct, great, the CPU saved time by guessing. If not, the CPU has to empty the pipeline and discard all computations since the initial guess, and then start over. This process causes a delay of a few nanoseconds.
# 
# For the programmer, this means that the speed of an if-statement depends on how easy it is to guess. If it is trivially easy to guess, the branch predictor will be correct almost all the time, and the if statement will take no longer than a simple instruction, typically 1 clock cycle. In a situation where the branching is random, it will be wrong about 50% of the time, and each misprediction may cost around 10 clock cycles.
# 
# Branches caused by loops are among the easiest to guess. If you have a loop with 1000 elements, the code will loop back 999 times and break out of the loop just once. Hence the branch predictor can simply always predict "loop back", and get a 99.9% accuracy.
# 
# We can demonstrate the performance of branch misprediction with a simple function:

## Copy all odd numbers from src to dst.
function copy_odds!(dst::Vector{UInt}, src::Vector{UInt})
    write_index = 1
    @inbounds for i in eachindex(src) #### <--- this branch is trivially easy to predict
        v = src[i]
        if isodd(v)  #### <--- this is the branch we want to predict
            dst[write_index] = v
            write_index += 1
        end
    end
    return dst
end

dst = rand(UInt, 5000)
src_random = rand(UInt, 5000)
src_all_odd = [2i+1 for i in src_random];
#----------------------------------------------------------------------------

@btime copy_odds!(dst, src_random)
@btime copy_odds!(dst, src_all_odd);
#----------------------------------------------------------------------------

# In the first case, the integers are random, and about half the branches will be mispredicted causing delays. In the second case, the branch is always taken, the branch predictor is quickly able to pick up the pattern and will reach near 100% correct prediction. As a result, on my computer, the latter is around 6x faster.
# 
# Note that if you use smaller vectors and repeat the computation many times, as the `@btime` macro does, the branch predictor is able to learn the pattern of the small random vectors by heart, and will reach much better than random prediction. This is especially pronounced in the most modern CPUs where the branch predictors have gotten much better. This "learning by heart" is an artifact of the loop in the benchmarking process. You would not expect to run the exact same computation repeatedly on real-life data:

src_random = rand(UInt, 100)
src_all_odd = [2i+1 for i in src_random];
#----------------------------------------------------------------------------

@btime copy_odds!(dst, src_random)
@btime copy_odds!(dst, src_all_odd);
#----------------------------------------------------------------------------

# Because branches are very fast if they are predicted correctly, highly predictable branches caused by error checks are not of much performance concern, assuming that the code essensially never errors. Hence a branch like bounds checking is very fast. You should only remove bounds checks if absolutely maximal performance is critical, or if the bounds check happens in a loop which would otherwise SIMD-vectorize.
# 
# If branches cannot be easily predicted, it is often possible to re-phrase the function to avoid branches all together. For example, in the `copy_odds!` example above, we could instead write it like so:

function copy_odds!(dst::Vector{UInt}, src::Vector{UInt})
    write_index = 1
    @inbounds for i in eachindex(src)
        v = src[i]
        dst[write_index] = v
        write_index += isodd(v)
    end
    return dst
end

dst = rand(UInt, 5000)
src_random = rand(UInt, 5000)
src_all_odd = [2i+1 for i in src_random];
#----------------------------------------------------------------------------

@btime copy_odds!(dst, src_random)
@btime copy_odds!(dst, src_all_odd);
#----------------------------------------------------------------------------

# Which contains no other branches than the one caused by the loop itself (which is easily predictable), and results in speeds somewhat worse than the perfectly predicted one, but much better for random data.
# 
# The compiler will often remove branches in your code when the same computation can be done using other instructions. When the compiler fails to do so, Julia offers the `ifelse` function, which sometimes can help elide branching.

# ## Variable clock speed
# 
# A modern laptop CPU optimized for low power consumption consumes roughly 25 watts of power on a chip as small as a stamp (and thinner than a human hair). Without proper cooling, this will cause the temperature of the CPU to skyrocket and melting the plastic of the chip, destroying it. Typically, CPUs have a maximal operating temperature of about 100 degrees C. Power consumption, and therefore heat generation, depends among many factors on clock speed, higher clock speeds generate more heat.
# 
# Modern CPUs are able to adjust their clock speeds according to the CPU temperature to prevent the chip from destroying itself. Often, CPU temperature will be the limiting factor in how quick a CPU is able to run. In these situations, better physical cooling for your computer translates directly to a faster CPU. Old computers can often be revitalized simply by removing dust from the interior, and replacing the cooling fans and [CPU thermal paste](https://en.wikipedia.org/wiki/Thermal_grease)!
# 
# As a programmer, there is not much you can do to take CPU temperature into account, but it is good to know. In particular, variations in CPU temperature often explain observed difference in performance:
# 
# * CPUs usually work fastest at the beginning of a workload, and then drop in performance as it reaches maximal temperature
# * SIMD instructions usually require more power than ordinary instructions, generating more heat, and lowering the clock frequency. This can offset some performance gains of SIMD, but SIMD will still always be more efficient when applicable

# ## Multithreading<a id='multithreading'></a>
# In the bad old days, CPU clock speed would increase every year as new processors were brought onto the market. Partially because of heat generation, this acceleration slowed down once CPUs hit the 3 GHz mark. Now we see only minor clock speed increments every processor generation. Instead of raw speed of execution, the focus has shifted on getting more computation done per clock cycle. CPU caches, CPU pipelining, branch prediction and SIMD instructions are all important progresses in this area, and have all been covered here.
# 
# Another important area where CPUs have improved is simply in numbers: Almost all CPU chips contain multiple smaller CPUs, or *cores* inside them. Each core has their own small CPU cache, and does computations in parallel. Furthermore, many CPUs have a feature called *hyper-threading*, where two *threads* (i.e. streams of instructions) are able to run on each core. The idea is that whenever one process is stalled (e.g. because it experiences a cache miss or a misprediction), the other process can continue on the same core. The CPU "pretends" to have twice the amount of processors. For example, I am writing this on a laptop with an Intel Core i5-8259U CPU. This CPU has 4 cores, but various operating systems like Windows or Linux would show 8 "CPUs" in the systems monitor program.
# 
# Hyperthreading only really matters when your threads are sometimes prevented from doing work. Besides CPU-internal causes like cache misses, a thread can also be paused because it is waiting for an external resource like a webserver or data from a disk. If you are writing a program where some threads spend a significant time idling, the core can be used by the other thread, and hyperthreading can show its value.
# 
# Let's see our first parallel program in action. First, we need to make sure that Julia actually was started with the correct number of threads. You can set the environment variable `JULIA_NUM_THREADS` before starting Julia. I have 4 cores on this CPU, both with hyperthreading so I have set the number of threads to 8:

Threads.nthreads()
#----------------------------------------------------------------------------

## Spend about half the time waiting, half time computing
function half_asleep(start::Bool)
    a, b = 1, 0
    for iteration in 1:5
        start && sleep(0.06)
        for i in 1:100000000
            a, b = a + b, a
        end
        start || sleep(0.06)
    end
    return a
end

function parallel_sleep(n_jobs)
    jobs = []
    for job in 1:n_jobs
        push!(jobs, Threads.@spawn half_asleep(isodd(job)))
    end
    return sum(fetch, jobs)
end

parallel_sleep(1); ##run once to compile it 
#----------------------------------------------------------------------------

for njobs in (1, 4, 8, 16)
    @time parallel_sleep(njobs);
end
#----------------------------------------------------------------------------

# You can see that with this task, my computer can run 8 jobs in parallel almost as fast as it can run 1. But 16 jobs takes much longer.
# 
# For CPU-constrained programs, the core is kept busy with only one thread, and there is not much to do as a programmer to leverage hyperthreading. Actually, for the most optimized programs, it usually leads to better performance to *disable* hyperthreading. Most workloads are not that optimized and can really benefit from hyperthreading, so we'll stick with 8 threads for now.
# 
# #### Parallelizability
# Multithreading is more difficult that any of the other optimizations, and should be one of the last tools a programmer reaches for. However, it is also an impactful optimization. Compute clusters usually contain CPUs with tens of CPU cores, offering a massive potential speed boost ripe for picking.
# 
# A prerequisite for efficient use of multithreading is that your computation is able to be broken up into multiple chunks that can be worked on independently. Luckily the majority of compute-heavy tasks (at least in my field of work, bioinformatics), contain sub-problems that are *embarassingly parallel*. This means that there is a natural and easy way to break it into sub-problems that can be processed independently. For example, if a certain __independent__ computation is required for 100 genes, it is natural to use one thread for each gene.
# 
# Let's have an example of a small embarrasingly parallel problem. We want to construct a [Julia set](https://en.wikipedia.org/wiki/Julia_set). Julia sets are named after Gaston Julia, and have nothing to do with the Julia language. Julia sets are (often) fractal sets of complex numbers. By mapping the real and complex component of the set's members to the X and Y pixel value of a screen, one can generate the LSD-trippy images associated with fractals.
# 
# The Julia set I create below is defined thus: We define a function $f(z) = z^2 + C$, where $C$ is some constant. We then record the number of times $f$ can be applied to any given complex number $z$ before $|z| > 2$. The number of iterations correspond to the brightness of one pixel in the image. We simply repeat this for a range of real and imaginary values in a grid to create an image.
# 
# First, let's see a non-parallel solution:

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
function julia()
    M = Matrix{UInt8}(undef, 5000, 5000)
    for (x, real) in enumerate(range(-1.0f0, 1.0f0, length=size(M, 2)))
        fill_column!(M, x, real)
    end
    return M
end;
#----------------------------------------------------------------------------

@time M = julia();
#----------------------------------------------------------------------------

# That took around 3 seconds on my computer. Now for a parallel one:

function recursive_fill_columns!(M::Matrix, cols::UnitRange)
    F, L = first(cols), last(cols)
    ## If only one column, fill it using fill_column!
    if F == L
        r = range(-1.0f0,1.0f0,length=5000)[F]
        fill_column!(M, F, r)
    ## Else divide the range of columns in two, spawning a new task for each half
    else
        mid = div(L+F,2)
        p = Threads.@spawn recursive_fill_columns!(M, F:mid)
        recursive_fill_columns!(M, mid+1:L)
        wait(p)
    end
end

function julia()
    M = Matrix{UInt8}(undef, 5000, 5000)
    recursive_fill_columns!(M, 1:5000)
    return M
end;
#----------------------------------------------------------------------------

@time M = julia();
#----------------------------------------------------------------------------

# This is almost 7 times as fast! This is close to the best case scenario for 8 threads, only possible for near-perfect embarrasingly parallel tasks.
# 
# Despite the potential for great gains, in my opinion, multithreading should be one of the last resorts for performance improvements, for three reasons:
# 
# 1. Implementing multithreading is harder than other optimization methods in many cases. In the example shown, it was very easy. In a complicated workflow, it can get messy quickly.
# 2. Multithreading can cause hard-to-diagnose and erratic bugs. These are almost always related to multiple threads reading from, and writing to the same memory. For example, if two threads both increment an integer with value `N` at the same time, the two threads will both read `N` from memory and write `N+1` back to memory, where the correct result of two increments should be `N+2`! Infuriatingly, these bugs appear and disappear unpredictably, since they are causing by unlucky timing. These bugs of course have solutions, but it is tricky subject outside the scope of this document.
# 3. Finally, achieving performance by using multiple threads is really achieving performance by consuming more resources, instead of gaining something from nothing. Often, you pay for using more threads, either literally when buying cloud compute time, or when paying the bill of increased electricity consumption from multiple CPU cores, or metaphorically by laying claim to more of your users' CPU resources they could use somewhere else. In contrast, more *efficent* computation costs nothing.

# ## GPUs<a id='gpus'></a>
# So far, we've covered only the most important kind of computing chip, the CPU. But there are many other kind of chips out there. The most common kind of alternative chip is the *graphical processing unit* or GPU.
# 
# As shown in the above example with the Julia set, the task of creating computer images are often embarassingly parallel with an extremely high degree of parallelizability. In the limit, the value of each pixel is an independent task. This calls for a chip with a high number of cores to do effectively. Because generating graphics is a fundamental part of what computers do, nearly all commercial computers contain a GPU. Often, it's a smaller chip integrated into the motherboard (*integrated graphics*, popular in small laptops). Other times, it's a large, bulky card.
# 
# GPUs have sacrificed many of the bells and whistles of CPUs covered in this document such as specialized instructions, SIMD and branch prediction. They also usually run at lower frequencies than CPUs. This means that their raw compute power is many times slower than a CPU. To make up for this, they have a high number of cores. For example, the high-end gaming GPU NVIDIA RTX 2080Ti has 4,352 cores. Hence, some tasks can experience 10s or even 100s of times speedup using a GPU. Most notably for scientific applications, matrix and vector operations are highly parallelizable.
# 
# Unfortunately, the laptop I'm writing this document on has only integrated graphics, and there is not yet a stable way to interface with integrated graphics using Julia, so I cannot show examples.
# 
# There are also more esoteric chips like TPUs (explicitly designed for low-precision tensor operations common in deep learning) and ASICs (an umbrella term for highly specialized chips intended for one single application). At the time of writing, these chips are uncommon, expensive, poorly supported and have limited uses, and are therefore not of any interest for non-computer science researchers.

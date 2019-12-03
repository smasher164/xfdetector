## XFDetector: Cross-Failure Bug Detection in Persistent Memory Programs

## Table of Contents
* [Introduction to XFDetector](#introduction-to-xfdetector)
* [Installation](#installation)
  * [Hardware Dependencies](#hardware-dependencies)
  * [Software Dependencies](#software-dependencies)
  * [Build XFDetector](#build-xfdetector)
  * [Build Test Workloads](#build-test-workloads)
* [Testing and Reporducing Bugs](#testing-and-reproducing-bugs)


## Introduction to XFDetector
Persistent memory (PM) technologies, such as Intel's Optane memory, deliver high performance, byte-addressability and persistence, allowing program to directly manipulate persistent data in memory without OS overhead. 
An important requirement of these programs is that persistent data must remain consistent across a failure, which we refer to as the crash consistency guarantee.

However, maintaining crash consistency is not trivial --- consistency depends critically on the order of persistent memory access in both *pre-failure* and *post-failure* execution. 
Because hardware may reorder persistent memory accesses both before and after failure, validation of crash-consistent programs requires holistic analysis of both execution stages.
We categorize the underlying causes behind inconsistent recovery due to incorrect interaction between the pre-failure and post-failure execution. First, a program is not crash consistent 
if the post-failure stage reads from locations that are not guaranteed to have persisted in all possible access interleavings during the pre-failure stage --- an error that we refer to as a *cross-failure race*.
Second, a program is not crash consistent 
if the post-failure stage reads persistent data that  has been left semantically inconsistent during the pre-failure stage, such as a stale log or uncommitted data, which we call a *cross-failure semantic bug*.
Together, we call these *cross-failure bugs*. 
In this work, we propose XFDetector, a tool that detects cross-failure bugs by considering failures injected at all ordering points in pre-failure execution and checking for cross-failure races and cross-failure semantic bugs in the post-failure continuation.
XFDetector has detected four new bugs in three pieces of PM software: one of PMDK examples, a PM-optimized Redis database and a  PMDK library function.


## Installation
This repository is organized as the following structure:
* `xfdetector/`: The source code of our tool.
* `pmdk/`: Intel's [PMDK](https://pmem.io/) library, including its example PM programs.
* `redis-nvml/`: A Redis implementation (from [Intel](https://github.com/pmem/redis/tree/3.2-nvml)) based on PMDK (PMDK was previously named as NVML).
* `memcached-pmem/`: A Memcached implementation (from [Lenovo](https://github.com/lenovo/memcached-pmem)) based on Intel's PMDK library. 
* `patch/`: Patches for reproducing bugs and trying our tool

### Hardware Dependencies
XFDetector targets workloads that directly manage the persistent data on PM through a DAX file system. To support these workloads, the hardware needs to provide a persistent memory device, either by using real PM (Intel Optane DC Persistent Memory) or emulating PM with DRAM. To enable efficient writeback of persistent data, the processor also requires the CLWB instrcution in both real and emulated platforms. 

The following is a list of requirements:
#### Real PM system 
* CPU: Intel 2nd Generation Xeon Scalable Processor (Gold or Platinum)
* Memory: Intel Optane DC Persistent Memory (at least 1x 128GB DIMM) and DDR4 RDIMM (at least 1x 16GB DMM).

Please refer to Intel's [guide](https://software.intel.com/en-us/articles/quick-start-guide-configure-intel-optane-dc-persistent-memory-on-linux) to initialize DC persistent memory in App Direct mode. In the rest of this documentation, we assume the PM device is mounted on `/mnt/pmem0`.

#### Emulated PM system
* CPU: Intel 1st/2nd Generation Xeon Scalable, or Skylake-X Processor.
(As far as we know, they are the only Intel processors that supports the CLWB instrcution)
* Memory: at least DDR4 32GB (16GB of which will be emulated as PM)

Steps for PM emulation (Assuming that the system has a minimum of 32GB of DRAM):  
1. Create "PM" Device:
	Edit `/etc/default/grub` with sudo privilege, and add the following line to the end of the file:

		GRUB_CMDLINE_LINUX="memmap=16G!16G"

	Save the changes and execute:

		# update-grub2

2. After reboot, you shall see a new "PM" device: `/dev/pmem0`

3. Mount the "PM" device:

	First, format `/dev/pmem0` as EXT4:

		# mkfs.ext4 -F /dev/pmem0

	Then create a mounting point. We will be using `pmem0` in the rest of this documentation:

		# mkdir /mnt/pmem0

	Mount the device to the mounting point with DAX option:

		# mount -o dax /dev/pmem0 /mnt/pmem0

   Confirm the DAX option is successfully enabled:
    
	   $ mount | grep dax

   You should see something similar to: `/dev/pmem0 on /mnt/pmem0 type ext4 (rw,relatime,dax)`  
   To access the newly created PM device without sudo privilege, change the owndership to your own username:
  
        # chown -R <username> /mnt/pmem0

  Note that the emulated PM device will disappear everytime system restarts. So you will need to *execute the steps in (3) everytime the system boots*. 
For more details about emulating PM, please refer to PMDK's [documentation](https://pmem.io/2016/02/22/pm-emulation.html).


### Software Dependencies
The following is a list of software dependencies for XFDetector and test workloads (the listed versions have been tested, other versions might work but not guaranteed):   
* OS: Ubuntu 18.04 (kernel 4.15 or higher)   
* Compiler: g++/gcc-7
* Libraries: libboost-1.65, ndctl-61.2   

Other dependent libraries for the workloads are contained in this repository. 

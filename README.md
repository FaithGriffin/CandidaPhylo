## To run script ##

1. [Download Anaconda for Linux](https://www.anaconda.com/products/distribution)  
   
2. Run `conda install -c conda-forge miniwdl` command.

3. Edit `Candida-Pylo.inputs.json`. Specifically, CandidaPhylo.input_samples, CandidaPhylo.input_fastqs_1, and CandidaPhylo.input_fastqs_2

4. Run `miniwdl run [-i INPUT.json] [-o OUT.json]`

MATLAB Parameter Sweep Utility
------------------------------

An important step in DSP algorithm design is parameter selection, which is often accomplished by sweeping over combinations of many different parameters.  Writing code to perform a parameter sweep is time consuming, tedious, and clutters your application code.  The MATLAB Parameter Sweep Utility allows you to setup and perform parameter sweeps quickly.

The MATLAB Parameter Sweep Utility is:
 - **Clean**: Perform parameter sweeps in a single line.
 - **Easy to use**: Organized results structure, with execution times, for easy analysis.
 - **Flexible**: Works with scripts, functions, or function handles.  Cluster mode.  Large number of options.
 - **Fast**: Small performance penalty over an application-specific parameter sweep.

See documentation in sweep.m

Todo:
 - Easier method to save/combine results in "cluster mode"
 - Option to automatically average/median multiple trials?
 - Option to turn off status print
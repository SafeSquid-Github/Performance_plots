# Performance_plots
Generate SafeSquids performance plots using GNU Plots

#How to use auto_plot.sh

auto_plot.sh <-u ><[options]>
-i,		Make ini for auto_plot
-m,		Monitor auto_plot.ini file
-u,		Update monit configuration file
-p,		Generates GNU plot without any required configuration file.
		You can find the plots at /var/www/safesquid/<file_name>
-h,		Prints this help menu

**EXAMPLES:**
To generate plot for desired time run
auto_plot.sh <time range>
Example1: ```auto_plot.sh today```
Example2: ```auto_plot.sh 10 hours ago```
Example3: ```auto_plot.sh last day```
Example4: ```auto_plot.sh 2 days day```
Example5: ```auto_plot.sh last week```
Example6: ```auto_plot.sh -p today```
when auto_plot.sh is execute without any options plots are genearete as per set default plot time
Default plot time is set in auto_plot.ini file.

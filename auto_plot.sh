#!/bin/bash
# This script analyses SafeSquid's performance.log and auto generates performance plots based on the set frequency
####################################################
THIS_PROCESS=$BASHPID
TAG="auto_plot.performance"
NOW=$(date +"%Y%m%d%H%M%S")
if [[ -t 1 ]]; then
    exec 1> >( exec logger --id=${THIS_PROCESS} -s -t "${TAG}" ) 2>&1
else
    exec 1> >( exec logger --id=${THIS_PROCESS} -t "${TAG}" ) 2>&1
fi

#Path for your auto_plot ini file
AUTO_PLOT_INI=/opt/extras/autoplot/auto_plot.ini

#make ini file for auto_plot script
MAKE_INI () {

	echo "INFO: CREATING A NEW INI FILE: ${AUTO_PLOT_INI}"
	> "${AUTO_PLOT_INI}"
	cat <<- _EOF >> "${AUTO_PLOT_INI}"
	#File path for performance.log file
	#Configuration directory for auto_plot
	CONF_DIR="/opt/safesquid/auto_plot"
	#performance log file used for plotting.
	PERFORMANCE_LOG_FILE="/var/log/safesquid/performance/performance.log"
	#Default plot time is used in situations where time input has not been provided by user, it will use the default plot time to generate the reports.
	DEFAULT_PLOT_TIME="1 hour ago"
	#Output directory for the plots to be stored.
	PLOT_DIR="/var/www/safesquid/plots"
	#advance plot directory structure, used to have a tree like structure for plot out.
	#Set value: advance_plot_dir_off-0, advance_plot_dir_with_year-1,advance_plot_dir_with_month-2,advance_plot_dir_with_year_month-3,advance_plot_dir_with_month_week_number-6,advance_plot_dir_with_year_month_week_number-7,advance_plot_dir_with_year_month_week_number_day-8
	ADVANCE_PLOT_DIR="8"
	#Plot title that is centered at the top of the plot
	REPORT_TITLE="Analysis of Safesquid Performance Logs"
	#Monit file to monitor changes in ini file
	MONITOR_INI="${CONF_DIR}/monitor_ini.monit"
	#auto_plot.monit config path
	AUTO_PLOT_MONIT_CONFIG="${CONF_DIR}/plot.monit"
	#Local monit configuration path.
	MONIT_CONFIG_PATH="/etc/monit/conf.d/"
	#Configure auto plot to generate plot based on the set intervals., set 1 to monit plot and set 0 to turn off monit plot.
	AUTO_PLOT_NONIT="1"
	#Monit plot time select, select all which is required.
	#add time range using comma to seprate out values.
	#Available vaules: HOUR,DAY,WEEK,FORTNIGHT,MONTH,YEAR
	MONIT_PLOT_TIME="DAY,WEEK"
	_EOF
}

#Help function for using this script
HELP () {     
	#How to use#
    echo "USAGE:"
    echo "${0:2} <-u ><[options]>"
    echo "-i,		Make ini for auto_plot"
	echo "-m,		Monitor auto_plot.ini file"
	echo "-u,		Update monit configuration file"
	echo "-h,		Prints this help menu"
	echo ""
	echo "EXAMPLES:"
	echo "To generate plot for desired time run"
	echo "auto_plot.sh <time range>"
	echo "Example1: auto_plot.sh today"
	echo "Example2: auto_plot.sh 10 hours ago"
	echo "Example3: auto_plot.sh last day"
	echo "Example4: auto_plot.sh 2 days day"
	echo "Example5: auto_plot.sh last week"
	echo "when auto_plot.sh is execute without any options plots are genearete as per set default plot time"
	echo "Default plot time is set in auto_plot.ini file."
}

#Monitor init using monit, if file update create a new monit configuration file.
MONITOR_INI () {

	[ ! -d "${CONF_DIR}" ] && mkdir -p "${CONF_DIR}"
	[ "x${PERFORMANCE_LOG_FILE}" == "x" ] && echo "ERROR: LOG FILE NOT FOUND: ${PERFORMANCE_LOG_FILE}" && exit 1
	> "${MONITOR_INI}"
	cat <<- _EOF >> "${MONITOR_INI}"
	#Dynamic monit configuration file created via auto_plot.sh
	#monitor for changes in ini file.
	check FILE auto_plot_ini with path "${AUTO_PLOT_INI}"
		if changed checksum
			then exec "/usr/local/bin/auto_plot.sh -u"
	_EOF
	[ -f "${MONITOR_INI}" ] && ln -sfv "${MONITOR_INI}" "${MONIT_CONFIG_PATH}"
	monit -t && monit reload
}

#auto_plot monit using the given set time.
MAKE_MONIT_CONFIG () {

	declare -A AUTO_PLOTS
	AUTO_PLOTS["HOUR"]="0 * * * *"
	AUTO_PLOTS["DAY"]="0 0 * * *"
	AUTO_PLOTS["WEEK"]="0 0 * * 7"
	AUTO_PLOTS["FORTNIGHT"]="0 0 1,16 * *"
	AUTO_PLOTS["MONTH"]="0 0 1 * *"
	AUTO_PLOTS["YEAR"]="0 0 1 1 * *"

	[ ! -d "${CONF_DIR}" ] && mkdir -p "${CONF_DIR}"
	> "${AUTO_PLOT_MONIT_CONFIG}"
	while read -r  TIME_RANGE
	do	
	cat <<- _EOF >> "${AUTO_PLOT_MONIT_CONFIG}"
	#Dynamic monit configuration file created via auto_plot.sh
	#Performance plots to be generated every ${TIME_RANGE,,}
	check FILE performance_plots_every_${TIME_RANGE,,} with path "${PERFORMANCE_LOG_FILE}"
		every "${AUTO_PLOTS[${TIME_RANGE}]}"
		if changed checksum
			then exec "/usr/local/bin/auto_plot.sh last ${TIME_RANGE,,}"

	_EOF
	done < <(echo "${MONIT_PLOT_TIME}" | tr ',' '\n')
}

#Create a symlink for plot.monit configuration file and reload monit.
PLOT_WITH_MONIT () {

	MAKE_MONIT_CONFIG
	[ -f "${AUTO_PLOT_MONIT_CONFIG}" ] && ln -sfv "${AUTO_PLOT_MONIT_CONFIG}" "${MONIT_CONFIG_PATH}"
	monit -t && monit reload
}

#Remove symlink for plot.monit configuration file and reload monit.
PLOT_WITHOUT_MONIT () {

	[ ! -h ${MONIT_CONFIG_PATH}/$(basename ${AUTO_PLOT_MONIT_CONFIG}) ] && return 0
	unlink "${MONIT_CONFIG_PATH}/$(basename ${AUTO_PLOT_MONIT_CONFIG})"
	monit -t && monit reload
}

#Check if auto_plot_monit is to be configured, if yes then load the configuration file.
CONFIGURE_PLOT_MONIT () {

	[ "x${AUTO_PLOT_NONIT}" == "x0" ] && PLOT_WITHOUT_MONIT
	[ "x${AUTO_PLOT_NONIT}" == "x1" ] && PLOT_WITH_MONIT
}

#Set out dir for gnuplot to out the file.
SET_PLOT_DIR () {

	ADV_DIR=""
	local YEAR=$(date +%Y)
	local MONTH=$(date +%B)
	local WEEK=WEEK-0$(( 1 + $(date +%V) - $(date +%V -d $(date +%Y-%m-01))))
	local DAY=$(date +%A)
	[ "x${ADVANCE_PLOT_DIR}" == "x0" ]
	[ "x${ADVANCE_PLOT_DIR}" == "x1" ] && ADV_DIR="${YEAR}"
	[ "x${ADVANCE_PLOT_DIR}" == "x2" ] && ADV_DIR="${MONTH}"
	[ "x${ADVANCE_PLOT_DIR}" == "x3" ] && ADV_DIR="${YEAR}/${MONTH}"
	[ "x${ADVANCE_PLOT_DIR}" == "x6" ] && ADV_DIR="${MONTH}/${WEEK}"
	[ "x${ADVANCE_PLOT_DIR}" == "x7" ] && ADV_DIR="${YEAR}/${MONTH}/${WEEK}"
	[ "x${ADVANCE_PLOT_DIR}" == "x8" ] && ADV_DIR="${YEAR}/${MONTH}/${WEEK}/${DAY}"
	PLOT_OUT_DIR="${PLOT_DIR}/${ADV_DIR}"
	#Create plot directory if not present
	[ ! -d "${PLOT_OUT_DIR}" ] && echo "INFO: ADDING DIRECTORY: "${PLOT_OUT_DIR}"" && mkdir -p "${PLOT_OUT_DIR}"
}

#get start and end time for last week
GET_WEEK () {

	local TS=$(date --date="$D" +"%F")
	local W=$(date --date="${TS}" +"%w")
	BW=$(date --date="${TS} -${W} days" +"%F"); 
    EW=$(date --date="${BW} +6 days" +"%F")
}

#get start and end time for last month
GET_MONTH () {

	local TS=$(date --date="$D" +"%F")
	BM=$(date --date="${TS}" +"%Y-%m-01")
	EM=$(date --date="${BM} +1 month" +"%F")
}

#Set Start time for the plot
SET_S_TIME () {

	[ "x${D}" == "xtoday" ] && START_TIME=$(date +%Y%m%d000000) && return 0
	[ "x${D}" == "last day" ] && START_TIME=$(date --date="-1 day" +%Y%m%d000000) && return 0
	[ "x${D}" == "xlast week" ] && GET_WEEK && START_TIME=$(date --date="${BW}" +"%Y%m%d%H%M") && return 0
	[ "x${D}" == "xlast month" ] && GET_MONTH && START_TIME=$(date --date="${BM}" +"%Y%m%d%H%M") && return 0
	[ "x${D}" == "xall time" ] && START_TIME=$(awk -F',' 'FNR==3 {print $1}' "${PERFORMANCE_LOG_FILE}") && return 0
	START_TIME=$(date '+%Y%m%d%H%M' --date="${D}")
}

#Set end time for the plot
SET_E_TIME () {

	[ "x${D}" == "last day" ] && END_TIME=$(date --date="-1 day" +%Y%m%d2400) && return 0
	[ "x${D}" == "xlast week" ] && GET_WEEK && END_TIME=$(date --date="${EW}" +"%Y%m%d%H%M") && return 0
	[ "x${D}" == "xlast month" ] && GET_MONTH && END_TIME=$(date --date="${EM}" +"%Y%m%d%H%M") && return 0
	[ "x${D}" == "xall time" ] && END_TIME=$(tail -n 1 "${PERFORMANCE_LOG_FILE}" | awk -F',' '{print $1}') && return 0
	END_TIME=$(date '+%Y%m%d%H%M')
}

#Get the start time and the end time for the plot
#if user arguments are not found use default plot time
#Exit if start time and end time is not found.
#Set plot file name.
PLOT_RANGE () {

	local D=${@,,}
	[ "x${#}" == "x0" ] && local D="${DEFAULT_PLOT_TIME}"
	SET_S_TIME
	SET_E_TIME
	[ "x${START_TIME}" == "x" ] && echo "ERROR: INVALID TIME SELECTION: ${D}" && exit 1
	[ "x${END_TIME}" == "x" ] && echo "ERROR: INVALID TIME SELECTION: ${D}" && exit 1

	local ST="${START_TIME:8:12}"
	local ET="${END_TIME:8:12}"
	PLOT_OUT_FILENAME="$(date --date="${S_DATE:0:8}" +%a%b%Y_)${ST}-$(date --date=${E_DATE:0:8} +%a%b%Y_)${ET}_performance.png"
}

#Start ploting performance grahp.
PLOT () {

	A="${START_TIME}"
	B="${END_TIME}"

	echo "INFO: PLOTTING: STARTED: $(date +%Y-%m-%d.%H:%M:%S.%N)"
	ST=$(date +%s)

	PLOT_WIDTH=1200
	PLOT_OUT="${PLOT_OUT_DIR}/${PLOT_OUT_FILENAME}"

	/usr/bin/gnuplot <<- _EOF
	##### template #####

	# total number of plots
	t=18.0
	# width of individual plots
	w=${PLOT_WIDTH}
	# height of individual plots
	h=150
	# left margin
	l=30
	# right margin
	r=l

	set datafile commentschars "#T"
	set terminal pngcairo interlace truecolor size w,(( t * h) + ( 19 * 25) + h ) font 'Courier Bold,9'
	# Define colors usingng linecolor keyword
	set linetype 1 lc rgb "#1A9c37cf" # Plot_Purple  
	set linetype 2 lc rgb "#BF057503" # Plot_Green
	set linetype 3 lc rgb "#6625d4ff" # Plot_Blue 
	set linetype 4 lc rgb "#73e5f300" # Plot_Lemon_Yellow
	set linetype 5 lc rgb "#80dda400" # Plot_Golden_Yellow
	set style line 6 lc rgb '#00000000' lt 1 lw 1 # Plot_grid_Black
	set style line 7 lc rgb '#00000000' lt 0 lw 1 # Plot_grid_Black
						
	set output "${PLOT_OUT}"

	set timefmt "%Y%m%d%H%M%S"  
	set xdata time  	# The x axis data is time
	# set format x "%Y-%m-%d %H:%M:%S" 	# On the x-axis, we want tics like Jun 10
	# Input file contains comma-separated values fields  
	set datafile separator "," 

	#setting plot border and grid 
	set border ls 6
	set tics nomirror
	set grid back ls 7

	set xtics border mirror out
	set ytics border nomirror out
	set y2tics border nomirror out
	set key off
	set xtics autofreq
	set autoscale y ; set autoscale y2 ; set autoscale x
	set xrange ["${START_TIME}":"${END_TIME}"]
	show xrange
	n=l/3
	d=0
	set grid
	set multiplot layout t,1 rowsfirst title "${REPORT_TITLE}\n${RESTART}"
	set bmargin 0
	set tmargin 1
	set rmargin r
	set lmargin l

	# set key outside rmargin center vertical

	set macros
	set format x ""

	plot_reset = " d=(d == 0 ? n : 0 ) ; j=1 ; unset label; unset logscale y ; unset autoscale y; unset autoscale y2 ; set autoscale y ; set autoscale y2 ;"
	lreset = "c = l - d -1;"
	left_side = "at graph 0,0  rotate left  tc lt j offset -c,0 ; c= c - 2 ; j=j + 1 ;"
	right_side = "at graph 1,0  rotate left  tc lt j offset c,0 ; c= c - 2 ; j=j + 1 ;"
	##### Connections #####
	# first plot
	@plot_reset
	# chart 1
	PLOT1="Concurrent Client Connections"
	PLOT2="Concurrent Active Requests"

	#print PLOT1
	#print PLOT2
	@lreset
	set label j PLOT1 @left_side
	@lreset
	set label j PLOT2 @right_side
	plot \
		"${PERFORMANCE_LOG_FILE}" using 1:(\$3-\$4) ti PLOT1 w impulses lw 2,\
		"${PERFORMANCE_LOG_FILE}" using 1:(\$8) ti PLOT2 w impulses lw 2 axes x1y2 

	##### Incoming Pressure #####
	@plot_reset
	# chart 2
	PLOT4="New Incoming Connections"
	PLOT5="Client Connections in Pool"
	#print PLOT4
	#print PLOT5
	@lreset
	set label j PLOT4 @left_side
	@lreset
	set label j PLOT5 @right_side

	plot \
		"${PERFORMANCE_LOG_FILE}" using 1:32 ti PLOT4 w impulses lw 2, \
		"${PERFORMANCE_LOG_FILE}" using 1:6 ti PLOT5 w impulses lw 2 axes x1y2

	##### Request Handling #####
	@plot_reset
	# chart 3
	PLOT7="Client Transactions Handled"
	PLOT8="Outbound Connections demanded"
	#print PLOT7
	#print PLOT8
	@lreset
	set label j PLOT7 @left_side
	@lreset
	set label j PLOT8 @right_side

	plot \
		"${PERFORMANCE_LOG_FILE}" using 1:34 ti PLOT7 w impulses lw 2 axes x1y1, \
		"${PERFORMANCE_LOG_FILE}" using 1:(\$42 + \$43 + +\$44 + \$51) ti PLOT8 w impulses lw 2 axes x1y2
	##### - #####

	##### WAN Pressure #####
	@plot_reset
	# chart 4
	PLOT13="Outbound Connection Pool Reused"
	PLOT14="Outbound Connections in Pool"
	#print PLOT13
	#print PLOT14
	@lreset
	set label j PLOT13 @left_side
	@lreset
	set label j PLOT14 @right_side

	plot \
		"${PERFORMANCE_LOG_FILE}" using 1:44 ti PLOT13 w impulses lw 2,\
		"${PERFORMANCE_LOG_FILE}" using 1:16 ti PLOT14 w impulses lw 2 axes x1y2

	# Network Pressure
	@plot_reset
	# chart 5
	PLOT3="Total TCP Connections"
	PLOT4="Idle TCP Connections"
	#print PLOT3
	#print PLOT4

	@lreset
	set label j PLOT3 @left_side

	@lreset
	set label j PLOT4 @right_side
	plot \
		"${PERFORMANCE_LOG_FILE}" using 1:(\$3 - \$4 + \$42 + \$16) ti PLOT3 w impulses lw 2,\
		"${PERFORMANCE_LOG_FILE}" using 1:(\$6 + \$16) ti PLOT4 w impulses lw 2 axes x1y2
		
		
	##### Data Xfer #####
	# Data Xfer
	@plot_reset
	# chart 6
	PLOT16="Bytes In (MBytes)"
	PLOT17="Bytes Out (MBytes)"
	#print PLOT16
	#print PLOT17
	@lreset
	set label j PLOT16 @left_side

	@lreset
	set label j PLOT17 @right_side

	plot \
		"${PERFORMANCE_LOG_FILE}" using 1:(\$46 / 1048576) ti PLOT16 w impulses lw 2,\
		"${PERFORMANCE_LOG_FILE}" using 1:(\$47 / 1048576) ti PLOT17 w impulses lw 2 axes x1y2
	##### Caching #####

	# Caching
	@plot_reset
	# chart 7
	PLOT18="Caching Objects in Memory"
	PLOT19="Caching Objects Removed from Memory"
	PLOT20="Caching Objects Added into Memory"
	#print PLOT18
	#print PLOT19
	#print PLOT20
	@lreset
	set label j PLOT18 @left_side
	set label j PLOT19 @left_side

	@lreset
	set label j PLOT20 @right_side

	plot "${PERFORMANCE_LOG_FILE}" using 1:(\$19-\$20) ti PLOT18 w impulses lw 2,\
		"${PERFORMANCE_LOG_FILE}" using 1:49 ti PLOT19 w impulses lw 2 axes x1y2,\
		"${PERFORMANCE_LOG_FILE}" using 1:48 ti PLOT20 w impulses lw 2 axes x1y2

	##### DNS #####
	@plot_reset
	# chart 8
	PLOT22="New DNS Queries"
	PLOT23="DNS Query Reused"
	#print PLOT22
	#print PLOT23
	@lreset
	set label j PLOT22 @left_side

	@lreset
	set label j PLOT23 @right_side

	plot \
		"${PERFORMANCE_LOG_FILE}" using 1:51 ti PLOT22 w impulses lw 2 ,\
		"${PERFORMANCE_LOG_FILE}" using 1:50 ti PLOT23 w impulses lw 2 axes x1y2

	##### Threading Capacity #####
	@plot_reset
	# chart 9
	PLOT8="Spare Client Threads"
	PLOT9="Client Threads in Use"
	PLOT10="Client Threads in Waiting"

	#print PLOT8
	#print PLOT9
	#print PLOT10

	@lreset
	set label j PLOT8 @left_side

	@lreset
	set label j PLOT9 @right_side
	set label j PLOT10 @right_side

	plot \
		"${PERFORMANCE_LOG_FILE}" using 1:7 ti PLOT8 w lines lw 2,\
		"${PERFORMANCE_LOG_FILE}" using 1:8 ti PLOT9 w impulses lw 2 axes x1y2,\
		"${PERFORMANCE_LOG_FILE}" using 1:9 ti PLOT10 w impulses lw 1 axes x1y2
	##### System Memory #####

	# System Memory
	PLOT24="Total System Memory (GBytes)"
	PLOT25="Free System Memory (MBytes)"
	@plot_reset
	# chart 10
	#print PLOT24
	#print PLOT25
	@lreset
	set label j PLOT24 @left_side

	@lreset
	set label j PLOT25 @right_side
	plot \
		"${PERFORMANCE_LOG_FILE}" using 1:(\$24 / 1048576) ti PLOT24 w lines lw 2,\
		"${PERFORMANCE_LOG_FILE}" using 1:(\$25 / 1024) ti PLOT25 w impulses lw 2 axes x1y2

	##### SafeSquid Memory #####
	# SafeSquid Memory
	PLOT26="SafeSquid Virtual Memory (MBytes)"
	PLOT27="SafeSquid Library Memory (MBytes)"
	PLOT28="SafeSquid Resident Memory (MBytes)" 
	PLOT29="SafeSquid Shared Memory (MBytes)" 
	PLOT30="SafeSquid Code Memory (MBytes)" 
	PLOT31="SafeSquid Data Memory (MBytes)" 

	@plot_reset
	# chart 11
	#print PLOT26
	#print PLOT27
	#print PLOT28
	#print PLOT29
	#print PLOT30
	#print PLOT31

	@lreset
	set label j PLOT26 @left_side
	set label j PLOT27 @left_side

	@lreset
	set label j PLOT28 @right_side
	set label j PLOT29 @right_side
	set label j PLOT30 @right_side
	set label j PLOT31 @right_side

	plot \
		"${PERFORMANCE_LOG_FILE}" using 1:(\$26 / 1024) ti PLOT26 w lines lw 2,\
		"${PERFORMANCE_LOG_FILE}" using 1:(\$31 / 1024) ti PLOT27 w lines lw 2,\
		"${PERFORMANCE_LOG_FILE}" using 1:(\$27 / 1024) ti PLOT28 w lines lw 2 axes x1y2,\
		"${PERFORMANCE_LOG_FILE}" using 1:(\$28 / 1024) ti PLOT29 w lines lw 2 axes x1y2,\
		"${PERFORMANCE_LOG_FILE}" using 1:(\$29 / 1024) ti PLOT30 w lines lw 2 axes x1y2,\
		"${PERFORMANCE_LOG_FILE}" using 1:(\$30 / 1024) ti PLOT31 w lines lw 2 axes x1y2

	##### Errors #####
	# Errors
	PLOT32="DNS Query failures"
	PLOT33="Outbound Connections Failed"
	PLOT34="Threading Errors"

	@plot_reset
	# chart 12
	#print PLOT32
	#print PLOT33
	#print PLOT34

	@lreset
	set label j PLOT32 @left_side
	set label j PLOT33 @left_side

	@lreset
	set label j PLOT34 @right_side

	plot \
		"${PERFORMANCE_LOG_FILE}" using 1:52 ti PLOT32 w impulses lw 2,\
		"${PERFORMANCE_LOG_FILE}" using 1:43 ti PLOT33 w impulses lw 2 axes x1y2,\
		"${PERFORMANCE_LOG_FILE}" using 1:41 ti PLOT34 w impulses lw 2 axes x1y2

	##### System Load #####
	# System Load
	PLOT35="load avg.(1 min)"
	PLOT36="load avg.(5 min)"
	PLOT37="load avg.(15 min)"

	@plot_reset
	# chart 13
	#print PLOT35
	#print PLOT36
	#print PLOT37

	@lreset
	set label j PLOT35 @left_side

	@lreset
	set label j PLOT36 @right_side
	set label j PLOT37 @right_side

	plot \
		"${PERFORMANCE_LOG_FILE}" using 1:53 ti PLOT35 w steps lw 2,\
		"${PERFORMANCE_LOG_FILE}" using 1:54 ti PLOT36 w steps lw 2 axes x1y2,\
		"${PERFORMANCE_LOG_FILE}" using 1:55 ti PLOT37 w steps lw 2 axes x1y2

	##### CPU Switching #####
	# CPU Switching
	PLOT38="Running Processes"
	PLOT39="Waiting Processes"

	@plot_reset
	# chart 14
	#print PLOT38
	#print PLOT39

	@lreset
	set label j PLOT38 @left_side

	@lreset
	set label j PLOT39 @right_side

	plot \
		"${PERFORMANCE_LOG_FILE}" using 1:56 ti PLOT38 w impulses lw 2,\
		"${PERFORMANCE_LOG_FILE}" using 1:57 ti PLOT39 w impulses lw 2 axes x1y2

	##### CPU Utilization 1 #####
	# CPU Utilization
	@plot_reset
	# chart 15
	PLOT43="Total CPU Use Delta (msecs)"
	PLOT44="User Time (msecs)"
	PLOT45="System Time (msecs)"
	#print PLOT43
	#print PLOT44
	#print PLOT45
	@lreset
	set label j PLOT43 @left_side
	@lreset
	set label j PLOT44 @right_side
	set label j PLOT45 @right_side
	plot \
		"${PERFORMANCE_LOG_FILE}" using 1:(\$63 * 1000) ti PLOT43 w impulses lw 2, \
		"${PERFORMANCE_LOG_FILE}" using 1:(\$61 * 1000) ti PLOT44 w lines lw 2 axes x1y2, \
		"${PERFORMANCE_LOG_FILE}" using 1:(\$62 * 1000) ti PLOT45 w lines lw 2 axes x1y2
		
	##### CPU Utilization 2 #####
	# CPU Utilization
	PLOT40="Total CPU Use Trend"
	PLOT41="User Time Trend"
	PLOT42="System Time Trend"

	@plot_reset
	# chart 16
	#print PLOT40
	#print PLOT41
	#print PLOT42
	@lreset
	set label j PLOT40 @left_side
	@lreset
	set label j PLOT41 @right_side
	set label j PLOT42 @right_side
	plot \
		"${PERFORMANCE_LOG_FILE}" using 1:( (\$60 + \$63 ) / \$2) ti PLOT40 w steps  lw 2,\
		"${PERFORMANCE_LOG_FILE}" using 1:( (\$58 + \$61 ) / \$2) ti PLOT41 w steps  lw 2 axes x1y2, \
		"${PERFORMANCE_LOG_FILE}" using 1:( (\$59 + \$62) / \$2) ti PLOT42 w steps  lw 2 axes x1y2

	##### Process Life #####
	# last plot must LOG time as the significant x values
	set format x "%Y-%m-%d %H:%M:%S"
	set xtics rotate
	@plot_reset
	# chart 17
	set logscale y2
	PLOT46="SafeSquid Virtual Memory (MBytes)"
	PLOT47="Process Age"
		
	#print PLOT46
	#print PLOT47

	@lreset
	set label j PLOT46 @left_side
	@lreset
	set label j PLOT47 @right_side
		
	plot \
		"${PERFORMANCE_LOG_FILE}" using 1:(\$26 / 1024 ) ti PLOT46 w lines  lw 2 axes x1y1,\
		"${PERFORMANCE_LOG_FILE}" using 1:2 ti PLOT47 w lines lw 2  axes x1y2	
		
	# last plot
	set bmargin 0
	##### - #####

	unset multiplot
	exit
	_EOF

	ET=$(date +%s)
	echo "INFO: PLOTTING COMPLETE: REPORT GENERATED"
	echo "INFO: PROCESSING TIME: $[ ${ET} - ${ST} ] SECONDS"
}

#Plot SafeSquid performance log
#If log source not found exit the script
MAIN () {
	PERFORMANCE_LOG_FILE="/var/log/safesquid/performance/performance.log"
	#Check if INI file is not found and create if not found.
	[ ! -f "${AUTO_PLOT_INI}" ] && echo "ERROR: INI FILE NOT FOUND: ${AUTO_PLOT_INI}" && MAKE_INI
	source "${AUTO_PLOT_INI}"
	[ "x${PERFORMANCE_LOG_FILE}" == "x" ] && echo "ERROR: LOG FILE NOT FOUND: ${PERFORMANCE_LOG_FILE}" && exit 1
	PLOT_RANGE "${@}"
	SET_PLOT_DIR
	PLOT
}

#Generate plot
PLOT_NOW () {
	PERFORMANCE_LOG_FILE="/var/log/safesquid/performance/performance.log"
	PLOT_OUT_DIR="/var/www/safesquid"
	PLOT_RANGE "${OPTARG}"
	PLOT
}

#Select option 
options="huimp:"
while getopts $options option
do
   case $option in      
		h) # display Help            
			HELP;; 
		i) #make ini file
			MAKE_INI;;  
		m) #monitor ini file
			MONITOR_INI;;
		u) #update monit config
			CONFIGURE_PLOT_MONIT;;
		p) #Plot graph without any configuration
			PLOT_NOW;;
		\?) # incorrect option            
			echo "Error: Invalid option"
			exit;;         
	esac
done

#Execute the main function if no options are provided.
[ "x${OPTIND}" == "x1" ] && MAIN "${@}"

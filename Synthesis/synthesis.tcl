#############################################################################
# Stage 1 — Logic Synthesis (Design Compiler)
# Generalized script — replace every $VARIABLE before running in dc_shell
#############################################################################

#### USER VARIABLES — edit these for your project ####
set DESIGN_NAME     "your_design_name"
set RTL_PATH        "./rtl"
set LIB_PATH        "./lib"
set OUTPUT_PATH     "./outputs"
set TECH_LIB        "your_tech_lib"        ;# e.g. saed90nm_typ
set MACRO_LIB       "your_macro_lib"       ;# leave blank list entry if none

set CLK_NAME        "clk"
set CLK_PORT        "clk"
set CLK_PERIOD_NS   10.0
set UNCERTAINTY_NS  0.2
set INPUT_DELAY_NS  1.0
set OUTPUT_DELAY_NS 1.0
set DRIVING_CELL    "BUFX2"
set OUTPUT_LOAD_PF  0.05
########################################################

set search_path [list . $LIB_PATH $RTL_PATH]
set target_library "$TECH_LIB.db"
set link_library   "* $TECH_LIB.db $MACRO_LIB.db"
set symbol_library "$TECH_LIB.sdb"

file mkdir $OUTPUT_PATH
file mkdir reports

# --- Read RTL ---
# Add/remove file entries as needed for your module hierarchy
read_verilog [glob $RTL_PATH/*.v]
current_design $DESIGN_NAME
link

# --- Constraints (SDC) ---
create_clock -name $CLK_NAME -period $CLK_PERIOD_NS [get_ports $CLK_PORT]
set_clock_uncertainty $UNCERTAINTY_NS [get_clocks $CLK_NAME]
set_input_delay  $INPUT_DELAY_NS  -clock $CLK_NAME [remove_from_collection [all_inputs] [get_ports $CLK_PORT]]
set_output_delay $OUTPUT_DELAY_NS -clock $CLK_NAME [all_outputs]
set_driving_cell -lib_cell $DRIVING_CELL [remove_from_collection [all_inputs] [get_ports $CLK_PORT]]
set_load $OUTPUT_LOAD_PF [all_outputs]

# --- Compile strategy ---
ungroup -all -flatten
set_fix_multiple_port_nets -all -buffer_constants

# --- Compile ---
compile_ultra -no_autoungroup

# --- Reports ---
report_timing  -delay_type max -max_paths 10 > reports/${DESIGN_NAME}_timing.rpt
report_area                                  > reports/${DESIGN_NAME}_area.rpt
report_power                                 > reports/${DESIGN_NAME}_power.rpt
report_qor                                   > reports/${DESIGN_NAME}_qor.rpt
check_design                                 > reports/${DESIGN_NAME}_check_design.rpt

# --- Outputs ---
write -format verilog -hierarchy -output $OUTPUT_PATH/${DESIGN_NAME}_netlist.v
write_sdc $OUTPUT_PATH/${DESIGN_NAME}_constraints.sdc

puts "Stage 1 (Synthesis) complete. Check reports/ for QoR before proceeding to Stage 2."

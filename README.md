# Stage 1 — Logic Synthesis (Design Compiler)

## What this stage does

Synthesis translates synthesizable RTL (Verilog/VHDL) into a gate-level netlist made of
cells from your target standard-cell library, while meeting the timing, area, and power
constraints you specify. Design Compiler (DC) does this through a sequence of
translation, mapping, and optimization passes, guided entirely by the constraints you
give it — DC will always try to meet the SDC (Synopsys Design Constraints) you supply,
even if that means poor QoR, so getting constraints right matters more than any single
compile switch.

## Why it matters

Every later stage inherits synthesis's decisions. A netlist synthesized with slack
constraints, no proper clock definition, or unconstrained loads will fight you all the
way through place-and-route and STA. Synthesis is also where you decide whether you're
targeting a **flat** or **hierarchical** compile — flattening (removing RTL hierarchy)
generally gives DC more freedom to optimize across module boundaries and is often
preferred over tools like Yosys for this reason when a full commercial license is
available, since DC's flattening + mapping is co-optimized with its own timing engine.

![Synthesis mapping](../images/01_synthesis_mapping.svg)

## Inputs

- Synthesizable RTL (no non-synthesizable constructs — see note below)
- Technology library: `.db` (Synopsys binary library) for the standard-cell library,
  covering the corners you care about (e.g., worst-case slow, best-case fast, typical)
- SDC: clock definitions, I/O delays, false paths, multicycle paths, load/drive
  constraints

## Outputs

- Gate-level netlist (`.v`)
- Constraints carried forward (`.sdc`)
- Synthesis reports: timing (`report_timing`), area (`report_area`), power
  (`report_power`), QoR (`report_qor`)

## A note on synthesizable RTL

DC will not synthesize behavioral constructs meant only for simulation. The most common
offender is an `initial` block used to set a reset or initial value — this has no
hardware equivalent and must be rewritten as a proper synchronous (or asynchronous)
reset described entirely with clocked always-blocks. If your RTL was written for
simulation-only testbenches first, budget time to rewrite every module's reset
methodology before synthesis, not after — catching this at Formality (Stage 3) instead
of here costs much more rework.

## Step-by-step flow

### 1. Set up library and search paths

```tcl
set search_path [list . $LIB_PATH $RTL_PATH]
set target_library "$TECH_LIB.db"
set link_library   "* $TECH_LIB.db $MACRO_LIB.db"
set symbol_library "$TECH_LIB.sdb"
```

### 2. Read RTL

```tcl
read_verilog [list $RTL_PATH/$DESIGN_NAME.v \
                    $RTL_PATH/${DESIGN_NAME}_submodule1.v \
                    $RTL_PATH/${DESIGN_NAME}_submodule2.v]
current_design $DESIGN_NAME
link
```

### 3. Apply constraints (SDC)

```tcl
create_clock -name $CLK_NAME -period $CLK_PERIOD_NS [get_ports $CLK_PORT]
set_clock_uncertainty $UNCERTAINTY_NS [get_clocks $CLK_NAME]
set_input_delay  $INPUT_DELAY_NS  -clock $CLK_NAME [all_inputs]
set_output_delay $OUTPUT_DELAY_NS -clock $CLK_NAME [all_outputs]
set_driving_cell -lib_cell $DRIVING_CELL [all_inputs]
set_load $OUTPUT_LOAD_PF [all_outputs]
```

### 4. Set compile strategy (flatten vs hierarchical)

```tcl
# Flatten hierarchy for cross-boundary optimization (recommended default)
ungroup -all -flatten

set_fix_multiple_port_nets -all -buffer_constants
```

### 5. Compile

```tcl
compile_ultra -no_autoungroup
# or, for a design with scan/DFT to be inserted at this stage:
# compile_ultra -no_autoungroup -scan
```

### 6. Generate reports

```tcl
report_timing  -delay_type max -max_paths 10 > reports/${DESIGN_NAME}_timing.rpt
report_area                                  > reports/${DESIGN_NAME}_area.rpt
report_power                                 > reports/${DESIGN_NAME}_power.rpt
report_qor                                   > reports/${DESIGN_NAME}_qor.rpt
check_design                                 > reports/${DESIGN_NAME}_check_design.rpt
```

### 7. Write outputs

```tcl
write -format verilog -hierarchy -output $OUTPUT_PATH/${DESIGN_NAME}_netlist.v
write_sdc $OUTPUT_PATH/${DESIGN_NAME}_constraints.sdc
write_script > $OUTPUT_PATH/${DESIGN_NAME}_compile.log
```

## How to know this stage passed

- `check_design` reports no unresolved references or floating pins
- Worst negative slack (WNS) in `report_timing` is non-negative, or within a slack budget
  you've deliberately allowed for downstream recovery
- No latches inferred unless intentional (`report_timing -unconstrained` and checking for
  `check_timing` warnings about missing clock/reset paths)
- Area and power reports are within the budget for your target node/library

## Files in this folder

- `synthesis.tcl` — full generalized script combining the steps above, ready to be
  sourced in `dc_shell` after editing the variables at the top

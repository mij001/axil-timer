# icarus for the directed bench, verilator for lint and the assertions, xsim
# for the uvm bench because uvm needs a simulator that ships it. targets are
# listed in the readme
#
# xsim and uvm come from vivado. set XILINX_DIR if yours is somewhere else
# rtl/common, tb/common and sva/ are the reusable bits. axil-uart16550 takes this
# repo as a submodule for them

SIMDIR  := sim
SEED    ?= 1
TNTRANS ?= 3000
NITEMS  ?= 2000

SVA := sva/axil_sva.sv

RTL := rtl/common/axil_reg_bus.sv rtl/timer/axil_timer_regs.sv \
       rtl/timer/axil_timer_core.sv rtl/timer/axil_timer.sv
TB  := tb/common/axil_checker.sv tb/timer/timer_model.sv tb/timer/tb_axil_timer.sv
XILINX_DIR ?= /opt/Xilinx/2026.1/Vivado
XSIM_BIN   := $(XILINX_DIR)/bin
UVM := $(RTL) tb/uvm/axil_if.sv tb/uvm/axil_pkg.sv tb/uvm/tb_axil_timer_uvm.sv

VFLAGS := --binary --timing --assert -Wno-fatal

all: lint run uvm

$(SIMDIR):
	@mkdir -p $(SIMDIR)

$(SIMDIR)/tb_axil_timer.vvp: $(RTL) $(TB) | $(SIMDIR)
	iverilog -g2012 -o $@ $^

run: $(SIMDIR)/tb_axil_timer.vvp
	vvp $(SIMDIR)/tb_axil_timer.vvp +seed=$(SEED) +ntrans=$(TNTRANS)

regress: $(SIMDIR)/tb_axil_timer.vvp
	@for s in 1 2 3 4 5 6 7 8 9 10; do \
	  vvp $(SIMDIR)/tb_axil_timer.vvp +seed=$$s +ntrans=$(TNTRANS) | grep -E '^RESULT' | sed "s/^/seed $$s: /"; \
	done

$(SIMDIR)/timer_sva: $(RTL) $(SVA) $(TB) | $(SIMDIR)
	@echo "  verilating the directed bench with assertions"
	@verilator $(VFLAGS) --top-module tb_axil_timer \
	  -Mdir $(SIMDIR)/obj_sva -o ../timer_sva $^ > $(SIMDIR)/build_sva.log 2>&1 \
	  || (cat $(SIMDIR)/build_sva.log; false)

sva: $(SIMDIR)/timer_sva
	$(SIMDIR)/timer_sva +seed=$(SEED) +ntrans=$(TNTRANS)

$(SIMDIR)/xsim/.built: $(UVM) $(wildcard tb/uvm/*.svh) | $(SIMDIR)
	@mkdir -p $(SIMDIR)/xsim
	@echo "  xvlog + xelab, uvm from $(XILINX_DIR)"
	@cd $(SIMDIR)/xsim && $(XSIM_BIN)/xvlog -sv -L uvm -i ../../tb/uvm \
	  $(addprefix ../../,$(UVM)) > xvlog.log 2>&1 || (cat xvlog.log; false)
	@cd $(SIMDIR)/xsim && $(XSIM_BIN)/xelab -L uvm tb_axil_timer_uvm -s timer_uvm \
	  --timescale 1ns/1ps > xelab.log 2>&1 || (cat xelab.log; false)
	@touch $@

uvm: $(SIMDIR)/xsim/.built
	@cd $(SIMDIR)/xsim && $(XSIM_BIN)/xsim timer_uvm -R \
	  -testplusarg UVM_TESTNAME=axil_test_random -testplusarg nitems=$(NITEMS) \
	  | grep -E 'MONITOR|SCOREBOARD|COVERAGE|COVER|RESULT|UVM_ERROR|UVM_FATAL'

lint:
	verilator --lint-only -Wall --top-module axil_timer $(RTL)

waves: $(SIMDIR)/tb_axil_timer.vvp
	@for sc in write_aw_first write_w_first write_same_cycle read_stall oneshot w1c_collision prescale_shrink; do \
	  vvp $(SIMDIR)/tb_axil_timer.vvp +scenario=$$sc | grep WAVE_START | sed "s/^/$$sc /"; \
	done

clean:
	rm -rf $(SIMDIR)

.PHONY: all lint run regress sva uvm waves clean

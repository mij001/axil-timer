# icarus and verilator. targets are listed in the readme

SIMDIR  := sim
SEED    ?= 1

RTL := rtl/common/axil_reg_bus.v rtl/timer/axil_timer_regs.v \
       rtl/timer/axil_timer_core.v rtl/timer/axil_timer.v

$(SIMDIR):
	@mkdir -p $(SIMDIR)

lint:
	verilator --lint-only -Wall --top-module axil_timer $(RTL)

clean:
	rm -rf $(SIMDIR)

.PHONY: lint clean

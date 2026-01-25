# icarus and verilator. targets are listed in the readme

SIMDIR  := sim
SEED    ?= 1
TNTRANS ?= 3000

RTL := rtl/common/axil_reg_bus.v rtl/timer/axil_timer_regs.v \
       rtl/timer/axil_timer_core.v rtl/timer/axil_timer.v
TB  := tb/common/axil_checker.v tb/timer/timer_model.v tb/timer/tb_axil_timer.v

all: lint run

$(SIMDIR):
	@mkdir -p $(SIMDIR)

$(SIMDIR)/tb_axil_timer.vvp: $(RTL) $(TB) | $(SIMDIR)
	iverilog -g2005 -o $@ $^

lint:
	verilator --lint-only -Wall --top-module axil_timer $(RTL)

run: $(SIMDIR)/tb_axil_timer.vvp
	vvp $(SIMDIR)/tb_axil_timer.vvp +seed=$(SEED) +ntrans=$(TNTRANS)

regress: $(SIMDIR)/tb_axil_timer.vvp
	@for s in 1 2 3 4 5 6 7 8 9 10; do \
	  vvp $(SIMDIR)/tb_axil_timer.vvp +seed=$$s +ntrans=$(TNTRANS) | grep -E '^RESULT' | sed "s/^/seed $$s: /"; \
	done

waves: $(SIMDIR)/tb_axil_timer.vvp
	@for sc in write_aw_first write_w_first write_same_cycle read_stall oneshot w1c_collision prescale_shrink; do \
	  vvp $(SIMDIR)/tb_axil_timer.vvp +scenario=$$sc | grep WAVE_START | sed "s/^/$$sc /"; \
	done

clean:
	rm -rf $(SIMDIR)

.PHONY: all lint run regress waves clean

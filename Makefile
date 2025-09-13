# icarus and verilator. targets are listed in the readme

SIMDIR := sim

$(SIMDIR):
	@mkdir -p $(SIMDIR)

clean:
	rm -rf $(SIMDIR)

.PHONY: clean

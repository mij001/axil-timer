// constrained random over the register map

class axil_test_random extends uvm_test;

   `uvm_component_utils(axil_test_random)

   axil_env     env;
   int unsigned n_items;

   function new(string name, uvm_component parent);
      super.new(name, parent);
      n_items = 2000;
   endfunction

   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      void'($value$plusargs("nitems=%d", n_items));
      env = axil_env::type_id::create("env", this);
   endfunction

   task run_phase(uvm_phase phase);
      axil_sequence seq;
      phase.raise_objection(this);
      seq = axil_sequence::type_id::create("seq");
      seq.n_items = n_items;
      seq.start(env.agt.seqr);
      repeat (40) @(posedge env.agt.mon.vif.aclk);
      phase.drop_objection(this);
   endtask

   function void report_phase(uvm_phase phase);
      `uvm_info("TEST", $sformatf("MONITOR:    %0d writes, %0d reads",
                                  env.agt.mon.n_writes, env.agt.mon.n_reads), UVM_LOW)
      if (env.sb.n_err == 0 && env.sb.n_acc > 0)
         `uvm_info("TEST", "RESULT: PASS", UVM_LOW)
      else
         `uvm_error("TEST", "RESULT: FAIL")
   endfunction

endclass : axil_test_random

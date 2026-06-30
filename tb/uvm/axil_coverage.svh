// what was really reached, from what the monitor saw

class axil_coverage extends uvm_subscriber #(axil_obs);

   `uvm_component_utils(axil_coverage)

   logic [11:0] addr;
   acc_e        kind;
   logic [3:0]  wstrb;
   logic [1:0]  resp;

   int unsigned n_sampled;
   int unsigned n_okay, n_slverr, n_partial, n_nostrb;

   covergroup cg_acc;
      cp_addr: coverpoint addr {
         bins ctrl     = {A_CTRL};
         bins load     = {A_LOAD};
         bins count    = {A_COUNT};
         bins status   = {A_STATUS};
         bins prescale = {A_PRESCALE};
         bins nothing  = {12'h014, 12'h020};
         bins unaligned = {12'h001};
      }
      cp_kind: coverpoint kind {
         bins rd = {ACC_READ};
         bins wr = {ACC_WRITE};
      }
      cp_resp: coverpoint resp {
         bins okay   = {RESP_OKAY};
         bins slverr = {RESP_SLVERR};
      }
      // strobes only mean something on a write, so this is sampled as a shape
      cp_strb: coverpoint wstrb {
         bins none    = {4'h0};
         bins all     = {4'hF};
         bins partial = {[4'h1:4'hE]};
      }
      x_addr_kind: cross cp_addr, cp_kind;
      x_kind_resp: cross cp_kind, cp_resp;
   endgroup
   function new(string name, uvm_component parent);
      super.new(name, parent);
      n_sampled = 0;
      n_okay = 0; n_slverr = 0; n_partial = 0; n_nostrb = 0;
      cg_acc = new();
   endfunction

   function void write(axil_obs t);
      addr = t.addr; kind = t.kind; wstrb = t.wstrb; resp = t.resp;
      cg_acc.sample();
      n_sampled++;

      if (t.resp == RESP_OKAY) n_okay++; else n_slverr++;
      if (t.kind == ACC_WRITE) begin
         if (t.wstrb == 4'h0)      n_nostrb++;
         else if (t.wstrb != 4'hF) n_partial++;
      end
   endfunction : write

   function void report_phase(uvm_phase phase);
      `uvm_info("COV", $sformatf("COVERAGE:   cg_acc %0.2f%% over %0d samples",
                                 cg_acc.get_inst_coverage(), n_sampled), UVM_LOW)
      `uvm_info("COV", $sformatf("COVER responses okay / slverr   : %0d / %0d",
                                 n_okay, n_slverr), UVM_LOW)
      `uvm_info("COV", $sformatf("COVER writes partial / nostrobe : %0d / %0d",
                                 n_partial, n_nostrb), UVM_LOW)
   endfunction

endclass : axil_coverage

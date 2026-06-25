// a shadow of the register map. never looks at a pin
// it does not model the counter, COUNT and EXPIRED move on their own and the
// directed bench covers them against the reference model. what this checks is
// everything the bus promises whatever the counter is doing

class axil_scoreboard extends uvm_subscriber #(axil_obs);

   `uvm_component_utils(axil_scoreboard)

   logic [31:0] load_shadow;
   logic [15:0] prescale_shadow;
   bit          load_known, prescale_known;

   int unsigned n_acc, n_err;

   function new(string name, uvm_component parent);
      super.new(name, parent);
      n_acc = 0; n_err = 0;
      load_known = 0; prescale_known = 0;
   endfunction

   function bit is_register(logic [11:0] a);
      return (a == A_CTRL) || (a == A_LOAD) || (a == A_COUNT)
          || (a == A_STATUS) || (a == A_PRESCALE);
   endfunction

   function logic [31:0] merge(logic [31:0] old_v, logic [31:0] new_v, logic [3:0] s);
      logic [31:0] m;
      m = {{8{s[3]}}, {8{s[2]}}, {8{s[1]}}, {8{s[0]}}};
      return (old_v & ~m) | (new_v & m);
   endfunction

   function void write(axil_obs t);
      logic [1:0] want_resp;
      n_acc++;

      // ---- the response ---- spec section 6: an address that is not in the map
      // answers SLVERR, and so does a write to COUNT, which is read only
      if (!is_register(t.addr))
         want_resp = RESP_SLVERR;
      else if (t.kind == ACC_WRITE && t.addr == A_COUNT)
         want_resp = RESP_SLVERR;
      else
         want_resp = RESP_OKAY;

      if (t.resp !== want_resp) begin
         `uvm_error("SB", $sformatf("resp %b, expected %b, on %s",
                                    t.resp, want_resp, t.convert2string()))
         n_err++;
      end

      // ---- a failed read must not leak data ----
      if (t.kind == ACC_READ && t.resp == RESP_SLVERR && t.data !== 32'd0) begin
         `uvm_error("SB", $sformatf("SLVERR read leaked data on %s",
                                    t.convert2string()))
         n_err++;
      end

      // ---- reserved bits read as zero ----
      if (t.kind == ACC_READ && t.resp == RESP_OKAY) begin
         if (t.addr == A_CTRL && (t.data[31:3] !== 29'd0)) begin
            `uvm_error("SB", $sformatf("CTRL reserved bits not zero, 0x%08h",
                               t.data))
            n_err++;
         end
         if (t.addr == A_STATUS && (t.data[31:1] !== 31'd0)) begin
            `uvm_error("SB", $sformatf("STATUS reserved bits not zero, 0x%08h",
                               t.data))
            n_err++;
         end
         if (t.addr == A_PRESCALE && (t.data[31:16] !== 16'd0)) begin
            `uvm_error("SB", $sformatf("PRESCALE reserved bits not zero, 0x%08h",
                               t.data))
            n_err++;
         end
      end

      // ---- the two registers hardware never touches ---- LOAD and PRESCALE
      if (t.kind == ACC_WRITE && t.resp == RESP_OKAY) begin
         if (t.addr == A_LOAD) begin
            load_shadow = merge(load_known ? load_shadow : 32'd0, t.data, t.wstrb);
            load_known  = 1;
         end
         if (t.addr == A_PRESCALE) begin
            logic [31:0] merged;
            merged = merge(prescale_known ? {16'd0, prescale_shadow} : 32'd0,
                           t.data, t.wstrb);
            prescale_shadow = merged[15:0];
            prescale_known  = 1;
         end
      end

      if (t.kind == ACC_READ && t.resp == RESP_OKAY) begin
         if (t.addr == A_LOAD && load_known && t.data !== load_shadow) begin
            `uvm_error("SB", $sformatf("LOAD read 0x%08h, shadow says 0x%08h",
                               t.data, load_shadow))
            n_err++;
         end
         if (t.addr == A_PRESCALE && prescale_known
            && t.data[15:0] !== prescale_shadow) begin
            `uvm_error("SB", $sformatf("PRESCALE read 0x%04h, shadow says 0x%04h",
                               t.data[15:0], prescale_shadow))
            n_err++;
         end
      end
   endfunction
   function void report_phase(uvm_phase phase);
      `uvm_info("SB", $sformatf("SCOREBOARD: %0d accesses checked, %0d errors",
                                n_acc, n_err), UVM_LOW)
   endfunction

endclass : axil_scoreboard

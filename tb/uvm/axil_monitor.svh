// watches the five channels and rebuilds the accesses. drives nothing

class axil_monitor extends uvm_monitor;

   `uvm_component_utils(axil_monitor)

   virtual axil_if vif;
   uvm_analysis_port #(axil_obs) ap;
   int unsigned n_writes, n_reads;

   function new(string name, uvm_component parent);
      super.new(name, parent);
      n_writes = 0;
      n_reads  = 0;
   endfunction

   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);
      if (!uvm_config_db #(virtual axil_if)::get(this, "", "vif", vif))
         `uvm_fatal("NOVIF", "no virtual interface set for the monitor")
   endfunction

   task run_phase(uvm_phase phase);
      fork
         watch_writes();
         watch_reads();
      join
   endtask : run_phase

   task watch_writes();
      logic [11:0] a;
      logic [31:0] d;
      logic [3:0]  s;
      bit          have_a, have_d;
      axil_obs     o;

      have_a = 0; have_d = 0;
      forever begin
         @(vif.mon_cb);
         if (!vif.aresetn) begin
            have_a = 0; have_d = 0;
            continue;
         end
         if (vif.mon_cb.awvalid && vif.mon_cb.awready) begin
            a = vif.mon_cb.awaddr; have_a = 1;
         end
         if (vif.mon_cb.wvalid && vif.mon_cb.wready) begin
            d = vif.mon_cb.wdata; s = vif.mon_cb.wstrb; have_d = 1;
         end
         if (vif.mon_cb.bvalid && vif.mon_cb.bready) begin
            if (have_a && have_d) begin
               o = new();
               o.kind = ACC_WRITE; o.addr = a; o.data = d;
               o.wstrb = s; o.resp = vif.mon_cb.bresp;
               `uvm_info("MON", o.convert2string(), UVM_HIGH)
               ap.write(o);
               n_writes++;
            end
            have_a = 0; have_d = 0;
         end
      end
   endtask

   task watch_reads();
      logic [11:0] a;
      bit          have_a;
      axil_obs     o;

      have_a = 0;
      forever begin
         @(vif.mon_cb);
         if (!vif.aresetn) begin
            have_a = 0;
            continue;
         end
         if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
            a = vif.mon_cb.araddr; have_a = 1;
         end
         if (vif.mon_cb.rvalid && vif.mon_cb.rready) begin
            if (have_a) begin
               o = new();
               o.kind = ACC_READ; o.addr = a; o.data = vif.mon_cb.rdata;
               o.wstrb = 4'h0;    o.resp = vif.mon_cb.rresp;
               `uvm_info("MON", o.convert2string(), UVM_HIGH)
               ap.write(o);
               n_reads++;
            end
            have_a = 0;
         end
      end
   endtask
endclass : axil_monitor

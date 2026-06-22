// sequencer, driver and monitor for one axi4-lite port

class axil_agent extends uvm_agent;

   `uvm_component_utils(axil_agent)

   uvm_sequencer #(axil_item) seqr;
   axil_driver                drv;
   axil_monitor               mon;

   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction

   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      mon = axil_monitor::type_id::create("mon", this);
      if (get_is_active() == UVM_ACTIVE) begin
         seqr = uvm_sequencer #(axil_item)::type_id::create("seqr", this);
         drv  = axil_driver::type_id::create("drv", this);
      end
   endfunction

   function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      if (get_is_active() == UVM_ACTIVE)
         drv.seq_item_port.connect(seqr.seq_item_export);
   endfunction

endclass : axil_agent

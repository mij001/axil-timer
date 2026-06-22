// constrained random over the register map. three of the eight addresses are
// meant to be refused, so about 15% of accesses must come back SLVERR

class axil_sequence extends uvm_sequence #(axil_item);

   `uvm_object_utils(axil_sequence)

   rand int unsigned n_items;
   constraint c_n { n_items inside {[1:100000]}; }

   function new(string name = "axil_sequence");
      super.new(name);
      n_items = 2000;
   endfunction

   task body();
      axil_item req;
      repeat (n_items) begin
         req = axil_item::type_id::create("req");
         start_item(req);
         if (!req.randomize())
            `uvm_fatal("SEQ", "randomize failed")
         `uvm_info("SEQ", {"sending ", req.convert2string()}, UVM_HIGH)
         finish_item(req);
      end
   endtask : body

endclass : axil_sequence

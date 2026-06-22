// what the monitor saw on the five channels

class axil_obs extends uvm_sequence_item;

   acc_e        kind;
   logic [11:0] addr;
   logic [31:0] data;
   logic [3:0]  wstrb;
   logic [1:0]  resp;

   `uvm_object_utils_begin(axil_obs)
      `uvm_field_enum(acc_e, kind, UVM_ALL_ON)
      `uvm_field_int(addr,  UVM_ALL_ON | UVM_HEX)
      `uvm_field_int(data,  UVM_ALL_ON | UVM_HEX)
      `uvm_field_int(wstrb, UVM_ALL_ON | UVM_BIN)
      `uvm_field_int(resp,  UVM_ALL_ON | UVM_BIN)
   `uvm_object_utils_end

   function new(string name = "axil_obs");
      super.new(name);
   endfunction

   function string convert2string();
      if (kind == ACC_WRITE)
         return $sformatf("WRITE 0x%03h data 0x%08h strb %b resp %b",
                          addr, data, wstrb, resp);
      else
         return $sformatf("READ  0x%03h data 0x%08h resp %b",
                          addr, data, resp);
   endfunction

endclass : axil_obs

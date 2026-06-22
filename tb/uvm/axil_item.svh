// one bus access

class axil_item extends uvm_sequence_item;

   rand logic [11:0] addr;
   rand acc_e        kind;
   rand ord_e        ord;
   rand logic [31:0] wdata;
   rand logic [3:0]  wstrb;
   rand int unsigned gap;      // idle cycles before this access
   rand int unsigned skew;     // cycles between the two write halves

   `uvm_object_utils_begin(axil_item)
      `uvm_field_int(addr,      UVM_ALL_ON | UVM_HEX)
      `uvm_field_enum(acc_e, kind, UVM_ALL_ON)
      `uvm_field_enum(ord_e, ord,  UVM_ALL_ON)
      `uvm_field_int(wdata,     UVM_ALL_ON | UVM_HEX)
      `uvm_field_int(wstrb,     UVM_ALL_ON | UVM_BIN)
      `uvm_field_int(gap,       UVM_ALL_ON | UVM_DEC)
      `uvm_field_int(skew,      UVM_ALL_ON | UVM_DEC)
   `uvm_object_utils_end

   function new(string name = "axil_item");
      super.new(name);
   endfunction

   // mostly the five real registers, some deliberate misses
   constraint c_addr {
      addr dist {
         A_CTRL     := 20,
         A_LOAD     := 20,
         A_COUNT    := 15,
         A_STATUS   := 15,
         A_PRESCALE := 15,
         12'h014    := 5,    // nothing there
         12'h020    := 5,    // nothing there
         12'h001    := 5     // not a multiple of four
      };
   }

   constraint c_kind { kind dist { ACC_WRITE := 55, ACC_READ := 45 }; }
   constraint c_ord  { ord  dist { ORD_TOGETHER := 40, ORD_AW_FIRST := 35,
                           ORD_W_FIRST  := 25 }; }

   // all four strobes most of the time, sometimes a partial write, and a small
   // share with no strobes at all, which has to write nothing and still say OKAY
   constraint c_strb {
      wstrb dist { 4'hF := 55, 4'h0 := 10, 4'h3 := 10, 4'hC := 10,
                   4'h1 := 5,  4'h8 := 5,  4'h6 := 5 };
   }

   constraint c_gap  { gap  inside {[0:6]}; gap  dist {0 := 45, [1:6] := 55}; }
   constraint c_skew { skew inside {[0:4]}; skew dist {0 := 40, [1:4] := 60}; }

   function string convert2string();
      if (kind == ACC_WRITE)
         return $sformatf("WRITE 0x%03h data 0x%08h strb %b %s gap %0d skew %0d",
                          addr, wdata, wstrb, ord.name(), gap, skew);
      else
         return $sformatf("READ  0x%03h gap %0d", addr, gap);
   endfunction

endclass : axil_item

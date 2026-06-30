`timescale 1ns / 1ps

// top for the uvm bench. clock, reset, the design on the interface, the
// interface into the config db, then run_test
//   +UVM_TESTNAME=axil_test_random
//   +nitems=<n>

module tb_axil_timer_uvm;

   import uvm_pkg::*;
   import axil_pkg::*;

   localparam int ADDR_W = 12;

   logic aclk = 1'b0;
   always #5 aclk = ~aclk;

   // starts high so the async reset gets a real falling edge
   logic aresetn = 1'b1;
   initial begin
      #1 aresetn = 1'b0;
      repeat (4) @(posedge aclk);
      // released on the falling edge, so it is not a race with the flops
      @(negedge aclk);
      aresetn = 1'b1;
   end

   axil_if #(.ADDR_W(ADDR_W)) vif (.aclk(aclk), .aresetn(aresetn));

   axil_timer #(.ADDR_W(ADDR_W)) u_dut (
      .aclk            (aclk),
      .aresetn         (aresetn),
      .s_axil_awvalid  (vif.awvalid),
      .s_axil_awready  (vif.awready),
      .s_axil_awaddr   (vif.awaddr),
      .s_axil_awprot   (vif.awprot),
      .s_axil_wvalid   (vif.wvalid),
      .s_axil_wready   (vif.wready),
      .s_axil_wdata    (vif.wdata),
      .s_axil_wstrb    (vif.wstrb),
      .s_axil_bvalid   (vif.bvalid),
      .s_axil_bready   (vif.bready),
      .s_axil_bresp    (vif.bresp),
      .s_axil_arvalid  (vif.arvalid),
      .s_axil_arready  (vif.arready),
      .s_axil_araddr   (vif.araddr),
      .s_axil_arprot   (vif.arprot),
      .s_axil_rvalid   (vif.rvalid),
      .s_axil_rready   (vif.rready),
      .s_axil_rdata    (vif.rdata),
      .s_axil_rresp    (vif.rresp),
      .irq             (vif.irq)
   );

   initial begin
      uvm_config_db #(virtual axil_if)::set(null, "*", "vif", vif);
   end

   initial begin
      // a hang should fail, not sit there
      uvm_top.set_timeout(50ms, 0);
      run_test();
   end

endmodule : tb_axil_timer_uvm

// the only class that moves a pin

class axil_driver extends uvm_driver #(axil_item);

   `uvm_component_utils(axil_driver)

   virtual axil_if vif;

   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction

   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(virtual axil_if)::get(this, "", "vif", vif))
         `uvm_fatal("NOVIF", "no virtual interface set for the driver")
   endfunction

   task run_phase(uvm_phase phase);
      axil_item req;
      // a clocking block output is driven by the clocking block, not by the
      // variable's initialiser, and it drives X until something writes it. so
      // every output goes to a known value before anything else happens or the
      // X on bready walks straight into the design one cycle after reset
      @(vif.drv_cb);
      drive_idle();

      // uvm starts the run phase at time zero, so the driver waits for reset
      // itself, and for the whole pulse. this reset starts HIGH so the async
      // reset gets a real falling edge, which means aresetn being 1 at time
      // zero says nothing
      wait (vif.aresetn === 1'b0);
      wait (vif.aresetn === 1'b1);
      @(vif.drv_cb);
      forever begin
         seq_item_port.get_next_item(req);
         if (req.kind == ACC_WRITE) do_write(req);
         else                       do_read(req);
         seq_item_port.item_done();
      end
   endtask : run_phase

   task drive_idle();
      vif.drv_cb.awvalid <= 1'b0;
      vif.drv_cb.awaddr  <= '0;
      vif.drv_cb.awprot  <= '0;
      vif.drv_cb.wvalid  <= 1'b0;
      vif.drv_cb.wdata   <= '0;
      vif.drv_cb.wstrb   <= '0;
      vif.drv_cb.bready  <= 1'b0;
      vif.drv_cb.arvalid <= 1'b0;
      vif.drv_cb.araddr  <= '0;
      vif.drv_cb.arprot  <= '0;
      vif.drv_cb.rready  <= 1'b0;
   endtask

   task do_write(axil_item it);
      repeat (it.gap) @(vif.drv_cb);

      case (it.ord)
         ORD_TOGETHER: begin
            fork
               drive_aw(it.addr);
               drive_w(it.wdata, it.wstrb);
            join
         end
         ORD_AW_FIRST: begin
            drive_aw(it.addr);
            repeat (it.skew) @(vif.drv_cb);
            drive_w(it.wdata, it.wstrb);
         end
         ORD_W_FIRST: begin
            drive_w(it.wdata, it.wstrb);
            repeat (it.skew) @(vif.drv_cb);
            drive_aw(it.addr);
         end
      endcase

      // take the response
      vif.drv_cb.bready <= 1'b1;
      do @(vif.drv_cb); while (!vif.drv_cb.bvalid);
      vif.drv_cb.bready <= 1'b0;
   endtask

   task drive_aw(logic [11:0] a);
      vif.drv_cb.awaddr  <= a;
      vif.drv_cb.awprot  <= 3'b000;
      vif.drv_cb.awvalid <= 1'b1;
      do @(vif.drv_cb); while (!vif.drv_cb.awready);
      vif.drv_cb.awvalid <= 1'b0;
   endtask

   task drive_w(logic [31:0] d, logic [3:0] s);
      vif.drv_cb.wdata  <= d;
      vif.drv_cb.wstrb  <= s;
      vif.drv_cb.wvalid <= 1'b1;
      do @(vif.drv_cb); while (!vif.drv_cb.wready);
      vif.drv_cb.wvalid <= 1'b0;
   endtask

   task do_read(axil_item it);
      repeat (it.gap) @(vif.drv_cb);

      vif.drv_cb.araddr  <= it.addr;
      vif.drv_cb.arprot  <= 3'b000;
      vif.drv_cb.arvalid <= 1'b1;
      do @(vif.drv_cb); while (!vif.drv_cb.arready);
      vif.drv_cb.arvalid <= 1'b0;

      vif.drv_cb.rready <= 1'b1;
      do @(vif.drv_cb); while (!vif.drv_cb.rvalid);
      vif.drv_cb.rready <= 1'b0;
   endtask
endclass : axil_driver

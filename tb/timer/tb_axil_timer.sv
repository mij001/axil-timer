`timescale 1ns / 1ps

// directed bench. +seed= +ntrans= +scenario=<name>

module tb_axil_timer;

    localparam integer      ADDR_W     = 12;
    localparam [1:0]        OKAY       = 2'b00;
    localparam [1:0]        SLVERR     = 2'b10;
    localparam [ADDR_W-1:0] A_CTRL     = 12'h000;
    localparam [ADDR_W-1:0] A_LOAD     = 12'h004;
    localparam [ADDR_W-1:0] A_COUNT    = 12'h008;
    localparam [ADDR_W-1:0] A_STATUS   = 12'h00C;
    localparam [ADDR_W-1:0] A_PRESCALE = 12'h010;

    reg aclk    = 1'b0;
    reg aresetn = 1'b0;
    always #5 aclk = ~aclk;

    // master side of the bus, driven by the BFM
    reg              awvalid = 1'b0;  reg [ADDR_W-1:0] awaddr = 0;  reg [2:0] awprot = 0;
    reg              wvalid  = 1'b0;  reg [31:0]       wdata  = 0;  reg [3:0] wstrb  = 0;
    reg              bready  = 1'b0;
    reg              arvalid = 1'b0;  reg [ADDR_W-1:0] araddr = 0;  reg [2:0] arprot = 0;
    reg              rready  = 1'b0;

    wire             awready, wready, bvalid, arready, rvalid, irq;
    wire [1:0]       bresp, rresp;
    wire [31:0]      rdata;

    axil_timer #(.ADDR_W(ADDR_W)) u_dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axil_awvalid(awvalid), .s_axil_awready(awready), .s_axil_awaddr(awaddr), .s_axil_awprot(awprot),
        .s_axil_wvalid(wvalid),   .s_axil_wready(wready),   .s_axil_wdata(wdata),   .s_axil_wstrb(wstrb),
        .s_axil_bvalid(bvalid),   .s_axil_bready(bready),   .s_axil_bresp(bresp),
        .s_axil_arvalid(arvalid), .s_axil_arready(arready), .s_axil_araddr(araddr), .s_axil_arprot(arprot),
        .s_axil_rvalid(rvalid),   .s_axil_rready(rready),   .s_axil_rdata(rdata),   .s_axil_rresp(rresp),
        .irq(irq)
    );

    axil_checker #(.ADDR_W(ADDR_W), .NAME("timer")) u_chk (
        .aclk(aclk), .aresetn(aresetn),
        .awvalid(awvalid), .awready(awready), .awaddr(awaddr), .awprot(awprot),
        .wvalid(wvalid),   .wready(wready),   .wdata(wdata),   .wstrb(wstrb),
        .bvalid(bvalid),   .bready(bready),   .bresp(bresp),
        .arvalid(arvalid), .arready(arready), .araddr(araddr), .arprot(arprot),
        .rvalid(rvalid),   .rready(rready),   .rdata(rdata),   .rresp(rresp)
    );

    timer_model #(.ADDR_W(ADDR_W)) u_model (
        .aclk(aclk), .aresetn(aresetn),
        .reg_wr(u_dut.reg_wr), .reg_waddr(u_dut.reg_waddr),
        .reg_wdata(u_dut.reg_wdata), .reg_wstrb(u_dut.reg_wstrb)
    );

    // bookkeeping
    integer seed, ntrans, max_dly, cyc, errors, model_mismatches;
    integer aw_dly_force, w_dly_force, b_dly_force, ar_dly_force, r_dly_force;
    integer aw_hs_cyc, w_hs_cyc, rd_hs_cyc, n_writes, n_reads;
    reg [1:0]  last_bresp, last_rresp;
    reg [31:0] v;
    reg [8*32-1:0] scenario, vcdname;

    integer cov_aw_first, cov_w_first, cov_aw_w_same, cov_b_stall, cov_r_stall;
    integer cov_zero_strb, cov_partial_strb, cov_ro_write, cov_bad_addr, cov_misaligned;
    integer cov_expire_w1c, cov_expire_load, cov_expire_ctrl, cov_prescale_shrink;
    integer cov_oneshot_expire, cov_periodic_expire, cov_irq_rise, cov_read_write_same;
    reg     irq_prev;
    integer cov_aw_throttled, cov_w_throttled, cov_ar_throttled, cov_aw_during_b;

    // bus monitor queues. filled at AXI handshakes, emptied when a write is applied
    reg [ADDR_W-1:0] mq_aw [0:8191];   // accepted write addresses, in order
    reg [35:0]       mq_w  [0:8191];   // accepted {strobes, data}, in order
    reg [1:0]        mq_b  [0:8191];   // expected BRESP, in order
    reg [32:0]       mq_r  [0:8191];   // expected {error, data}, in order
    integer mq_aw_head, mq_aw_tail, mq_w_head, mq_w_tail;
    integer mq_b_head, mq_b_tail, mq_r_head, mq_r_tail, n_applied;

    function integer urand;                  // uniform 0..n
        input integer n;
        begin
            urand = (n <= 0) ? 0 : ({$random(seed)} % (n + 1));
        end
    endfunction

    task expect32;
        input [31:0]     got;
        input [31:0]     exp;
        input [8*40-1:0] what;
        begin
            if (got !== exp) begin
                $display("[%0t] EXPECT FAIL %0s: got 0x%08h expected 0x%08h", $time, what, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    // every cycle: compare DUT state with the model, and collect coverage sampled at
    always @(posedge aclk) begin
        if (aresetn) cyc = cyc + 1;
    end

    always @(negedge aclk) begin
        if (aresetn) begin
            if (u_dut.u_regs.en_q       !== u_model.en       ||
                u_dut.u_regs.periodic_q !== u_model.periodic ||
                u_dut.u_regs.irq_en_q   !== u_model.irq_en   ||
                u_dut.u_regs.load_q     !== u_model.load     ||
                u_dut.u_regs.prescale_q !== u_model.prescale ||
                u_dut.u_regs.expired_q  !== u_model.expired  ||
                u_dut.u_core.count_q    !== u_model.count    ||
                u_dut.u_core.pre_q      !== u_model.pre      ||
                irq                     !== u_model.irq) begin
                if (model_mismatches < 5)
                    $display("[%0t] MODEL MISMATCH cyc %0d: en %b/%b per %b/%b ie %b/%b load %0d/%0d pre_v %0d/%0d exp %b/%b count %0d/%0d pre %0d/%0d irq %b/%b",
                        $time, cyc,
                        u_dut.u_regs.en_q, u_model.en, u_dut.u_regs.periodic_q, u_model.periodic,
                        u_dut.u_regs.irq_en_q, u_model.irq_en, u_dut.u_regs.load_q, u_model.load,
                        u_dut.u_regs.prescale_q, u_model.prescale, u_dut.u_regs.expired_q, u_model.expired,
                        u_dut.u_core.count_q, u_model.count, u_dut.u_core.pre_q, u_model.pre, irq, u_model.irq);
                model_mismatches = model_mismatches + 1;
            end

            // events of the cycle that just ended, as recorded by the model
            if (u_model.ev_expire && u_model.ev_w1c)        cov_expire_w1c      = cov_expire_w1c + 1;
            if (u_model.ev_expire && u_model.ev_load_write) cov_expire_load     = cov_expire_load + 1;
            if (u_model.ev_expire && u_model.ev_ctrl_write) cov_expire_ctrl     = cov_expire_ctrl + 1;
            if (u_model.ev_prescale_shrink)                 cov_prescale_shrink = cov_prescale_shrink + 1;

            // events of the cycle in progress
            if (u_dut.core_expire &&  u_model.periodic) cov_periodic_expire = cov_periodic_expire + 1;
            if (u_dut.core_expire && !u_model.periodic) cov_oneshot_expire  = cov_oneshot_expire + 1;
            if (irq && !irq_prev)                       cov_irq_rise        = cov_irq_rise + 1;
            irq_prev = irq;
        end
    end

    // bus monitor and bus coverage. sampled at the RISING edge, like the checker. the
    always @(posedge aclk) begin
        if (aresetn) begin
            if (bvalid  && !bready)  cov_b_stall      = cov_b_stall + 1;
            if (rvalid  && !rready)  cov_r_stall      = cov_r_stall + 1;
            if (awvalid && !awready) cov_aw_throttled = cov_aw_throttled + 1;
            if (wvalid  && !wready)  cov_w_throttled  = cov_w_throttled + 1;
            if (arvalid && !arready) cov_ar_throttled = cov_ar_throttled + 1;
            if (awvalid && awready && bvalid) cov_aw_during_b = cov_aw_during_b + 1;
            if (arvalid && arready && u_dut.reg_wr && araddr == u_dut.reg_waddr)
                cov_read_write_same = cov_read_write_same + 1;

            // a write applied on the register bus must be the oldest write accepted
            if (u_dut.reg_wr) begin
                if (mq_aw_head == mq_aw_tail || mq_w_head == mq_w_tail) begin
                    $display("[%0t] MONITOR FAIL: a write was applied that AXI never delivered", $time);
                    errors = errors + 1;
                end else begin
                    if (u_dut.reg_waddr !== mq_aw[mq_aw_head % 8192] ||
                        {u_dut.reg_wstrb, u_dut.reg_wdata} !== mq_w[mq_w_head % 8192]) begin
                        $display("[%0t] MONITOR FAIL: applied 0x%03h/%h/0x%08h but AXI sent 0x%03h/%h/0x%08h",
                                 $time, u_dut.reg_waddr, u_dut.reg_wstrb, u_dut.reg_wdata,
                                 mq_aw[mq_aw_head % 8192], mq_w[mq_w_head % 8192][35:32],
                                 mq_w[mq_w_head % 8192][31:0]);
                        errors = errors + 1;
                    end
                    mq_aw_head = mq_aw_head + 1;
                    mq_w_head  = mq_w_head + 1;
                    n_applied  = n_applied + 1;
                end
            end

            if (awvalid && awready) begin
                mq_aw[mq_aw_tail % 8192] = awaddr;
                mq_b[mq_b_tail % 8192]   = u_model.write_err(awaddr) ? SLVERR : OKAY;
                mq_aw_tail = mq_aw_tail + 1;
                mq_b_tail  = mq_b_tail + 1;
            end
            if (wvalid && wready) begin
                mq_w[mq_w_tail % 8192] = {wstrb, wdata};
                mq_w_tail = mq_w_tail + 1;
            end

            if (bvalid && bready) begin
                if (mq_b_head == mq_b_tail) begin
                    $display("[%0t] MONITOR FAIL: write response with no write outstanding", $time);
                    errors = errors + 1;
                end else begin
                    if (bresp !== mq_b[mq_b_head % 8192]) begin
                        $display("[%0t] MONITOR FAIL: BRESP %b expected %b", $time, bresp, mq_b[mq_b_head % 8192]);
                        errors = errors + 1;
                    end
                    mq_b_head = mq_b_head + 1;
                end
            end

            // the expected read answer is taken from the model at the AR handshake
            if (arvalid && arready) begin
                mq_r[mq_r_tail % 8192] = u_model.read(araddr);
                mq_r_tail = mq_r_tail + 1;
            end
            if (rvalid && rready) begin
                if (mq_r_head == mq_r_tail) begin
                    $display("[%0t] MONITOR FAIL: read response with no read outstanding", $time);
                    errors = errors + 1;
                end else begin
                    if (rresp !== (mq_r[mq_r_head % 8192][32] ? SLVERR : OKAY) ||
                        rdata !== mq_r[mq_r_head % 8192][31:0]) begin
                        $display("[%0t] MONITOR FAIL: read got %b/0x%08h expected %b/0x%08h", $time,
                                 rresp, rdata, mq_r[mq_r_head % 8192][32] ? SLVERR : OKAY,
                                 mq_r[mq_r_head % 8192][31:0]);
                        errors = errors + 1;
                    end
                    mq_r_head = mq_r_head + 1;
                end
            end
        end
    end

    // AXI4-Lite master BFM. everything is driven at the falling edge. READY outputs
    task axi_write;
        input [ADDR_W-1:0] a;
        input [31:0]       d;
        input [3:0]        s;
        integer dly_aw, dly_w, dly_b;
        reg [1:0] exp_resp;
        begin
            if (aclk !== 1'b0) begin
                $display("[%0t] BFM USE ERROR: axi_write must be called at a falling edge", $time);
                errors = errors + 1;
            end
            exp_resp = u_model.write_err(a) ? SLVERR : OKAY;
            dly_aw = (aw_dly_force >= 0) ? aw_dly_force : urand(max_dly);
            dly_w  = (w_dly_force  >= 0) ? w_dly_force  : urand(max_dly);
            dly_b  = (b_dly_force  >= 0) ? b_dly_force  : urand(max_dly);

            if (s == 4'h0)                       cov_zero_strb    = cov_zero_strb + 1;
            if (s != 4'h0 && s != 4'hF)          cov_partial_strb = cov_partial_strb + 1;
            if (a == A_COUNT)                    cov_ro_write     = cov_ro_write + 1;
            if (u_model.write_err(a) && a != A_COUNT) cov_bad_addr = cov_bad_addr + 1;
            if (a[1:0] != 2'b00)                 cov_misaligned   = cov_misaligned + 1;

            // a master may raise BREADY before BVALID. sometimes do
            if (b_dly_force < 0 && urand(3) == 0) bready = 1'b1;

            fork
                begin : aw_channel
                    repeat (dly_aw) @(negedge aclk);
                    awaddr = a; awprot = urand(7); awvalid = 1'b1;
                    while (awready !== 1'b1) @(negedge aclk);
                    aw_hs_cyc = cyc;
                    @(negedge aclk);
                    awvalid = 1'b0; awaddr = $random(seed);
                end
                begin : w_channel
                    repeat (dly_w) @(negedge aclk);
                    wdata = d; wstrb = s; wvalid = 1'b1;
                    while (wready !== 1'b1) @(negedge aclk);
                    w_hs_cyc = cyc;
                    @(negedge aclk);
                    wvalid = 1'b0; wdata = $random(seed); wstrb = $random(seed);
                end
            join

            if (aw_hs_cyc < w_hs_cyc) cov_aw_first  = cov_aw_first + 1;
            if (aw_hs_cyc > w_hs_cyc) cov_w_first   = cov_w_first + 1;
            if (aw_hs_cyc == w_hs_cyc) cov_aw_w_same = cov_aw_w_same + 1;

            if (!bready) begin
                repeat (dly_b) @(negedge aclk);
                bready = 1'b1;
            end
            while (bvalid !== 1'b1) @(negedge aclk);
            last_bresp = bresp;
            @(negedge aclk);
            bready = 1'b0;

            if (last_bresp !== exp_resp) begin
                $display("[%0t] SCOREBOARD FAIL write 0x%03h: BRESP %b expected %b", $time, a, last_bresp, exp_resp);
                errors = errors + 1;
            end
            n_writes = n_writes + 1;
        end
    endtask

    task axi_read;
        input  [ADDR_W-1:0] a;
        output [31:0]       d;
        integer dly_ar, dly_r;
        reg [32:0] exp;
        begin
            if (aclk !== 1'b0) begin
                $display("[%0t] BFM USE ERROR: axi_read must be called at a falling edge", $time);
                errors = errors + 1;
            end
            dly_ar = (ar_dly_force >= 0) ? ar_dly_force : urand(max_dly);
            dly_r  = (r_dly_force  >= 0) ? r_dly_force  : urand(max_dly);
            if (r_dly_force < 0 && urand(3) == 0) rready = 1'b1;
            if (a[1:0] != 2'b00) cov_misaligned = cov_misaligned + 1;

            repeat (dly_ar) @(negedge aclk);
            araddr = a; arprot = urand(7); arvalid = 1'b1;
            while (arready !== 1'b1) @(negedge aclk);
            exp = u_model.read(a);            // state during the AR handshake cycle
            rd_hs_cyc = cyc;
            @(negedge aclk);
            arvalid = 1'b0; araddr = $random(seed);

            if (!rready) begin
                repeat (dly_r) @(negedge aclk);
                rready = 1'b1;
            end
            while (rvalid !== 1'b1) @(negedge aclk);
            d = rdata;
            last_rresp = rresp;
            @(negedge aclk);
            rready = 1'b0;

            if (last_rresp !== (exp[32] ? SLVERR : OKAY) || d !== exp[31:0]) begin
                $display("[%0t] SCOREBOARD FAIL read 0x%03h: got %b/0x%08h expected %b/0x%08h",
                         $time, a, last_rresp, d, exp[32] ? SLVERR : OKAY, exp[31:0]);
                errors = errors + 1;
            end
            n_reads = n_reads + 1;
        end
    endtask

    task wr;                                  // full-strobe write
        input [ADDR_W-1:0] a;
        input [31:0]       d;
        begin
            axi_write(a, d, 4'hF);
        end
    endtask

    task no_delays;
        begin
            aw_dly_force = 0; w_dly_force = 0; b_dly_force = 0; ar_dly_force = 0; r_dly_force = 0;
        end
    endtask

    task random_delays;
        begin
            aw_dly_force = -1; w_dly_force = -1; b_dly_force = -1; ar_dly_force = -1; r_dly_force = -1;
        end
    endtask

    // cycles until the model expects an expiry, counted from the cycle in progress (0
    function integer cycles_to_expire;
        input dummy;
        integer t;
        begin
            if (!u_model.en) cycles_to_expire = -1;
            else begin
                t = (u_model.pre >= u_model.prescale) ? 0 : (u_model.prescale - u_model.pre);
                cycles_to_expire = t + u_model.count * (u_model.prescale + 1);
            end
        end
    endfunction

    // land a full-strobe write on exactly the cycle the timer expires the write is
    task write_on_expiry;
        input [ADDR_W-1:0] a;
        input [31:0]       d;
        begin
            while (cycles_to_expire(0) != 1) @(negedge aclk);
            if (awready !== 1'b1 || wready !== 1'b1 || bvalid !== 1'b0) begin
                $display("[%0t] TEST SETUP FAIL: bus not idle for write_on_expiry", $time);
                errors = errors + 1;
            end
            no_delays;
            bready = 1'b1;
            axi_write(a, d, 4'hF);
            random_delays;
        end
    endtask

    // directed tests. one per question in the decisions log
    task test_reset_values;
        begin
            axi_read(A_CTRL, v);     expect32(v, 32'h0, "reset CTRL");
            axi_read(A_LOAD, v);     expect32(v, 32'h0, "reset LOAD");
            axi_read(A_COUNT, v);    expect32(v, 32'h0, "reset COUNT");
            axi_read(A_STATUS, v);   expect32(v, 32'h0, "reset STATUS");
            axi_read(A_PRESCALE, v); expect32(v, 32'h0, "reset PRESCALE");
            if (irq !== 1'b0) begin $display("EXPECT FAIL irq after reset"); errors = errors + 1; end
        end
    endtask

    task test_rw_and_reserved;
        begin
            wr(A_CTRL, 32'hFFFF_FFFE);             // EN written 0, everything else 1
            axi_read(A_CTRL, v);     expect32(v, 32'h6, "CTRL reserved bits read zero");
            wr(A_LOAD, 32'hDEAD_BEEF);
            axi_read(A_LOAD, v);     expect32(v, 32'hDEAD_BEEF, "LOAD readback");
            axi_read(A_COUNT, v);    expect32(v, 32'hDEAD_BEEF, "LOAD write loads COUNT");
            wr(A_PRESCALE, 32'hABCD_1234);
            axi_read(A_PRESCALE, v); expect32(v, 32'h1234, "PRESCALE reserved bits read zero");
            wr(A_CTRL, 32'h0);
        end
    endtask

    task test_strobes;
        begin
            wr(A_LOAD, 32'h1122_3344);
            axi_write(A_LOAD, 32'hAABB_CCDD, 4'b0101);
            axi_read(A_LOAD, v);     expect32(v, 32'h11BB_33DD, "partial strobes on LOAD");
            axi_read(A_COUNT, v);    expect32(v, 32'h11BB_33DD, "partial LOAD write restarts COUNT");
            wr(A_PRESCALE, 32'h5);
            wr(A_CTRL, 32'h1);                     // start counting down
            repeat (3) @(negedge aclk);
            wr(A_CTRL, 32'h0);
            axi_read(A_COUNT, v);
            axi_write(A_LOAD, 32'hFFFF_FFFF, 4'b0000);
            if (last_bresp !== OKAY) begin $display("EXPECT FAIL zero strobe response"); errors = errors + 1; end
            axi_read(A_LOAD, v);     expect32(v, 32'h11BB_33DD, "zero strobes change nothing");
            axi_write(A_PRESCALE, 32'hFFFF_0000, 4'b1100);
            axi_read(A_PRESCALE, v); expect32(v, 32'h5, "PRESCALE upper strobes ignored");
            axi_write(A_PRESCALE, 32'h0000_7700, 4'b0010);
            axi_read(A_PRESCALE, v); expect32(v, 32'h7705, "PRESCALE byte 1 strobe");
        end
    endtask

    task test_errors;
        begin
            axi_read(A_COUNT, v);
            axi_write(A_COUNT, 32'h1234_5678, 4'hF);
            if (last_bresp !== SLVERR) begin $display("EXPECT FAIL write COUNT not SLVERR"); errors = errors + 1; end
            axi_write(12'h014, 32'h1, 4'hF);
            axi_write(12'h001, 32'h1, 4'hF);
            axi_write(12'hFFC, 32'h1, 4'hF);
            axi_read(12'h014, v);    expect32(v, 32'h0, "SLVERR read data is zero");
            if (last_rresp !== SLVERR) begin $display("EXPECT FAIL read 0x014 not SLVERR"); errors = errors + 1; end
            axi_read(12'h006, v);
            if (last_rresp !== SLVERR) begin $display("EXPECT FAIL misaligned read not SLVERR"); errors = errors + 1; end
        end
    endtask

    task test_channel_orders;
        begin
            aw_dly_force = 0; w_dly_force = 3; b_dly_force = 0; wr(A_LOAD, 32'h10);
            aw_dly_force = 3; w_dly_force = 0; b_dly_force = 0; wr(A_LOAD, 32'h20);
            aw_dly_force = 0; w_dly_force = 0; b_dly_force = 6; wr(A_LOAD, 32'h30);
            ar_dly_force = 2; r_dly_force = 5; axi_read(A_LOAD, v); expect32(v, 32'h30, "slow read");
            random_delays;
        end
    endtask

    task test_oneshot;
        integer guard;
        begin
            wr(A_CTRL, 32'h0);
            wr(A_PRESCALE, 32'h1);
            wr(A_LOAD, 32'h3);
            wr(A_STATUS, 32'h1);
            wr(A_CTRL, 32'h5);                     // EN and IRQ_EN, one-shot
            guard = 0;
            while (irq !== 1'b1 && guard < 100) begin @(negedge aclk); guard = guard + 1; end
            if (irq !== 1'b1) begin $display("EXPECT FAIL one-shot never interrupted"); errors = errors + 1; end
            axi_read(A_CTRL, v);     expect32(v, 32'h4, "one-shot clears EN");
            axi_read(A_COUNT, v);    expect32(v, 32'h0, "one-shot leaves COUNT at zero");
            axi_read(A_STATUS, v);   expect32(v, 32'h1, "EXPIRED set");
            wr(A_STATUS, 32'h0);
            axi_read(A_STATUS, v);   expect32(v, 32'h1, "writing 0 to STATUS does nothing");
            wr(A_STATUS, 32'h1);
            axi_read(A_STATUS, v);   expect32(v, 32'h0, "write 1 clears EXPIRED");
            if (irq !== 1'b0) begin $display("EXPECT FAIL irq still high after clear"); errors = errors + 1; end
        end
    endtask

    task test_periods;
        integer k, L, P, t0, guard;
        begin
            for (k = 0; k < 5; k = k + 1) begin
                case (k)
                    0: begin L = 0; P = 0; end
                    1: begin L = 1; P = 0; end
                    2: begin L = 0; P = 3; end
                    3: begin L = 4; P = 2; end
                    default: begin L = 9; P = 1; end
                endcase
                wr(A_CTRL, 32'h0);
                wr(A_PRESCALE, P);
                wr(A_LOAD, L);
                wr(A_CTRL, 32'h3);                 // EN and PERIODIC
                guard = 0;
                while (!u_dut.core_expire && guard < 1000) begin @(negedge aclk); guard = guard + 1; end
                t0 = cyc;
                @(negedge aclk);
                guard = 0;
                while (!u_dut.core_expire && guard < 1000) begin @(negedge aclk); guard = guard + 1; end
                if (cyc - t0 != (P + 1) * (L + 1)) begin
                    $display("[%0t] EXPECT FAIL period LOAD=%0d PRESCALE=%0d: %0d cycles, spec says %0d",
                             $time, L, P, cyc - t0, (P + 1) * (L + 1));
                    errors = errors + 1;
                end
            end
            wr(A_CTRL, 32'h0);
            wr(A_STATUS, 32'h1);
        end
    endtask

    task test_collisions;
        begin
            // write-1-to-clear on the expiry cycle: EXPIRED must stay set
            wr(A_PRESCALE, 32'h1); wr(A_LOAD, 32'h3); wr(A_CTRL, 32'h7);
            write_on_expiry(A_STATUS, 32'h1);
            axi_read(A_STATUS, v);   expect32(v, 32'h1, "expiry beats write-1-to-clear");

            // LOAD write on a periodic expiry cycle
            write_on_expiry(A_LOAD, 32'h9);
            axi_read(A_STATUS, v);   expect32(v, 32'h1, "expiry reported despite LOAD write");

            // CTRL write on a one-shot expiry: the written EN wins
            wr(A_CTRL, 32'h0); wr(A_PRESCALE, 32'd20); wr(A_LOAD, 32'h1); wr(A_CTRL, 32'h5);
            write_on_expiry(A_CTRL, 32'h5);
            axi_read(A_CTRL, v);     expect32(v, 32'h5, "CTRL write beats one-shot stop");

            // LOAD write on a one-shot expiry: EN still cleared, COUNT = new value
            wr(A_CTRL, 32'h0); wr(A_LOAD, 32'h1); wr(A_CTRL, 32'h1);
            write_on_expiry(A_LOAD, 32'h9);
            axi_read(A_CTRL, v);     expect32(v, 32'h0, "one-shot stop kept on LOAD write");
            axi_read(A_COUNT, v);    expect32(v, 32'h9, "LOAD write decides COUNT");
            wr(A_STATUS, 32'h1);
        end
    endtask

    task test_prescale_shrink;
        begin
            wr(A_CTRL, 32'h0); wr(A_PRESCALE, 32'd300); wr(A_LOAD, 32'd1000); wr(A_CTRL, 32'h1);
            while (u_model.pre < 150) @(negedge aclk);
            no_delays;
            wr(A_PRESCALE, 32'd10);
            random_delays;
            repeat (3) @(negedge aclk);
            axi_read(A_COUNT, v);
            if (v >= 32'd1000) begin
                $display("[%0t] EXPECT FAIL shrinking PRESCALE did not tick at once (COUNT %0d)", $time, v);
                errors = errors + 1;
            end
            wr(A_CTRL, 32'h0);
        end
    endtask

    // outstanding transactions. AXI4-Lite allows several transactions to be in flight
    task send_write_only;
        input [ADDR_W-1:0] a;
        input [31:0]       d;
        input [3:0]        s;
        integer dly_aw, dly_w;
        begin
            if (aclk !== 1'b0) begin
                $display("[%0t] BFM USE ERROR: send_write_only must be called at a falling edge", $time);
                errors = errors + 1;
            end
            dly_aw = urand(2);
            dly_w  = urand(2);
            fork
                begin
                    repeat (dly_aw) @(negedge aclk);
                    awaddr = a; awprot = urand(7); awvalid = 1'b1;
                    while (awready !== 1'b1) @(negedge aclk);
                    @(negedge aclk);
                    awvalid = 1'b0;
                end
                begin
                    repeat (dly_w) @(negedge aclk);
                    wdata = d; wstrb = s; wvalid = 1'b1;
                    while (wready !== 1'b1) @(negedge aclk);
                    @(negedge aclk);
                    wvalid = 1'b0;
                end
            join
        end
    endtask

    task send_read_only;
        input [ADDR_W-1:0] a;
        begin
            if (aclk !== 1'b0) begin
                $display("[%0t] BFM USE ERROR: send_read_only must be called at a falling edge", $time);
                errors = errors + 1;
            end
            repeat (urand(1)) @(negedge aclk);
            araddr = a; arprot = urand(7); arvalid = 1'b1;
            while (arready !== 1'b1) @(negedge aclk);
            @(negedge aclk);
            arvalid = 1'b0;
        end
    endtask

    task test_outstanding;
        integer i, got;
        reg [ADDR_W-1:0] a;
        begin
            bready = 1'b0;
            fork
                begin
                    for (i = 0; i < 60; i = i + 1) begin
                        a = pick_addr(0);
                        send_write_only(a, pick_data(a), pick_strb(0));
                    end
                end
                begin
                    got = 0;
                    while (got < 60) begin
                        @(negedge aclk);
                        bready = (urand(2) == 0);
                        if (bvalid === 1'b1 && bready) got = got + 1;
                    end
                    @(negedge aclk);
                    bready = 1'b0;
                end
            join

            rready = 1'b0;
            fork
                begin
                    for (i = 0; i < 60; i = i + 1) send_read_only(pick_addr(0));
                end
                begin
                    got = 0;
                    while (got < 60) begin
                        @(negedge aclk);
                        rready = (urand(2) == 0);
                        if (rvalid === 1'b1 && rready) got = got + 1;
                    end
                    @(negedge aclk);
                    rready = 1'b0;
                end
            join
        end
    endtask

    // random test
    function [ADDR_W-1:0] pick_addr;
        input dummy;
        integer k;
        begin
            k = urand(99);
            if      (k < 20) pick_addr = A_CTRL;
            else if (k < 40) pick_addr = A_LOAD;
            else if (k < 50) pick_addr = A_COUNT;
            else if (k < 70) pick_addr = A_STATUS;
            else if (k < 88) pick_addr = A_PRESCALE;
            else if (k < 94) pick_addr = {urand(1023), 2'b00};
            else             pick_addr = urand(4095);
        end
    endfunction

    function [31:0] pick_data;
        input [ADDR_W-1:0] a;
        begin
            case (a)
                A_CTRL:     pick_data = {$random(seed)} & 32'hFFFF_FFF8 | (urand(9) < 7 ? 32'h1 : 32'h0)
                                        | (urand(1) << 1) | (urand(1) << 2);
                A_LOAD:     pick_data = (urand(9) < 8) ? urand(12) : $random(seed);
                A_PRESCALE: pick_data = (urand(9) < 8) ? urand(4)  : $random(seed);
                default:    pick_data = $random(seed);
            endcase
        end
    endfunction

    function [3:0] pick_strb;
        input dummy;
        integer k;
        begin
            k = urand(99);
            if      (k < 70) pick_strb = 4'hF;
            else if (k < 78) pick_strb = 4'h0;
            else             pick_strb = urand(15);
        end
    endfunction

    task test_random;
        input integer n;
        integer i, k;
        reg [ADDR_W-1:0] a, a2;
        begin
            random_delays;
            for (i = 0; i < n; i = i + 1) begin
                k  = urand(99);
                a  = pick_addr(0);
                a2 = pick_addr(0);
                if (k < 45)       axi_write(a, pick_data(a), pick_strb(0));
                else if (k < 75)  axi_read(a, v);
                else if (k < 90)  fork
                                      axi_write(a, pick_data(a), pick_strb(0));
                                      axi_read(a2, v);
                                  join
                else              repeat (urand(20)) @(negedge aclk);
            end
        end
    endtask

    // short scenarios, used only to draw timing diagrams
    task run_scenario;
        begin
            $sformat(vcdname, "sim/timer_%0s.vcd", scenario);
            $dumpfile(vcdname);
            $dumpvars(0, tb_axil_timer);
            no_delays;
            if (scenario == "oneshot") begin
                wr(A_PRESCALE, 32'h1); wr(A_LOAD, 32'h2);
                @(posedge aclk); $display("WAVE_START %0d", $time); @(negedge aclk);
                wr(A_CTRL, 32'h5);
                repeat (8) @(negedge aclk);
                wr(A_STATUS, 32'h1);
            end else if (scenario == "w1c_collision") begin
                wr(A_PRESCALE, 32'h1); wr(A_LOAD, 32'h1); wr(A_CTRL, 32'h7);
                while (cycles_to_expire(0) != 3) @(negedge aclk);
                @(posedge aclk); $display("WAVE_START %0d", $time); @(negedge aclk);
                write_on_expiry(A_STATUS, 32'h1);
            end else if (scenario == "prescale_shrink") begin
                wr(A_PRESCALE, 32'd9); wr(A_LOAD, 32'd50); wr(A_CTRL, 32'h1);
                while (u_model.pre != 5) @(negedge aclk);
                @(posedge aclk); $display("WAVE_START %0d", $time); @(negedge aclk);
                wr(A_PRESCALE, 32'd2);
            end else if (scenario == "read_stall") begin
                wr(A_LOAD, 32'h2A);
                @(posedge aclk); $display("WAVE_START %0d", $time); @(negedge aclk);
                r_dly_force = 2; axi_read(A_LOAD, v);
            end else begin
                @(posedge aclk); $display("WAVE_START %0d", $time); @(negedge aclk);
                if (scenario == "write_aw_first") begin
                    w_dly_force = 2; b_dly_force = 2; wr(A_LOAD, 32'h2A);
                end else if (scenario == "write_w_first") begin
                    aw_dly_force = 2; wr(A_LOAD, 32'h2A);
                end else if (scenario == "write_same_cycle") begin
                    wr(A_LOAD, 32'h2A);
                end else if (scenario == "read_stall") begin
                    r_dly_force = 2; axi_read(A_LOAD, v);
                end
            end
            repeat (6) @(negedge aclk);
        end
    endtask

    // main
    task report_and_finish;
        integer holes;
        begin
            repeat (5) @(negedge aclk);
            holes = 0;
            $display("");
            u_chk.report;
            $display("SCOREBOARD: %0d writes, %0d reads, %0d errors, %0d model mismatches over %0d cycles",
                     n_writes, n_reads, errors, model_mismatches, cyc);
            $display("COVER AW before W                 : %0d", cov_aw_first);
            $display("COVER W before AW                 : %0d", cov_w_first);
            $display("COVER AW and W same cycle         : %0d", cov_aw_w_same);
            $display("COVER BVALID waiting for BREADY   : %0d cycles", cov_b_stall);
            $display("COVER RVALID waiting for RREADY   : %0d cycles", cov_r_stall);
            $display("COVER write with no strobes       : %0d", cov_zero_strb);
            $display("COVER write with partial strobes  : %0d", cov_partial_strb);
            $display("COVER write to read-only COUNT    : %0d", cov_ro_write);
            $display("COVER access to undefined offset  : %0d", cov_bad_addr);
            $display("COVER misaligned address          : %0d", cov_misaligned);
            $display("COVER read and write same register: %0d", cov_read_write_same);
            $display("COVER one-shot expiry             : %0d", cov_oneshot_expire);
            $display("COVER periodic expiry             : %0d", cov_periodic_expire);
            $display("COVER irq rising                  : %0d", cov_irq_rise);
            $display("COVER expiry with W1C same cycle  : %0d", cov_expire_w1c);
            $display("COVER expiry with LOAD same cycle : %0d", cov_expire_load);
            $display("COVER expiry with CTRL same cycle : %0d", cov_expire_ctrl);
            $display("COVER PRESCALE shrunk below phase : %0d", cov_prescale_shrink);
            $display("COVER AWVALID waiting for AWREADY : %0d cycles", cov_aw_throttled);
            $display("COVER WVALID waiting for WREADY   : %0d cycles", cov_w_throttled);
            $display("COVER ARVALID waiting for ARREADY : %0d cycles", cov_ar_throttled);
            $display("COVER AW accepted while B waits   : %0d", cov_aw_during_b);
            $display("MONITOR: %0d writes applied, queues left AW %0d W %0d B %0d R %0d",
                     n_applied, mq_aw_tail - mq_aw_head, mq_w_tail - mq_w_head,
                     mq_b_tail - mq_b_head, mq_r_tail - mq_r_head);
            if (mq_aw_tail != mq_aw_head || mq_w_tail != mq_w_head ||
                mq_b_tail  != mq_b_head  || mq_r_tail != mq_r_head) begin
                $display("MONITOR FAIL: transactions accepted but never completed");
                errors = errors + 1;
            end
            if (cov_aw_throttled == 0 || cov_w_throttled == 0 || cov_ar_throttled == 0 ||
                cov_aw_during_b == 0)
                holes = 1;
            if (cov_aw_first == 0 || cov_w_first == 0 || cov_aw_w_same == 0 || cov_b_stall == 0 ||
                cov_r_stall == 0 || cov_zero_strb == 0 || cov_partial_strb == 0 || cov_ro_write == 0 ||
                cov_bad_addr == 0 || cov_misaligned == 0 || cov_read_write_same == 0 ||
                cov_oneshot_expire == 0 || cov_periodic_expire == 0 || cov_irq_rise == 0 ||
                cov_expire_w1c == 0 || cov_expire_load == 0 || cov_expire_ctrl == 0 ||
                cov_prescale_shrink == 0)
                holes = 1;
            if (errors == 0 && model_mismatches == 0 && u_chk.errors == 0 && holes == 0)
                $display("RESULT: PASS");
            else
                $display("RESULT: FAIL%0s", holes ? " (coverage hole)" : "");
            $display("");
            $finish;
        end
    endtask

    initial begin
        if (!$value$plusargs("seed=%d", seed))     seed    = 1;
        if (!$value$plusargs("ntrans=%d", ntrans)) ntrans  = 3000;
        if (!$value$plusargs("maxdly=%d", max_dly)) max_dly = 4;
        if (!$value$plusargs("scenario=%s", scenario)) scenario = "";

        cyc = 0; errors = 0; model_mismatches = 0; n_writes = 0; n_reads = 0;
        aw_hs_cyc = 0; w_hs_cyc = 0; rd_hs_cyc = 0; irq_prev = 1'b0;
        cov_aw_first = 0; cov_w_first = 0; cov_aw_w_same = 0; cov_b_stall = 0; cov_r_stall = 0;
        cov_zero_strb = 0; cov_partial_strb = 0; cov_ro_write = 0; cov_bad_addr = 0; cov_misaligned = 0;
        cov_expire_w1c = 0; cov_expire_load = 0; cov_expire_ctrl = 0; cov_prescale_shrink = 0;
        cov_oneshot_expire = 0; cov_periodic_expire = 0; cov_irq_rise = 0; cov_read_write_same = 0;
        cov_aw_throttled = 0; cov_w_throttled = 0; cov_ar_throttled = 0; cov_aw_during_b = 0;
        mq_aw_head = 0; mq_aw_tail = 0; mq_w_head = 0; mq_w_tail = 0;
        mq_b_head  = 0; mq_b_tail  = 0; mq_r_head = 0; mq_r_tail = 0; n_applied = 0;
        random_delays;

        repeat (4) @(posedge aclk);
        @(negedge aclk) aresetn = 1'b1;
        @(negedge aclk);

        if (scenario != "") begin
            run_scenario;
            $finish;
        end

        test_reset_values;
        test_rw_and_reserved;
        test_strobes;
        test_errors;
        test_channel_orders;
        test_oneshot;
        test_periods;
        test_collisions;
        test_prescale_shrink;
        if (!$test$plusargs("no_outstanding"))    // +no_outstanding reproduces the old hole
            test_outstanding;
        test_random(ntrans);
        report_and_finish;
    end

    initial begin
        #20_000_000;
        $display("TIMEOUT at cycle %0d. Likely a stuck handshake.", cyc);
        $display("RESULT: FAIL (timeout)");
        $finish;
    end

endmodule

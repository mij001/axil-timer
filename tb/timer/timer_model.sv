`timescale 1ns / 1ps

// reference model, written from the spec not from the rtl

module timer_model #(
    parameter integer ADDR_W = 12
) (
    input wire              aclk,
    input wire              aresetn,
    input wire              reg_wr,
    input wire [ADDR_W-1:0] reg_waddr,
    input wire [31:0]       reg_wdata,
    input wire [3:0]        reg_wstrb
);

    // model state, visible to the testbench
    reg        en, periodic, irq_en, expired;
    reg [31:0] load, count;
    reg [15:0] prescale, pre;

    // events during the cycle that just ended, for coverage
    reg ev_expire, ev_w1c, ev_load_write, ev_ctrl_write, ev_prescale_shrink;

    wire irq = expired & irq_en;

    function [31:0] merge;       // apply a 32-bit write through byte strobes
        input [31:0] old_v;
        input [31:0] new_v;
        input [3:0]  strb;
        integer b;
        begin
            merge = old_v;
            for (b = 0; b < 4; b = b + 1)
                if (strb[b]) merge[8*b +: 8] = new_v[8*b +: 8];
        end
    endfunction

    // expected answer to a read at address a, using the current state
    function [32:0] read;        // {error, data}
        input [ADDR_W-1:0] a;
        begin
            case (a)
                'h00:    read = {1'b0, 29'd0, irq_en, periodic, en};
                'h04:    read = {1'b0, load};
                'h08:    read = {1'b0, count};
                'h0C:    read = {1'b0, 31'd0, expired};
                'h10:    read = {1'b0, 16'd0, prescale};
                default: read = {1'b1, 32'd0};
            endcase
        end
    endfunction

    // expected error for a write at address a
    function write_err;
        input [ADDR_W-1:0] a;
        begin
            write_err = !(a == 'h00 || a == 'h04 || a == 'h0C || a == 'h10);
        end
    endfunction

    reg        n_en, n_periodic, n_irq_en, n_expired;
    reg [31:0] n_load, n_count;
    reg [15:0] n_prescale, n_pre;
    reg        tick, expire, sw_ctrl, sw_load, sw_status, sw_prescale, w1c;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            en <= 0; periodic <= 0; irq_en <= 0; expired <= 0;
            load <= 0; count <= 0; prescale <= 0; pre <= 0;
            ev_expire <= 0; ev_w1c <= 0; ev_load_write <= 0;
            ev_ctrl_write <= 0; ev_prescale_shrink <= 0;
        end else begin
            // start from "nothing changes"
            n_en = en; n_periodic = periodic; n_irq_en = irq_en; n_expired = expired;
            n_load = load; n_count = count; n_prescale = prescale; n_pre = pre;

            // spec section 4, as written: what the timer does on its own
            tick   = en && (pre >= prescale);
            expire = tick && (count == 0);
            if (!en)          n_pre = 0;
            else if (!tick)   n_pre = pre + 1;
            else begin
                n_pre = 0;
                if (count != 0)    n_count = count - 1;
                else begin
                    n_expired = 1;                      // the timer expires
                    if (periodic)  n_count = load;      // periodic: reload
                    else           n_en = 0;            // one-shot: stop
                end
            end

            // software's write this cycle, applied on top
            sw_ctrl     = reg_wr && reg_waddr == 'h00 && reg_wstrb[0];
            sw_load     = reg_wr && reg_waddr == 'h04 && (reg_wstrb != 0);
            sw_status   = reg_wr && reg_waddr == 'h0C;
            sw_prescale = reg_wr && reg_waddr == 'h10;
            w1c         = sw_status && reg_wstrb[0] && reg_wdata[0];

            if (sw_ctrl) begin                 // software intent wins for EN
                n_en       = reg_wdata[0];
                n_periodic = reg_wdata[1];
                n_irq_en   = reg_wdata[2];
            end
            if (sw_load) begin                 // software intent wins for COUNT
                n_load  = merge(load, reg_wdata, reg_wstrb);
                n_count = n_load;
                n_pre   = 0;
            end
            if (sw_prescale)
                n_prescale = merge({16'd0, prescale}, reg_wdata, {2'b00, reg_wstrb[1:0]});
            if (w1c && !expire)                // events are never lost
                n_expired = 0;

            en <= n_en; periodic <= n_periodic; irq_en <= n_irq_en; expired <= n_expired;
            load <= n_load; count <= n_count; prescale <= n_prescale; pre <= n_pre;

            ev_expire          <= expire;
            ev_w1c             <= w1c;
            ev_load_write      <= sw_load;
            ev_ctrl_write      <= sw_ctrl;
            ev_prescale_shrink <= sw_prescale && en && (n_prescale < pre);
        end
    end

endmodule

// everything the uvm bench needs, in one package, the usual way

package axil_pkg;

   import uvm_pkg::*;
`include "uvm_macros.svh"

   parameter int ADDR_W = 12;

   // register map, from docs/axil_timer_spec.md section 3
   parameter logic [11:0] A_CTRL     = 12'h000;
   parameter logic [11:0] A_LOAD     = 12'h004;
   parameter logic [11:0] A_COUNT    = 12'h008;
   parameter logic [11:0] A_STATUS   = 12'h00C;
   parameter logic [11:0] A_PRESCALE = 12'h010;

   parameter logic [1:0] RESP_OKAY   = 2'b00;
   parameter logic [1:0] RESP_SLVERR = 2'b10;

   typedef enum { ACC_READ, ACC_WRITE } acc_e;

   // which of AW and W the driver presents first
   typedef enum { ORD_TOGETHER, ORD_AW_FIRST, ORD_W_FIRST } ord_e;

`include "axil_item.svh"
`include "axil_obs.svh"
`include "axil_sequence.svh"

`include "axil_driver.svh"
`include "axil_monitor.svh"
`include "axil_agent.svh"

`include "axil_scoreboard.svh"
`include "axil_coverage.svh"

`include "axil_env.svh"
`include "axil_test.svh"

endpackage : axil_pkg

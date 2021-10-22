// distributed under the mit license
// https://opensource.org/licenses/mit-license.php

`timescale 1 ns / 1 ps
`default_nettype none

module axicb_mst_if

    #(
        // Address width in bits
        parameter AXI_ADDR_W = 8,
        // ID width in bits
        parameter AXI_ID_W = 8,
        // Data width in bits
        parameter AXI_DATA_W = 8,

        // Number of slave
        parameter SLV_NB = 4,

        // Enable routing to a slave, one bit per slave,
        // bit 0 = slave 0, bit 1 = slave 1, ...
        parameter MST_ROUTES = 4'b1_1_1_1,

        // STRB support:
        //   - 0: contiguous wstrb (store only 1st/last dataphase)
        //   - 1: full wstrb transport
        parameter STRB_MODE = 1,

        // AXI Signals Supported:
        //   - 0: AXI4-lite
        //   - 1: Restricted AXI4 (INCR mode, ADDR, ALEN)
        //   - 2: Complete
        parameter AXI_SIGNALING = 0,

        // Activate the timer to avoid deadlock
        parameter TIMEOUT_ENABLE = 1,

        // Implement CDC input stage
        parameter MST_CDC = 0,
        // Maximum number of requests a master can store
        parameter MST_OSTDREQ_NUM = 4,
        // Size of an outstanding request in dataphase
        parameter MST_OSTDREQ_SIZE = 1,

        // Output channels' width (concatenated)
        parameter AWCH_W = 8,
        parameter WCH_W = 8,
        parameter BCH_W = 8,
        parameter ARCH_W = 8,
        parameter RCH_W = 8
    )(
        // input interface from external master
        input  logic                      i_aclk,
        input  logic                      i_aresetn,
        input  logic                      i_srst,
        input  logic                      i_awvalid,
        output logic                      i_awready,
        input  logic [AXI_ADDR_W    -1:0] i_awaddr,
        input  logic [8             -1:0] i_awlen,
        input  logic [3             -1:0] i_awsize,
        input  logic [2             -1:0] i_awburst,
        input  logic [2             -1:0] i_awlock,
        input  logic [4             -1:0] i_awcache,
        input  logic [3             -1:0] i_awprot,
        input  logic [4             -1:0] i_awqos,
        input  logic [4             -1:0] i_awregion,
        input  logic [AXI_ID_W      -1:0] i_awid,
        input  logic                      i_wvalid,
        output logic                      i_wready,
        input  logic                      i_wlast,
        input  logic [AXI_DATA_W    -1:0] i_wdata,
        input  logic [AXI_DATA_W/8  -1:0] i_wstrb,
        output logic                      i_bvalid,
        input  logic                      i_bready,
        output logic [AXI_ID_W      -1:0] i_bid,
        output logic [2             -1:0] i_bresp,
        input  logic                      i_arvalid,
        output logic                      i_arready,
        input  logic [AXI_ADDR_W    -1:0] i_araddr,
        input  logic [8             -1:0] i_arlen,
        input  logic [3             -1:0] i_arsize,
        input  logic [2             -1:0] i_arburst,
        input  logic [2             -1:0] i_arlock,
        input  logic [4             -1:0] i_arcache,
        input  logic [3             -1:0] i_arprot,
        input  logic [4             -1:0] i_arqos,
        input  logic [4             -1:0] i_arregion,
        input  logic [AXI_ID_W      -1:0] i_arid,
        output logic                      i_rvalid,
        input  logic                      i_rready,
        output logic [AXI_ID_W      -1:0] i_rid,
        output logic [2             -1:0] i_rresp,
        output logic [AXI_DATA_W    -1:0] i_rdata,
        output logic                      i_rlast,
        // output interface to switching logic
        input  logic                      o_aclk,
        input  logic                      o_aresetn,
        input  logic                      o_srst,
        output logic                      o_awvalid,
        input  logic                      o_awready,
        output logic [AWCH_W        -1:0] o_awch,
        output logic                      o_wvalid,
        input  logic                      o_wready,
        output logic                      o_wlast,
        output logic [WCH_W         -1:0] o_wch,
        input  logic                      o_bvalid,
        output logic                      o_bready,
        input  logic [BCH_W         -1:0] o_bch,
        output logic                      o_arvalid,
        input  logic                      o_arready,
        output logic [ARCH_W        -1:0] o_arch,
        input  logic                      o_rvalid,
        output logic                      o_rready,
        input  logic                      o_rlast,
        input  logic [RCH_W         -1:0] o_rch
    );

    ///////////////////////////////////////////////////////////////////////////////
    // Logic declarations
    ///////////////////////////////////////////////////////////////////////////////

    logic [AWCH_W        -1:0] awch;
    logic [ARCH_W        -1:0] arch;

    generate 
    if (AXI_SIGNALING==0) begin : AXI4LITE_MODE

        assign awch = {
            i_awid,
            i_awprot,
            i_awaddr
        };

        assign arch = {
            i_arid,
            i_arprot,
            i_araddr
        };

    end else if (AXI_SIGNALING==1) begin : AXI4LITE_BURST_MODE

        assign awch = {
            i_awid,
            i_awprot,
            i_awlen,
            i_awaddr
        };

        assign arch = {
            i_arid,
            i_arprot,
            i_arlen,
            i_araddr
        };

    end else begin : AXI4_MODE

        assign awch = {
            i_awid,
            i_awregion,
            i_awqos,
            i_awprot,
            i_awcache,
            i_awlock,
            i_awburst,
            i_awsize,
            i_awlen,
            i_awaddr
        };

        assign arch = {
            i_arid,
            i_arregion,
            i_arqos,
            i_arprot,
            i_arcache,
            i_arlock,
            i_arburst,
            i_arsize,
            i_arlen,
            i_araddr
        };

    end
    endgenerate

    generate 
    
    if (MST_CDC) begin: CDC_STAGE

    logic             aw_winc;
    logic             aw_full;
    logic             aw_rinc;
    logic             aw_empty;
    logic             w_winc;
    logic             w_full;
    logic             w_rinc;
    logic             w_empty;
    logic             b_winc;
    logic             b_full;
    logic             b_rinc;
    logic             b_empty;
    logic             ar_winc;
    logic             ar_full;
    logic             ar_rinc;
    logic             ar_empty;
    logic             r_winc;
    logic             r_full;
    logic             r_rinc;
    logic             r_empty;

    ///////////////////////////////////////////////////////////////////////////
    // Write Address Channel
    ///////////////////////////////////////////////////////////////////////////

    localparam AW_ASIZE = (MST_OSTDREQ_NUM==0) ? 2 : $clog2(MST_OSTDREQ_NUM);

    async_fifo 
    #(
    .DSIZE       (AWCH_W),
    .ASIZE       (AW_ASIZE),
    .FALLTHROUGH ("TRUE")
    )
    aw_dcfifo 
    (
    .wclk    (i_aclk),
    .wrst_n  (i_aresetn),
    .winc    (aw_winc),
    .wdata   (awch),
    .wfull   (aw_full),
    .awfull  (),
    .rclk    (o_aclk),
    .rrst_n  (o_aresetn),
    .rinc    (aw_rinc),
    .rdata   (o_awch),
    .rempty  (aw_empty),
    .arempty ()
    );

    assign i_awready = ~aw_full;
    assign aw_winc = i_awvalid & ~aw_full; 

    assign o_awvalid = ~aw_empty;
    assign aw_rinc = ~aw_empty & o_awready;

    ///////////////////////////////////////////////////////////////////////////
    // Write Data Channel
    ///////////////////////////////////////////////////////////////////////////

    localparam W_ASIZE = (MST_OSTDREQ_NUM==0) ? 2 : $clog2(MST_OSTDREQ_NUM);

    async_fifo 
    #(
    .DSIZE       (WCH_W+1),
    .ASIZE       (W_ASIZE),
    .FALLTHROUGH ("TRUE")
    )
    w_dcfifo 
    (
    .wclk    (i_aclk),
    .wrst_n  (i_aresetn),
    .winc    (w_winc),
    .wdata   ({i_wlast, i_wstrb, i_wdata}),
    .wfull   (w_full),
    .awfull  (),
    .rclk    (o_aclk),
    .rrst_n  (o_aresetn),
    .rinc    (w_rinc),
    .rdata   ({o_wlast, o_wch}),
    .rempty  (w_empty),
    .arempty ()
    );

    assign i_wready = ~w_full;
    assign w_winc = i_wvalid & ~w_full; 

    assign o_wvalid = ~w_empty;
    assign w_rinc = ~w_empty & o_wready;

    ///////////////////////////////////////////////////////////////////////////
    // Write Response Channel
    ///////////////////////////////////////////////////////////////////////////

    localparam B_ASIZE = (MST_OSTDREQ_NUM==0) ? 2 : $clog2(MST_OSTDREQ_NUM);

    async_fifo 
    #(
    .DSIZE       (BCH_W),
    .ASIZE       (B_ASIZE),
    .FALLTHROUGH ("TRUE")
    )
    b_dcfifo 
    (
    .wclk    (i_aclk),
    .wrst_n  (i_aresetn),
    .winc    (b_winc),
    .wdata   (o_bch),
    .wfull   (b_full),
    .awfull  (),
    .rclk    (o_aclk),
    .rrst_n  (o_aresetn),
    .rinc    (b_rinc),
    .rdata   ({i_bresp, i_bid}),
    .rempty  (b_empty),
    .arempty ()
    );

    assign o_bready = ~b_full;
    assign b_winc = o_bvalid & ~b_full; 

    assign i_bvalid = ~b_empty;
    assign b_rinc = ~b_empty & i_bready;

    ///////////////////////////////////////////////////////////////////////////
    // Read Address Channel
    ///////////////////////////////////////////////////////////////////////////

    localparam AR_ASIZE = (MST_OSTDREQ_NUM==0) ? 2 : $clog2(MST_OSTDREQ_NUM);

    async_fifo 
    #(
    .DSIZE       (ARCH_W),
    .ASIZE       (AR_ASIZE),
    .FALLTHROUGH ("TRUE")
    )
    ar_dcfifo 
    (
    .wclk    (i_aclk),
    .wrst_n  (i_aresetn),
    .winc    (ar_winc),
    .wdata   (arch),
    .wfull   (ar_full),
    .awfull  (),
    .rclk    (o_aclk),
    .rrst_n  (o_aresetn),
    .rinc    (ar_rinc),
    .rdata   (o_arch),
    .rempty  (ar_empty),
    .arempty ()
    );

    assign i_arready = ~ar_full;
    assign ar_winc = i_arvalid & ~ar_full; 

    assign o_arvalid = ~ar_empty;
    assign ar_rinc = ~ar_empty & o_arready;

    ///////////////////////////////////////////////////////////////////////////
    // Read Data Channel
    ///////////////////////////////////////////////////////////////////////////

    localparam R_ASIZE = (MST_OSTDREQ_NUM==0) ? 2 : $clog2(MST_OSTDREQ_NUM);

    async_fifo 
    #(
    .DSIZE       (RCH_W+1),
    .ASIZE       (R_ASIZE),
    .FALLTHROUGH ("TRUE")
    )
    r_dcfifo 
    (
    .wclk    (i_aclk),
    .wrst_n  (i_aresetn),
    .winc    (r_winc),
    .wdata   ({o_rlast,o_rch}),
    .wfull   (r_full),
    .awfull  (),
    .rclk    (o_aclk),
    .rrst_n  (o_aresetn),
    .rinc    (r_rinc),
    .rdata   ({i_rlast, i_rresp, i_rid, i_rdata}),
    .rempty  (r_empty),
    .arempty ()
    );

    assign o_rready = ~r_full;
    assign r_winc = o_rvalid & ~r_full; 

    assign i_rvalid = ~r_empty;
    assign r_rinc = ~r_empty & i_rready;


    end else if (MST_OSTDREQ_NUM>0) begin: BUFF_STAGE


    end else begin: NO_CDC_NO_BUFFERING

    assign o_awvalid = i_awvalid;
    assign o_awch = awch;
    assign i_awready = o_awready;

    assign o_wvalid = i_wvalid;
    assign i_wready = o_wready;
    assign o_wlast = i_wlast;

    assign o_wch = {i_wstrb, i_wdata};

    assign i_bvalid = o_bvalid;
    assign o_bready = i_bready;
    assign {i_bresp, i_bid} = o_bch;

    assign o_arvalid = i_arvalid;
    assign i_arready = o_arready;
    assign o_arch = arch;

    assign i_rvalid = o_rvalid;
    assign o_rready = i_rready;
    assign i_rlast = o_rlast;
    assign {i_rresp, i_rdata, i_rid} = o_rch;

    end

    endgenerate

endmodule

`resetall

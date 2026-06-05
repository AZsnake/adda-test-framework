// Copyright (c) 2007-2012, INNOFIDEI Technologies. All Rights Reserved.
// INNOFIDEI Confidential Proprietary
// --------------------------------------------------------------------------
// FILE NAME : spspi_data_shift.v
// AUTHOR :GaoBin
// AUTHOR'S EMAIL :
// -----------------------------------------------------------------------------
// RELEASE HISTORY
// VERSION    DATE          AUTHOR            DESCRIPTION
// 1.0        2010-12-05     gaobin            initial
// -----------------------------------------------------------------------------
// PURPOSE : spi core
// -----------------------------------------------------------------------------
// Clock Domains :
// Other :
// -FHDR------------------------------------------------------------------------
//------------------------------------------------------------------------------
// Module Declaration
//------------------------------------------------------------------------------
module rf_spi_core (
  clk                  ,
  rst_n                ,
  soft_reset           ,
  spi_slv_sel          ,
  spi_frame_size       ,
  spi_switch_point     ,
  spi_data             ,
  spi_start            ,
  spi_cpol             ,
  spi_cpha             ,
  spi_divider          ,
  spi_bidrection       ,
  spi_read             ,
  spi_capture_delay_sel,

  spi_rdata            ,
  spi_cmd_done         ,

  spi0_miso0           ,
  spi1_miso0           ,
  spi2_miso0           ,
  spi3_miso0           ,
  spi4_miso0           ,
  spi5_miso0           ,
  spi7_miso0           ,

  spi0_miso1           ,
  spi1_miso1           ,
  spi2_miso1           ,
  spi3_miso1           ,
  spi4_miso1           ,
  spi5_miso1           ,
  spi7_miso1           ,

  spi0_clk             ,
  spi1_clk             ,
  spi2_clk             ,
  spi3_clk             ,
  spi4_clk             ,
  spi5_clk             ,
  spi7_clk             ,

  spi0_mosi            ,
  spi1_mosi            ,
  spi2_mosi            ,
  spi3_mosi            ,
  spi4_mosi            ,
  spi5_mosi            ,
  spi7_mosi            ,


  spi0_oen             ,
  spi1_oen             ,
  spi2_oen             ,
  spi3_oen             ,
  spi4_oen             ,
  spi5_oen             ,
  spi7_oen             ,

  spi0_cs              ,
  spi1_cs              ,
  spi2_cs              ,
  spi3_cs              ,
  spi4_cs              ,
  spi5_cs              ,
  spi6_cs              ,
  spi7_cs

  );

//------------------------------------------------------------------------------
// Inputs / Outputs
//------------------------------------------------------------------------------
  input         clk                  ;
  input         rst_n                ;
  input         soft_reset           ;
  input  [2 :0] spi_slv_sel          ;

  input  [5 :0] spi_frame_size       ;
  input  [4 :0] spi_switch_point     ;
  input  [55:0] spi_data             ;
  input         spi_start            ;
  input         spi_cpol             ;
  input         spi_cpha             ;
  input  [15:0] spi_divider          ;
  input         spi_bidrection       ;
  input         spi_read             ;
  input         spi_capture_delay_sel;

  output [55:0] spi_rdata            ;
  output        spi_cmd_done         ;

  input         spi0_miso0           ;
  input         spi1_miso0           ;
  input         spi2_miso0           ;
  input         spi3_miso0           ;
  input         spi4_miso0           ;
  input         spi5_miso0           ;
  input         spi7_miso0           ;

  input         spi0_miso1           ;
  input         spi1_miso1           ;
  input         spi2_miso1           ;
  input         spi3_miso1           ;
  input         spi4_miso1           ;
  input         spi5_miso1           ;
  input         spi7_miso1           ;

  output        spi0_clk             ;
  output        spi1_clk             ;
  output        spi2_clk             ;
  output        spi3_clk             ;
  output        spi4_clk             ;
  output        spi5_clk             ;
  output        spi7_clk             ;

  output        spi0_mosi            ;
  output        spi1_mosi            ;
  output        spi2_mosi            ;
  output        spi3_mosi            ;
  output        spi4_mosi            ;
  output        spi5_mosi            ;
  output        spi7_mosi            ;

  output        spi0_oen             ;
  output        spi1_oen             ;
  output        spi2_oen             ;
  output        spi3_oen             ;
  output        spi4_oen             ;
  output        spi5_oen             ;
  output        spi7_oen             ;

  output        spi0_cs              ;
  output        spi1_cs              ;
  output        spi2_cs              ;
  output        spi3_cs              ;
  output        spi4_cs              ;
  output        spi5_cs              ;
  output        spi6_cs              ;
  output        spi7_cs              ;

//------------------------------------------------------------------------------
//internal signals
//------------------------------------------------------------------------------
  wire tx_shift  ;
  wire rx_shift  ;
  wire pos_edge  ;
  wire neg_edge  ;
  reg  spi_miso  ;
  wire spi_clk_en;
  wire clkgen_en ;
//------------------------------------------------------------------------------
//beginning main code
//------------------------------------------------------------------------------

always@*
  begin
    case(spi_slv_sel)
    3'h0: spi_miso = spi_bidrection?spi0_miso0:spi0_miso1;
    3'h1: spi_miso = spi_bidrection?spi1_miso0:spi1_miso1;
    3'h2: spi_miso = spi_bidrection?spi2_miso0:spi2_miso1;
    3'h3: spi_miso = spi_bidrection?spi3_miso0:spi3_miso1;
    3'h4: spi_miso = spi_bidrection?spi4_miso0:spi4_miso1;
    3'h5: spi_miso = spi_bidrection?spi5_miso0:spi5_miso1;
    3'h6: spi_miso = spi_bidrection?spi2_miso0:spi2_miso1;
    3'h7: spi_miso = spi_bidrection?spi7_miso0:spi7_miso1;
    endcase
end

  spi_data_shift spi_data_shift
(
    .clk         (clk         ),
    .rst_n       (rst_n       ),
    .soft_reset  (soft_reset  ),
    .spi_slv_sel (spi_slv_sel ),
    .spi_data    (spi_data    ),
    .spi_en      (spi_clk_en    ),
    .spi_start   (spi_start   ),
    .tx_shift    (tx_shift    ),
    .rx_shift    (rx_shift    ),
    .spi_miso    (spi_miso    ),
    .spi_rdata   (spi_rdata   ),
    .spi0_mosi   (spi0_mosi),
    .spi1_mosi   (spi1_mosi),
    .spi2_mosi   (spi2_mosi),
    .spi3_mosi   (spi3_mosi),
    .spi4_mosi   (spi4_mosi),
    .spi5_mosi   (spi5_mosi),
    .spi7_mosi   (spi7_mosi)
  );

  spi_frame_fsm spi_frame_fsm
  (
    .clk                    (clk                  ),
    .rst_n                  (rst_n                ),
    .soft_reset             (soft_reset),

    .spi_start              (spi_start            ),
    .spi_slv_sel            (spi_slv_sel          ),
    .spi_cpol               (spi_cpol             ),
    .spi_cpha               (spi_cpha             ),
    .spi_frame_size         (spi_frame_size       ),
    .spi_switch_point       (spi_switch_point     ),
    .pos_edge               (pos_edge             ),
    .neg_edge               (neg_edge             ),
    .spi_bidrection         (spi_bidrection       ),
    .spi_read               (spi_read             ),
    .spi_capture_delay_sel  (spi_capture_delay_sel),

    .spi0_oen               (spi0_oen),
    .spi1_oen               (spi1_oen),
    .spi2_oen               (spi2_oen),
    .spi3_oen               (spi3_oen),
    .spi4_oen               (spi4_oen),
    .spi5_oen               (spi5_oen),
    .spi7_oen               (spi7_oen),

    .spi0_cs                (spi0_cs),
    .spi1_cs                (spi1_cs),
    .spi2_cs                (spi2_cs),
    .spi3_cs                (spi3_cs),
    .spi4_cs                (spi4_cs),
    .spi5_cs                (spi5_cs),
    .spi6_cs                (spi6_cs),
    .spi7_cs                (spi7_cs),

    .clkgen_en       (clkgen_en),
    .spi_clk_en      (spi_clk_en    ) ,

    .tx_shift               (tx_shift  ),
    .rx_shift               (rx_shift  ),
    .trans_done             (spi_cmd_done)
    );

  spi_clkgen spi_clkgen (
    .clk             (clk         ) ,
    .rst_n           (rst_n       ) ,
    .soft_reset             (soft_reset),
    .spi_slv_sel     (spi_slv_sel ),
    .clkgen_en       (clkgen_en),
    .spi_clk_en      (spi_clk_en    ) ,
    .spi_cpol        (spi_cpol        ) ,
    .spi_divider     (spi_divider     ) ,
    .spi0_clk        (spi0_clk),
    .spi1_clk        (spi1_clk),
    .spi2_clk        (spi2_clk),
    .spi3_clk        (spi3_clk),
    .spi4_clk        (spi4_clk),
    .spi5_clk        (spi5_clk),
    .spi7_clk        (spi7_clk),
    .pos_edge    (pos_edge      ) ,
    .neg_edge    (neg_edge      )
 );

endmodule

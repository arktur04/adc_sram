`timescale 1ns/100ps

module adc_sram_tb();

localparam ADC_DATA_WIDTH = 16;

reg clk, rst_n;
reg [ADC_DATA_WIDTH - 1: 0] adc1_data, adc2_data;
wire adc_clk;
reg spi_mosi;
reg spi_sclk;
reg spi_cs_n;
wire spi_miso;
wire done;

always #10 clk = ~clk;

initial
begin
  clk = 1'b0;
  rst_n = 1'b0;
  #1 rst_n = 1'b1;
  #100000;
  //$stop; 
end

// adc inputs
integer cnt;
reg [7: 0] data;

//reset signal
reg reset;

initial
begin
  reset = 0;
  spi_cs_n = 1;
  spi_sclk = 0;
  spi_mosi = 0;  
  adc1_data = 100;
  adc2_data = 200;
  cnt = 0;
  //---------------------
  // register map
  //---------------------
  /*
  localparam ADC_READ_PRESCALER_LO_ADDR = 0;
  localparam ADC_READ_PRESCALER_HI_ADDR = 1;
  localparam TRIG_LEVEL_LO_ADDR = 2;
  localparam TRIG_LEVEL_HI_ADDR = 3;
  localparam BUFFER_LEN_ADDR = 4;
  localparam START_READING_ADDR = 5;
  */
  #100
  spi_write(.data(0)); //adc read prescaler (lo)
  #100
  spi_write(.data(8'h03)); // Fadc = Fclk / 4
  #100
  spi_write(.data(1)); //adc read prescaler (hi)
  #100
  spi_write(.data(0)); // 
  #100
  spi_write(.data(2)); //trigger level (low byte)
  #100
  // trigger at a half of the adc range (0x7fff)
  spi_write(.data(8'hff)); // low byte of the trigger
  #100
  spi_write(.data(3)); //trigger level (high byte)
  #100
  spi_write(.data(8'h7f)); // high byte of the trigger  
  #100
  spi_write(.data(4)); //buffer length
  #100
  spi_write(.data(8'h00)); // buffer length = (0x00 + 1) * 256 = 256  
  #100
  spi_write(.data(5)); //status reg
  #100
  spi_write(.data(8'h01)); // start bit      
end

task spi_write;
input wire [7:0] data;
integer i;
begin
  //------------------------------
  // send data to spi
  spi_cs_n = 0;
  spi_sclk = 0;
  spi_mosi = 0;
  #100;
  for (i = 0; i < 8; i = i + 1) 
  begin
  #50 spi_mosi = data[i];
  spi_sclk = 1;
  #50 spi_sclk = 0; 
  end  
  #100; 
  spi_cs_n = 1;
end
endtask

reg [31: 0] miso_data;

integer i;

initial
begin
  #40200;
  spi_write(.data(5)); //start
  #20
  spi_write(.data(8'h02)); // data_read bit 
  for(i = 0; i < 256; i = i + 1)
  begin
    spi_read(.data(miso_data));
  end
end

task spi_read;
output reg [31:0] data;
integer i;
begin
  //------------------------------
  // read data from spi
  spi_cs_n = 0;
  spi_sclk = 0;
  spi_mosi = 0;
  #100;
  for (i = 0; i < 32; i = i + 1) 
  begin
    spi_sclk = 1;
    #50 data[i] = spi_miso;
    spi_sclk = 0;
    #50;
  end
  #100;
  spi_cs_n = 1;   
end
endtask

// adc sets data on both rising and falling edges of the clk signal 
always@(adc_clk)
begin
  adc1_data = 32'bx;
  adc2_data = 32'bx;
  #5.4 // delay between a clk edge and data, ns
  adc1_data = cnt * 100; //adc1_data + 1;
  adc2_data = cnt * 200; //adc2_data + 2;
  cnt = cnt + 1;
  if(cnt == (2 ** ADC_DATA_WIDTH))
  cnt = 0; 
end
//--------------------------------
//  MODULE adc_sram INTERFACE
// module adc_sram
//  #(parameter
// RAM_ADDR_WIDTH = 11,
// RAM_DATA_WIDTH = 32,
// ADC_DATA_WIDTH = 16,
// SPI_CLOCK_POL = 0,
// SPI_MOSI_DATA_CNT_WIDTH = 3, // for 8-bit mosi data
// SPI_MISO_DATA_CNT_WIDTH = 5 // for 32-bit miso data
// )
// (
//  // reset and clock
//  input wire rst_n, clk,
//  // adc interface
//  input wire [ADC_DATA_WIDTH - 1:0] adc1_data, adc2_data,
//  output reg adc_clk,
//  // start/done signals
//  input wire start,
//  output reg done,
//  // spi interface
//  input wire spi_mosi,
//  input wire spi_sclk,
//  input wire spi_cs_n,
//  output reg spi_miso 
// ); 
// -----------------------------

adc_sram dut(
  // reset and clock
  .rst_n(rst_n), .clk(clk),
  // adc interface
  .adc1_data(adc1_data), .adc2_data(adc2_data),
  .adc_clk(adc_clk),
  // start/done signals
  .done(done),
  // reset signal
  .reset(reset),
  // spi interface
  .spi_mosi(spi_mosi),
  .spi_sclk(spi_sclk),
  .spi_cs_n(spi_cs_n),
  .spi_miso(spi_miso)
);

endmodule

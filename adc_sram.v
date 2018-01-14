//ADC LTC2296 or similar 

module adc_sram
  #(parameter
   RAM_ADDR_WIDTH = 11,
   RAM_DATA_WIDTH = 32,
   ADC_DATA_WIDTH = 16,
   SPI_CLOCK_POL = 0,
   SPI_MOSI_DATA_CNT_WIDTH = 3, // for 8-bit mosi data
   SPI_MISO_DATA_CNT_WIDTH = 5, // for 32-bit miso data
   SPI_ADDR_WIDTH = 3
  )
(
  // reset and clock
  input wire rst_n, clk,
  // adc interface
  input wire [ADC_DATA_WIDTH - 1: 0] adc1_data, adc2_data,
  output reg adc_clk,
  // done signals
  output reg done,
  // resets the state machine to the stop state
  input wire reset,
  // spi interface
  input wire spi_mosi,
  input wire spi_sclk,
  input wire spi_cs_n,
  output reg spi_miso
);

//fsm declaration
localparam STATE_STOP = 0;
localparam STATE_WAIT = 1;
localparam STATE_RUN = 2;
localparam STATE_SPI_CONFIG_ADDR = 3;
localparam STATE_SPI_CONFIG_REG = 4;
localparam STATE_SPI_DATA_READ = 5;

localparam STATE_REG_WIDTH = 3; 
reg [STATE_REG_WIDTH - 1: 0] state_reg;
//

//--------------------------------------------------------------------
//adc_clk prescaler
//--------------------------------------------------------------------
// Fadc_clk = Fclk / ADC_CLK_PRESCALER
// for Fclk = 50 MHz, ADC_CLK_PRESCALER = 4:
// Fadc_clk = 50 / 2 = 12.5 MHz
// (for 25 MSPS ADC)
// notice that one sample is taken on rising edge of adc_clk,
// and one sample on falling edge.
// the clk_prescaler is hardcoded and can not be changed in runtime.
localparam ADC_CLK_PRESCALER_WIDTH = 2;

reg [ADC_CLK_PRESCALER_WIDTH - 1: 0] adc_clk_cnt_reg;
wire [ADC_CLK_PRESCALER_WIDTH - 1: 0] adc_clk_cnt_next = adc_clk_cnt_reg + 1'b1;

always@(*) adc_clk <= adc_clk_cnt_reg[0];

always@(posedge clk or negedge rst_n)
  begin
    if(!rst_n)
    begin
      adc_clk_cnt_reg <= 0;
    end
    else
    begin
      if((state_reg == STATE_RUN) | (state_reg == STATE_WAIT))
      begin
          adc_clk_cnt_reg <= adc_clk_cnt_next;
      end
      else
      begin
          adc_clk_cnt_reg <= 0;
      end
    end
  end
  
//--------------------------------------------------------------------
// adc_prescaler_reg is the coefficient, which control,
// how many samples are skipped before one sample will be taken
// for example, if adc_prescaler_reg = 0, each sample will be taken,
// if adc_prescaler_reg = 1, one sample is skipped, one is taken 
localparam ADC_READ_PRESCALER_WIDTH = 16;
localparam DEFAULT_PRESCALER = 0; 

reg [ADC_READ_PRESCALER_WIDTH - 1: 0] adc_read_prescaler_reg;

reg [ADC_READ_PRESCALER_WIDTH - 1: 0] adc_read_cnt_reg;

wire [ADC_CLK_PRESCALER_WIDTH - 1: 0] adc_read_cnt_next = adc_read_cnt_reg + 1'b1;

wire adc_read = adc_read_cnt_next == 0;

always@(posedge clk or negedge rst_n)
  begin
    if(!rst_n)
    begin
      adc_read_cnt_reg <= 0;
    end
    else
    begin
      if((state_reg == STATE_RUN) | (state_reg == STATE_WAIT))
      begin
          if(adc_read_cnt_next == adc_read_prescaler_reg + 1'b1)
          begin
            adc_read_cnt_reg <= 0;
          end
          else
          begin
            adc_read_cnt_reg <= adc_read_cnt_next;
          end
      end
      else
      begin
        adc_read_cnt_reg <= 0;
      end
    end
  end

//----------------------------
// just metastable filter
reg [ADC_DATA_WIDTH - 1: 0] adc1_data_reg, adc2_data_reg;

always@(posedge clk or negedge rst_n)
begin
  if(!rst_n)
  begin
    adc1_data_reg <= 0;
    adc2_data_reg <= 0;
  end
  else
  begin
    adc1_data_reg <= adc1_data;
    adc2_data_reg <= adc2_data;
  end
end
//----------------------------
// reading adc
reg [ADC_DATA_WIDTH - 1: 0] adc1_reading_reg, adc2_reading_reg;

always@(posedge clk or negedge rst_n)
begin
  if(!rst_n)
  begin
    adc1_reading_reg <= 0;
    adc2_reading_reg <= 0;
  end
  else
  begin
    if(adc_read)
    begin
      adc1_reading_reg <= adc1_data_reg;
      adc2_reading_reg <= adc2_data_reg;
    end
  end
end

//----------------------------------
// write to SRAM
//----------------------------------

// default buffer len - 1
// fo example, if ADDR_WIDTH = 11, DEFAULT_BUFF_LEN = 7
// actual buffer len is (buff_len_reg + 1) * 256
localparam DEFAULT_BUFF_LEN = 7;
localparam BUFF_REG_LEN_WIDTH = 8; 

reg [RAM_ADDR_WIDTH - 1: 0] sram_addr_reg;
reg [BUFF_REG_LEN_WIDTH - 1: 0] buff_len_reg;

wire adc_data_ready = adc_read_cnt_next == adc_read_prescaler_reg;
wire [RAM_ADDR_WIDTH - 1: 0] sram_addr_next = sram_addr_reg + 1'b1; 

wire acquisition_done = sram_addr_next[RAM_ADDR_WIDTH - 1: BUFF_REG_LEN_WIDTH] > buff_len_reg;

always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        sram_addr_reg <= 0;
    end
    else
    begin
        if(state_reg == STATE_STOP)
        begin
            sram_addr_reg <= 0;
        end
        else if(state_reg == STATE_RUN)
        begin
          if(adc_data_ready)
            begin
                if(!acquisition_done) 
                begin
                  sram_addr_reg <= sram_addr_next;
                end  
            end
        end
    end
end

//done signal
always@(*) done = state_reg == STATE_RUN;
//----------------------------------
// the trigger
//---------------------
reg [ADC_DATA_WIDTH - 1: 0] trig_level_reg, adc1_data_1_reg;

wire trigger = (adc1_data_1_reg < trig_level_reg) & (adc1_data_reg >= trig_level_reg);

always@(posedge clk or negedge rst_n)
  begin
    if(!rst_n)
    begin
      adc1_data_1_reg <= 0;
    end
    else
    begin
        if((state_reg == STATE_RUN) | (state_reg == STATE_WAIT))
        begin
            adc1_data_1_reg <= adc1_data_reg;
        end
    end
  end
   
//---------------------------------
// spi interface
//  input wire spi_mosi,
//  input wire spi_sclk,
//  input wire spi_cs_n,
//  output reg spi_miso

reg spi_mosi_reg;
reg spi_sclk_reg;
reg spi_sclk_reg_1;
reg spi_cs_n_reg;

// input registers
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        spi_mosi_reg <= 1'b0;
        spi_sclk_reg <= 1'b0;
        spi_sclk_reg_1 <= 1'b0;
        spi_cs_n_reg <= 1'b1;     
    end
    else
    begin
        spi_mosi_reg <= spi_mosi;
        spi_sclk_reg <= spi_sclk;
        spi_sclk_reg_1 <= spi_sclk_reg;
        spi_cs_n_reg <= spi_cs_n;
    end
end

wire clk_pos_edge = ~spi_sclk_reg_1 & spi_sclk_reg;
wire clk_neg_edge = spi_sclk_reg_1 & ~spi_sclk_reg;

// spi data receive (MOSI)
// -------------------------
localparam SPI_MOSI_DATA_WIDTH = 2 ** SPI_MOSI_DATA_CNT_WIDTH;
 
 reg [SPI_MOSI_DATA_WIDTH - 1: 0] spi_mosi_data_reg;
 reg [SPI_MOSI_DATA_CNT_WIDTH: 0] spi_mosi_bit_cnt_reg;
 
 wire [SPI_MOSI_DATA_CNT_WIDTH: 0] spi_mosi_bit_cnt_next = spi_mosi_bit_cnt_reg + 1'b1;
 wire spi_reading_done = spi_mosi_bit_cnt_reg == SPI_MOSI_DATA_WIDTH;
 
always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        spi_mosi_data_reg <= 0;
        spi_mosi_bit_cnt_reg <= 0;
    end
    else
    begin
        if(spi_cs_n_reg == 1'b0)
        begin
          if((clk_pos_edge & (SPI_CLOCK_POL == 1 )) | (clk_neg_edge & (SPI_CLOCK_POL == 0 )))
          begin
              spi_mosi_data_reg <= {spi_mosi_reg, spi_mosi_data_reg[SPI_MOSI_DATA_WIDTH - 1: 1]};
              spi_mosi_bit_cnt_reg <= spi_mosi_bit_cnt_next;
          end  
          if(spi_mosi_bit_cnt_reg == SPI_MOSI_DATA_WIDTH)
          begin
            spi_mosi_bit_cnt_reg <= 0;
          end
        end
    end
end

// spi data transmit (MISO)
// -------------------------
localparam SPI_MISO_DATA_WIDTH = 2 ** SPI_MISO_DATA_CNT_WIDTH;

reg [SPI_MISO_DATA_CNT_WIDTH - 1: 0] spi_miso_bit_cnt_reg;
wire [SPI_MISO_DATA_CNT_WIDTH: 0] spi_miso_bit_cnt_next = spi_miso_bit_cnt_reg + 1'b1;

reg [RAM_ADDR_WIDTH - 1: 0] spi_addr_reg; //current address im bram for transmitting data
wire [RAM_ADDR_WIDTH: 0] spi_addr_next = spi_addr_reg + 1'b1;

wire [RAM_DATA_WIDTH - 1: 0] q;

wire spi_transmit_done = spi_addr_reg[RAM_ADDR_WIDTH - 1: BUFF_REG_LEN_WIDTH] == (buff_len_reg + 1'b1);

always@(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        spi_miso_bit_cnt_reg <= 0;
        spi_addr_reg <= 0;
        spi_miso <= 0;
    end    
    else
    begin
        if((spi_cs_n_reg == 1'b0) & (state_reg == STATE_SPI_DATA_READ))
        begin
          if((clk_pos_edge & (SPI_CLOCK_POL == 1)) | (clk_neg_edge & (SPI_CLOCK_POL == 0))) //transmit data on the rising edge (if SPI_CLOCK_POL == 1)
          begin
              spi_miso <= q[spi_miso_bit_cnt_reg];
              spi_miso_bit_cnt_reg <= spi_miso_bit_cnt_next;
              if(spi_miso_bit_cnt_next == RAM_DATA_WIDTH)
              begin
                  spi_addr_reg <= spi_addr_next;
              end
          end
        end
    end
end

// control registers
//-----------------------------------------------------------------
// register                  address                   comment
//-----------------------------------------------------------------
// adc_read_prescaler_reg    ADC_READ_PRESCALER_ADDR
// trig_level_reg            TRIG_LEVEL_ADDR           set the trigger level
// buff_len_reg              BUFFER_LEN_ADDR           memory buffer length
// start_reading_reg         START_READING_ADDR        set to 1 to read the buffer 

localparam ADC_READ_PRESCALER_LO_ADDR = 0;
localparam ADC_READ_PRESCALER_HI_ADDR = 1;
localparam TRIG_LEVEL_LO_ADDR = 2;
localparam TRIG_LEVEL_HI_ADDR = 3;
localparam BUFFER_LEN_ADDR = 4;
localparam START_READING_ADDR = 5;

reg start_reg;
reg start_reading_reg;
reg [SPI_ADDR_WIDTH - 1: 0] spi_regaddr_reg;

always@(posedge clk or negedge rst_n)
  begin
    if(!rst_n)
    begin
      adc_read_prescaler_reg <= DEFAULT_PRESCALER; //default prescaler
      // set the trigger level at a half of an adc range
      trig_level_reg <= 2 ** (ADC_DATA_WIDTH - 1);
      buff_len_reg <= DEFAULT_BUFF_LEN;
      start_reg <= 0;
      start_reading_reg <= 0;
      spi_regaddr_reg <= 0;   
    end
    else
    begin
      if(spi_reading_done & (state_reg == STATE_SPI_CONFIG_ADDR)) 
      begin
        spi_regaddr_reg <= spi_mosi_data_reg[SPI_ADDR_WIDTH - 1: 0];
      end
      else
      if(spi_reading_done & (state_reg == STATE_SPI_CONFIG_REG))
      begin
        case(spi_regaddr_reg)
            ADC_READ_PRESCALER_LO_ADDR: adc_read_prescaler_reg[SPI_MOSI_DATA_WIDTH - 1: 0] <= spi_mosi_data_reg;
            ADC_READ_PRESCALER_HI_ADDR: adc_read_prescaler_reg[2 * SPI_MOSI_DATA_WIDTH - 1: SPI_MOSI_DATA_WIDTH] <= spi_mosi_data_reg;
            TRIG_LEVEL_LO_ADDR: trig_level_reg[SPI_MOSI_DATA_WIDTH - 1: 0] <= spi_mosi_data_reg;
            TRIG_LEVEL_HI_ADDR: trig_level_reg[2 * SPI_MOSI_DATA_WIDTH - 1: SPI_MOSI_DATA_WIDTH] <= spi_mosi_data_reg;
            BUFFER_LEN_ADDR: buff_len_reg <= spi_mosi_data_reg;
            default: // STATE_REG_ADDR
            begin
                start_reg <= spi_mosi_data_reg[0];
                start_reading_reg <= spi_mosi_data_reg[1];
            end
        endcase
      end
      else
      if(state_reg == STATE_SPI_DATA_READ)
      begin
        start_reading_reg <= 0;
      end
      else if(state_reg == STATE_WAIT)
      begin
        start_reg <= 0;
      end
    end
  end

// FSM
//------------------------------
/*
localparam STATE_STOP = 0;
localparam STATE_WAIT = 1;
localparam STATE_RUN = 2;
localparam STATE_SPI_CONFIG_ADDR = 3;
localparam STATE_SPI_CONFIG_REG = 4;
localparam STATE_SPI_DATA_READ = 5;
*/

always@(posedge clk or negedge rst_n)
  begin
    if(!rst_n)
    begin
      state_reg <= STATE_STOP;
    end
    else
    begin
        case(state_reg)
            STATE_STOP:
                begin
                    if(start_reg)
                    begin
                      state_reg <= STATE_WAIT;
                    end
                    else if(spi_cs_n_reg == 0 & !start_reading_reg)
                    begin
                        state_reg <= STATE_SPI_CONFIG_ADDR;
                    end
                    else if(spi_cs_n_reg == 0 & start_reading_reg) 
                    begin
                        state_reg <= STATE_SPI_DATA_READ;
                    end
                  end            
            STATE_WAIT:
            begin
              if(reset)
              begin
                state_reg <= STATE_STOP;
              end
              else if(trigger)
              begin
                state_reg <= STATE_RUN;
              end
            end
            STATE_RUN:
            begin
                    if(reset)
                    begin
                        state_reg <= STATE_STOP;
                    end
                    else if(acquisition_done)
                    begin
                      state_reg <= STATE_STOP;
                    end
                  end      
            STATE_SPI_CONFIG_ADDR:
         begin
                    if(reset)
                    begin
                        state_reg <= STATE_STOP;
                    end
                    else if(spi_reading_done)
                    begin
                      state_reg <= STATE_SPI_CONFIG_REG;
                    end
                  end
                     STATE_SPI_CONFIG_REG:
                        begin
                          if(reset)
                          begin
                              state_reg <= STATE_STOP;
                          end
                          else if(spi_reading_done & start_reg)
                                  begin
                                    state_reg <= STATE_WAIT;
                                  end 
                          else if(spi_reading_done /*& !start_reading_reg*/)
                          begin
                            state_reg <= STATE_STOP;
                          end
                        end
                        STATE_SPI_DATA_READ:
                        begin
                          if(reset | spi_transmit_done)
                          begin
                            state_reg <= STATE_STOP;
                          end      
                        end
        endcase
        /*
      if(state_reg == STATE_STOP)
      begin
        if(start_reg)
        begin
          state_reg <= STATE_WAIT;
        end
        else if(spi_cs_n_reg == 0 & !start_reading_reg)
        begin
            state_reg <= STATE_SPI_CONFIG_ADDR;
        end
        else if(spi_cs_n_reg == 0 & start_reading_reg) 
        begin
            state_reg <= STATE_SPI_DATA_READ;
        end
      end
      else if(state_reg == STATE_WAIT)
      begin
        if(reset)
        begin
          state_reg <= STATE_STOP;
        end
        else if(trigger)
        begin
          state_reg <= STATE_RUN;
        end
      end
      else if(state_reg == STATE_RUN)
      begin
        if(reset)
        begin
            state_reg <= STATE_STOP;
        end
        else if(acquisition_done)
        begin
          state_reg <= STATE_STOP;
        end
      end
      else if(state_reg == STATE_SPI_CONFIG_ADDR)
      begin
        if(reset)
        begin
            state_reg <= STATE_STOP;
        end
        else if(spi_reading_done)
        begin
          state_reg <= STATE_SPI_CONFIG_REG;
        end
      end
      else if(state_reg == STATE_SPI_CONFIG_REG)
      begin
        if(reset)
        begin
            state_reg <= STATE_STOP;
        end
        else if(spi_reading_done & start_reg)
                begin
                  state_reg <= STATE_WAIT;
                end 
        else if(spi_reading_done)
        begin
          state_reg <= STATE_STOP;
        end
      end
      else if(state_reg == STATE_SPI_DATA_READ)
      begin
        if(reset | spi_transmit_done)
        begin
          state_reg <= STATE_STOP;
        end      
      end*/
    end 
  end

//-----------------------------------
// ram instance (32 * 1K) in BRAM
//----------------------------------
wire [RAM_DATA_WIDTH - 1: 0] data = {adc2_reading_reg, adc1_reading_reg}; 

wire [RAM_ADDR_WIDTH - 1: 0] addr = (state_reg == STATE_SPI_DATA_READ)? spi_addr_reg: sram_addr_reg;
wire we = state_reg == STATE_RUN;

single_port_ram buffer(.data(data), .addr(addr), .we(we), .clk(clk), .q(q));

endmodule

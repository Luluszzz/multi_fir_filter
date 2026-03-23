// DAC 格式化数据
// 功能：将ADC 12bit数据扩展为DAC 14bit数据，高位对齐
// 后续可替换为FIR滤波器等处理模块，保持接口一致即可
module dac_format (
    input  wire        clk,            // 系统工作时钟
    input  wire        rst_n,          // 异步复位，低有效
    input  wire [11:0] din,            // 输入数据（12bit ADC数据）
    input  wire        din_valid,      // 输入数据有效标志

    output reg  [13:0] dout,           // 输出数据（14bit DAC数据）
    output reg         dout_valid      // 输出数据有效标志
);

    // 12bit → 14bit，高位对齐，低2位补0
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout       <= 14'd0;
            dout_valid <= 1'b0;
        end else begin
            dout       <= {din, 2'b0};
            dout_valid <= din_valid;
        end
    end

endmodule

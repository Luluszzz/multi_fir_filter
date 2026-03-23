// AD9767 单通道DAC发送模块（Sink）
// 功能：接收14bit数据并通过AD9767输出模拟信号
// 采样时钟由顶层分频后传入，支持可配置采样率
module dac_ad9767 (
    input  wire        clk,            // 系统工作时钟（50MHz）
    input  wire        rst_n,          // 异步复位，低有效
    input  wire [13:0] dac_data_in,    // DAC输入数据
    input  wire        dac_data_valid, // 数据有效标志
    input  wire        sample_clk,     // 采样时钟（由顶层分频产生）

    output wire        dac_clk,        // DAC时钟输出
    output wire        dac_wrt,        // DAC写信号输出
    output reg  [13:0] dac_data        // DAC并行数据输出
);

    // 使用ODDR原语输出DAC时钟，跟随采样时钟
    ODDR #(
        .DDR_CLK_EDGE ("SAME_EDGE"),
        .INIT         (1'b0),
        .SRTYPE       ("ASYNC")
    ) u_oddr_dac_clk (
        .Q  (dac_clk),
        .C  (clk),
        .CE (1'b1),
        .D1 (sample_clk),
        .D2 (sample_clk),
        .R  (~rst_n),
        .S  (1'b0)
    );

    // 使用ODDR原语输出DAC写信号（与时钟同频同相）
    ODDR #(
        .DDR_CLK_EDGE ("SAME_EDGE"),
        .INIT         (1'b0),
        .SRTYPE       ("ASYNC")
    ) u_oddr_dac_wrt (
        .Q  (dac_wrt),
        .C  (clk),
        .CE (1'b1),
        .D1 (sample_clk),
        .D2 (sample_clk),
        .R  (~rst_n),
        .S  (1'b0)
    );

    // 数据寄存输出
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dac_data <= 14'd0;
        end else if (dac_data_valid) begin
            dac_data <= dac_data_in;
        end
    end

endmodule

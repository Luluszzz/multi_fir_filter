// AD9238 单通道ADC采样模块（Source）
// 功能：输出采样时钟给AD9238，采集12bit并行数据
// 采样时钟由顶层分频后传入，支持可配置采样率

module adc_ad9238 (
    input  wire        clk,            // 系统工作时钟（50MHz）
    input  wire        rst_n,          // 异步复位，低有效
    input  wire [11:0] adc_data,       // AD9238 并行数据输入
    input  wire        sample_clk,     // 采样时钟（由顶层分频产生）

    output wire        adc_clk,        // 输出给AD9238的采样时钟
    output reg  [11:0] sample_data,    // 采样数据输出
    output reg         sample_valid    // 数据有效标志
);

    // 使用ODDR原语输出采样时钟，保证时钟信号质量
    // D1=D2=sample_clk，输出跟随sample_clk，延迟一个系统时钟周期
    ODDR #(
        .DDR_CLK_EDGE ("SAME_EDGE"),
        .INIT         (1'b0),
        .SRTYPE       ("ASYNC")
    ) u_oddr_adc_clk (
        .Q  (adc_clk),
        .C  (clk),
        .CE (1'b1),
        .D1 (sample_clk),
        .D2 (sample_clk),
        .R  (~rst_n),
        .S  (1'b0)
    );

    // 检测采样时钟上升沿
    reg sample_clk_d1;
    reg sample_clk_d2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_clk_d1 <= 1'b0;
            sample_clk_d2 <= 1'b0;
        end else begin
            sample_clk_d1 <= sample_clk;
            sample_clk_d2 <= sample_clk_d1;
        end
    end

    // 下降沿检测：在采样时钟半周期处锁存数据，最大化建立/保持时间裕量
    wire sample_strobe = ~sample_clk_d1 & sample_clk_d2;

    // 在采样选通时锁存ADC数据
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_data  <= 12'd0;
            sample_valid <= 1'b0;
        end else begin
            sample_valid <= sample_strobe;
            if (sample_strobe)
                sample_data <= adc_data;
        end
    end

endmodule

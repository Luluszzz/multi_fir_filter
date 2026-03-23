// 顶层模块
// 功能：ADC采集 → FIR滤波 → 格式化 → DAC输出
// 管道架构：Source(adc_ad9238) → FIR(fir_filter) → Format(dac_format) → Sink(dac_ad9767)
module top #(
    parameter SYS_CLK_FREQ = 50_000_000,  // 系统时钟频率（Hz）
    parameter SAMPLE_RATE  = 2_000_000    // 采样率（Hz），默认2MHz
) (
    input  wire        sys_clk,              // 50MHz系统时钟
    input  wire        sys_rst_n,            // 异步复位按钮，低有效

    // AD9238 通道0
    output wire        ad9238_clk_ch0,       // AD9238 CH0 采样时钟
    input  wire [11:0] ad9238_data_ch0,      // AD9238 CH0 数据

    // AD9238 通道1
    // output wire        ad9238_clk_ch1,       // AD9238 CH1 采样时钟
    // input  wire [11:0] ad9238_data_ch1,      // AD9238 CH1 数据

    // AD9767 通道0
    output wire        ad9767_clk_ch0,      // AD9767 CH0 时钟
    output wire        ad9767_wrt_ch0,      // AD9767 CH0 写信号
    output wire [13:0] ad9767_data_ch0     // AD9767 CH0 数据

    // AD9767 通道1
    // output wire        ad9767_clk_ch1,      // AD9767 CH1 时钟
    // output wire        ad9767_wrt_ch1,      // AD9767 CH1 写信号
    // output wire [13:0] ad9767_data_ch1      // AD9767 CH1 数据
);

    // =========================================================================
    // 时钟与复位
    // =========================================================================
    wire clk_50m;           // 50MHz工作时钟
    wire clk_50m_unbuf;     // 未缓冲的50MHz时钟
    wire clk_fb;            // MMCM反馈时钟
    wire clk_fb_buf;        // 缓冲后的反馈时钟
    wire pll_locked;        // PLL锁定信号
    wire rst_n;             // 全局复位（PLL锁定 & 按钮复位）

    assign rst_n = sys_rst_n & pll_locked;

    // MMCME2_BASE：50MHz → 50MHz（PLL净化时钟抖动）
    // VCO频率 = 50MHz * CLKFBOUT_MULT_F / DIVCLK_DIVIDE = 50 * 13 / 1 = 650MHz
    // CLKOUT0 = VCO / CLKOUT0_DIVIDE_F = 650 / 13 = 50MHz
    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (13.0),         // VCO = 50 * 13 = 650MHz
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (20.0),          // 50MHz → 20ns
        .CLKOUT0_DIVIDE_F   (13.0),          // 650 / 13 = 50MHz
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKOUT0   (clk_50m_unbuf),
        .CLKOUT0B  (),
        .CLKOUT1   (),
        .CLKOUT1B  (),
        .CLKOUT2   (),
        .CLKOUT2B  (),
        .CLKOUT3   (),
        .CLKOUT3B  (),
        .CLKOUT4   (),
        .CLKOUT5   (),
        .CLKOUT6   (),
        .CLKFBOUT  (clk_fb),
        .CLKFBOUTB (),
        .LOCKED    (pll_locked),
        .CLKIN1    (sys_clk),
        .PWRDWN    (1'b0),
        .RST       (~sys_rst_n),
        .CLKFBIN   (clk_fb_buf)
    );

    // 工作时钟全局缓冲
    BUFG u_bufg_clk50m (
        .I (clk_50m_unbuf),
        .O (clk_50m)
    );

    // 反馈时钟全局缓冲
    BUFG u_bufg_fb (
        .I (clk_fb),
        .O (clk_fb_buf)
    );

    // =========================================================================
    // 采样时钟分频器
    // =========================================================================
    // 从系统时钟分频产生采样时钟方波
    // 分频系数 = SYS_CLK_FREQ / SAMPLE_RATE / 2
    // 50MHz / 2MHz / 2 = 12.5，取整为12，计数0~11翻转，实际采样率 ≈ 2.083MHz
    // 若需精确2MHz，可调整SYS_CLK_FREQ使其整除
    localparam DIV_CNT_MAX = SYS_CLK_FREQ / SAMPLE_RATE / 2 - 1;

    reg [$clog2(DIV_CNT_MAX+1)-1:0] div_cnt;
    reg                              sample_clk;

    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt    <= 0;
            sample_clk <= 1'b0;
        end else begin
            if (div_cnt == DIV_CNT_MAX) begin
                div_cnt    <= 0;
                sample_clk <= ~sample_clk;
            end else begin
                div_cnt <= div_cnt + 1'b1;
            end
        end
    end

    // =========================================================================
    // Source：ADC采样
    // =========================================================================
    wire [11:0] adc_sample_ch0;
    wire        adc_valid_ch0;

    adc_ad9238 u_adc_ch0 (
        .clk         (clk_50m),
        .rst_n       (rst_n),
        .adc_data    (ad9238_data_ch0),
        .sample_clk  (sample_clk),
        .adc_clk     (ad9238_clk_ch0),
        .sample_data (adc_sample_ch0),
        .sample_valid(adc_valid_ch0)
    );

    // =========================================================================
    // FIR 滤波器
    // =========================================================================
    wire [11:0] fir_data_ch0;
    wire        fir_valid_ch0;

    fir_filter u_fir_ch0 (
        .clk       (clk_50m),
        .din       (adc_sample_ch0),
        .din_valid (adc_valid_ch0),
        .dout      (fir_data_ch0),
        .dout_valid(fir_valid_ch0)
    );

    // =========================================================================
    // Middleware：格式化
    // =========================================================================
    wire [13:0] proc_data_ch0;
    wire        proc_valid_ch0;

    dac_format dac_format_ch0 (
        .clk       (clk_50m),
        .rst_n     (rst_n),
        .din       (fir_data_ch0),
        .din_valid (fir_valid_ch0),
        .dout      (proc_data_ch0),
        .dout_valid(proc_valid_ch0)
    );

    // =========================================================================
    // Sink：DAC输出
    // =========================================================================
    dac_ad9767 u_dac_da1 (
        .clk           (clk_50m),
        .rst_n         (rst_n),
        .dac_data_in   (proc_data_ch0),
        .dac_data_valid(proc_valid_ch0),
        .sample_clk    (sample_clk),
        .dac_clk       (ad9767_clk_ch0),
        .dac_wrt       (ad9767_wrt_ch0),
        .dac_data      (ad9767_data_ch0)
    );

endmodule

`default_nettype none

module tt_um_vga_ocarina (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  wire hsync;
  wire vsync;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;

  wire [1:0] R;
  wire [1:0] G;
  wire [1:0] B;

  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  hvsync_generator vga_sync_gen (
      .clk(clk),
      .reset(~rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(video_active),
      .hpos(pix_x),
      .vpos(pix_y)
  );

  wire inp_b, inp_y, inp_select, inp_start;
  wire inp_up, inp_down, inp_left, inp_right;
  wire inp_a, inp_x, inp_l, inp_r;
  wire pad_present;

  gamepad_pmod_single driver (
      .rst_n(rst_n),
      .clk(clk),
      .pmod_data(ui_in[6]),
      .pmod_clk(ui_in[5]),
      .pmod_latch(ui_in[4]),
      .b(inp_b),
      .y(inp_y),
      .select(inp_select),
      .start(inp_start),
      .up(inp_up),
      .down(inp_down),
      .left(inp_left),
      .right(inp_right),
      .a(inp_a),
      .x(inp_x),
      .l(inp_l),
      .r(inp_r),
      .is_present(pad_present)
  );



  function [10:0] absdiff;
    input [9:0] a;
    input [9:0] b;
    begin
      if (a >= b)
        absdiff = a - b;
      else
        absdiff = b - a;
    end
  endfunction
  function in_diamond;
    input [9:0] x;
    input [9:0] y;
    input [9:0] cx;
    input [9:0] cy;
    input [9:0] r;
    reg [10:0] dx;
    reg [10:0] dy;
    begin
      dx = absdiff(x, cx);
      dy = absdiff(y, cy);
      in_diamond = ((dx + dy) <= r);
    end
  endfunction

  reg  [17:0] note_div;
  reg         note_enable;
  reg  [17:0] tone_counter;
  reg         tone_ff;

  wire audio = note_enable ? tone_ff : 1'b0;

  assign uio_out = {audio, 7'b0};
  assign uio_oe  = 8'h80;


  always @(*) begin
    note_enable = 1'b0;
    note_div    = 18'd0;

    if (pad_present) begin
      // 3-button combos 
      if (inp_l && inp_left && inp_down) begin
        note_enable = 1'b1; note_div = 18'd50619; // B3

      end else if (inp_a && inp_right && inp_up) begin
        note_enable = 1'b1; note_div = 18'd17896; // F5

      // 2-button combos
      end else if (inp_l && inp_left) begin
        note_enable = 1'b1; note_div = 18'd47776; // C4
      end else if (inp_l && inp_down) begin
        note_enable = 1'b1; note_div = 18'd45098; // C#4
      end else if (inp_l && inp_up) begin
        note_enable = 1'b1; note_div = 18'd40184; // D#4

      end else if (inp_r && inp_down) begin
        note_enable = 1'b1; note_div = 18'd37920; // E4
      end else if (inp_r && inp_up) begin
        note_enable = 1'b1; note_div = 18'd33784; // F#4
      end else if (inp_r && inp_right) begin
        note_enable = 1'b1; note_div = 18'd31887; // G4

      end else if (inp_y && inp_down) begin
        note_enable = 1'b1; note_div = 18'd30103; // G#4
      end else if (inp_y && inp_up) begin
        note_enable = 1'b1; note_div = 18'd26810; // A#4

      end else if (inp_x && inp_up) begin
        note_enable = 1'b1; note_div = 18'd23888; // C5

      end else if (inp_a && inp_down) begin
        note_enable = 1'b1; note_div = 18'd22550; // C#5
      end else if (inp_a && inp_right) begin
        note_enable = 1'b1; note_div = 18'd18960; // E5
      end else if (inp_a && inp_up) begin
        note_enable = 1'b1; note_div = 18'd20092; // D#5

      // 1-button notes 
      end else if (inp_l) begin
        note_enable = 1'b1; note_div = 18'd42565; // D4
      end else if (inp_r) begin
        note_enable = 1'b1; note_div = 18'd35791; // F4
      end else if (inp_y) begin
        note_enable = 1'b1; note_div = 18'd28408; // A4
      end else if (inp_x) begin
        note_enable = 1'b1; note_div = 18'd25310; // B4
      end else if (inp_a) begin
        note_enable = 1'b1; note_div = 18'd21282; // D5
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tone_counter <= 18'd0;
      tone_ff      <= 1'b0;
    end else begin
      if (note_enable) begin
        if (tone_counter >= note_div) begin
          tone_counter <= 18'd0;
          tone_ff      <= ~tone_ff;
        end else begin
          tone_counter <= tone_counter + 18'd1;
        end
      end else begin
        tone_counter <= 18'd0;
        tone_ff      <= 1'b0;
      end
    end
  end



  // body
  wire body_main  = (pix_x >= 10'd220) && (pix_x <= 10'd420) &&
                    (pix_y >= 10'd190) && (pix_y <= 10'd270);

  wire body_mouth = (in_diamond(pix_x, pix_y, 10'd220, 10'd230, 10'd70));

  wire body_tail  = (pix_x >= 10'd421) && (pix_x <= 10'd450) &&
                    (pix_y >= 10'd205) && (pix_y <= 10'd255);

  wire body_on = body_main | body_mouth | body_tail;

  // blow hole
  wire blow_hole = (pix_x >= 10'd185) && (pix_x <= 10'd194) &&
                   (pix_y >= 10'd225) && (pix_y <= 10'd234);

  // top row holes: L R
  wire hole_l = (pix_x >= 10'd285) && (pix_x <= 10'd296) &&
                (pix_y >= 10'd202) && (pix_y <= 10'd213);

  wire hole_r = (pix_x >= 10'd355) && (pix_x <= 10'd366) &&
                (pix_y >= 10'd202) && (pix_y <= 10'd213);

  // bottom row holes: Y X A
  wire hole_y = (pix_x >= 10'd250) && (pix_x <= 10'd261) &&
                (pix_y >= 10'd247) && (pix_y <= 10'd258);

  wire hole_x = (pix_x >= 10'd320) && (pix_x <= 10'd331) &&
                (pix_y >= 10'd247) && (pix_y <= 10'd258);

  wire hole_a = (pix_x >= 10'd390) && (pix_x <= 10'd401) &&
                (pix_y >= 10'd247) && (pix_y <= 10'd258);

  // modifier boxes on right side
  wire mod_up = (pix_x >= 10'd500) && (pix_x <= 10'd509) &&
                (pix_y >= 10'd180) && (pix_y <= 10'd189);

  wire mod_down = (pix_x >= 10'd500) && (pix_x <= 10'd509) &&
                  (pix_y >= 10'd280) && (pix_y <= 10'd289);

  wire mod_left = (pix_x >= 10'd480) && (pix_x <= 10'd489) &&
                  (pix_y >= 10'd230) && (pix_y <= 10'd239);

  wire mod_right = (pix_x >= 10'd520) && (pix_x <= 10'd529) &&
                   (pix_y >= 10'd230) && (pix_y <= 10'd239);


  localparam [5:0] C_BLACK = 6'b000000;
  localparam [5:0] C_BG    = 6'b000001;
  localparam [5:0] C_BODY  = 6'b111000;
  localparam [5:0] C_HOLE  = 6'b000000;
  localparam [5:0] C_GRAY  = 6'b010101;
  localparam [5:0] C_GREEN = 6'b001100;

  reg [5:0] rgb;

  always @(*) begin
    rgb = C_BLACK;

    if (video_active) begin
      rgb = C_BG;

      if (body_on)    rgb = C_BODY;
      if (blow_hole)  rgb = C_HOLE;

      if (hole_l) rgb = inp_l ? C_GREEN : C_HOLE;
      if (hole_r) rgb = inp_r ? C_GREEN : C_HOLE;
      if (hole_y) rgb = inp_y ? C_GREEN : C_HOLE;
      if (hole_x) rgb = inp_x ? C_GREEN : C_HOLE;
      if (hole_a) rgb = inp_a ? C_GREEN : C_HOLE;

      if (mod_up)    rgb = inp_up    ? C_GREEN : C_GRAY;
      if (mod_down)  rgb = inp_down  ? C_GREEN : C_GRAY;
      if (mod_left)  rgb = inp_left  ? C_GREEN : C_GRAY;
      if (mod_right) rgb = inp_right ? C_GREEN : C_GRAY;
    end
  end

  assign {R, G, B} = rgb;

  wire _unused_ok = &{
    ena,
    uio_in,
    ui_in[7],
    ui_in[3:0],
    inp_b,
    inp_select,
    inp_start
  };

endmodule
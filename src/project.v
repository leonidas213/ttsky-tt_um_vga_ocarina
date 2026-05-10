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

  // ------------------------------------------------------------
  // VGA
  // ------------------------------------------------------------
  wire hsync;
  wire vsync;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;

  reg hsync_r;
  reg vsync_r;

  wire [1:0] R;
  wire [1:0] G;
  wire [1:0] B;

  // RGB and sync are registered by 1 pixel to reduce output timing pressure.
  assign uo_out = {hsync_r, B[0], G[0], R[0], vsync_r, B[1], G[1], R[1]};

  hvsync_generator vga_sync_gen (
      .clk(clk),
      .reset(~rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(video_active),
      .hpos(pix_x),
      .vpos(pix_y)
  );

  // ------------------------------------------------------------
  // Gamepad
  // ------------------------------------------------------------
  wire inp_y, inp_select, inp_start;
  wire inp_up, inp_down;
  wire inp_a, inp_x, inp_l, inp_r;
  wire pad_present;

  gamepad_pmod_single driver (
      .rst_n(rst_n),
      .clk(clk),
      .pmod_data(ui_in[6]),
      .pmod_clk(ui_in[5]),
      .pmod_latch(ui_in[4]),
      .b(),
      .y(inp_y),
      .select(inp_select),
      .start(inp_start),
      .up(inp_up),
      .down(inp_down),
      .left(),
      .right(),
      .a(inp_a),
      .x(inp_x),
      .l(inp_l),
      .r(inp_r),
      .is_present(pad_present)
  );

  // Button ids: 1=A, 2=X, 3=Y, 4=L, 5=R
  function row_for_btn;
    input [2:0] id;
    input       row_a;
    input       row_x;
    input       row_y;
    input       row_r;
    input       row_l;
    begin
      case (id)
        3'd1: row_for_btn = row_a;
        3'd2: row_for_btn = row_x;
        3'd3: row_for_btn = row_y;
        3'd5: row_for_btn = row_r;
        3'd4: row_for_btn = row_l;
        default: row_for_btn = 1'b0;
      endcase
    end
  endfunction

  // ------------------------------------------------------------
  // Audio note generation
  // ------------------------------------------------------------
  reg  [15:0] note_div;
  reg  [2:0]  note_vis;
  reg  [15:0] tone_counter;
  reg         tone_ff;

  wire note_enable = (note_vis != 3'd0);
  wire audio = note_enable ? tone_ff : 1'b0;

  assign uio_out = {audio, 7'b0};
  assign uio_oe  = 8'h80;

  always @(*) begin
    note_vis = 3'd0;
    note_div = 16'd0;

    if (pad_present) begin
      if (inp_a) begin
        note_vis = 3'd1;
        if (inp_down)
          note_div = 16'd22550; // C#5
        else if (inp_up)
          note_div = 16'd20092; // D#5
        else
          note_div = 16'd21282; // D5

      end else if (inp_y) begin
        note_vis = 3'd3;
        if (inp_down)
          note_div = 16'd30103; // G#4
        else if (inp_up)
          note_div = 16'd26810; // A#4
        else
          note_div = 16'd28408; // A4

      end else if (inp_x) begin
        note_vis = 3'd2;
        if (inp_up)
          note_div = 16'd23888; // C5
        else
          note_div = 16'd25310; // B4

      end else if (inp_l) begin
        note_vis = 3'd4;
        if (inp_down)
          note_div = 16'd45098; // C#4
        else if (inp_up)
          note_div = 16'd40184; // D#4
        else
          note_div = 16'd42565; // D4

      end else if (inp_r) begin
        note_vis = 3'd5;
        if (inp_down)
          note_div = 16'd37920; // E4
        else if (inp_up)
          note_div = 16'd33784; // F#4
        else
          note_div = 16'd35791; // F4
      end
    end
  end

  // Down-counter version:
  // cheaper than tone_counter >= note_div because it avoids a variable 16-bit magnitude compare.
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tone_counter <= 16'd0;
      tone_ff      <= 1'b0;
    end else begin
      if (note_enable) begin
        if (tone_counter == 16'd0) begin
          tone_counter <= note_div;
          tone_ff      <= ~tone_ff;
        end else begin
          tone_counter <= tone_counter - 16'd1;
        end
      end else begin
        tone_counter <= 16'd0;
        tone_ff      <= 1'b0;
      end
    end
  end

  // START cycles songs. SELECT clears history.
  reg        note_enable_d;
  reg [2:0]  note_vis_d;
  reg        inp_start_d;
  reg        inp_select_d;

  reg [2:0] hist0;
  reg [2:0] hist1;
  reg [2:0] hist2;
  reg [2:0] hist3;
  reg [2:0] hist4;
  reg [2:0] hist5;
  reg [2:0] hist_count;

  reg [1:0] song_id; // 0=Zelda, 1=Time, 2=Epona, 3=empty

  wire note_fire   = note_enable && ((!note_enable_d) || (note_vis != note_vis_d));
  wire start_fire  = pad_present && inp_start  && !inp_start_d;
  wire select_fire = pad_present && inp_select && !inp_select_d;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      note_enable_d <= 1'b0;
      note_vis_d    <= 3'd0;
      inp_start_d   <= 1'b0;
      inp_select_d  <= 1'b0;

      hist0 <= 3'd0;
      hist1 <= 3'd0;
      hist2 <= 3'd0;
      hist3 <= 3'd0;
      hist4 <= 3'd0;
      hist5 <= 3'd0;
      hist_count <= 3'd0;

      song_id <= 2'd0;
    end else begin
      note_enable_d <= note_enable;
      note_vis_d    <= note_vis;
      inp_start_d   <= inp_start;
      inp_select_d  <= inp_select;

      if (start_fire) begin
        if (song_id == 2'd3)
          song_id <= 2'd0;
        else
          song_id <= song_id + 2'd1;

        hist0 <= 3'd0;
        hist1 <= 3'd0;
        hist2 <= 3'd0;
        hist3 <= 3'd0;
        hist4 <= 3'd0;
        hist5 <= 3'd0;
        hist_count <= 3'd0;
      end else if (select_fire) begin
        hist0 <= 3'd0;
        hist1 <= 3'd0;
        hist2 <= 3'd0;
        hist3 <= 3'd0;
        hist4 <= 3'd0;
        hist5 <= 3'd0;
        hist_count <= 3'd0;
      end else if (note_fire) begin
        case (hist_count)
          3'd0: begin hist0 <= note_vis; hist_count <= 3'd1; end
          3'd1: begin hist1 <= note_vis; hist_count <= 3'd2; end
          3'd2: begin hist2 <= note_vis; hist_count <= 3'd3; end
          3'd3: begin hist3 <= note_vis; hist_count <= 3'd4; end
          3'd4: begin hist4 <= note_vis; hist_count <= 3'd5; end
          3'd5: begin hist5 <= note_vis; hist_count <= 3'd6; end
          default: begin
            hist0 <= hist1;
            hist1 <= hist2;
            hist2 <= hist3;
            hist3 <= hist4;
            hist4 <= hist5;
            hist5 <= note_vis;
            hist_count <= 3'd6;
          end
        endcase
      end
    end
  end

  // Slot 0: Zelda's Lullaby = X A Y X A Y
  // Slot 1: Song of Time     = Y L R Y L R
  // Slot 2: Epona's Song     = A X Y A X Y
  // Slot 3: Empty             = no guide notes
  reg [2:0] guide0;
  reg [2:0] guide1;
  reg [2:0] guide2;
  reg [2:0] guide3;
  reg [2:0] guide4;
  reg [2:0] guide5;

  always @(*) begin
    case (song_id)
      2'd1: begin
        guide0 = 3'd3; guide1 = 3'd4; guide2 = 3'd5;
        guide3 = 3'd3; guide4 = 3'd4; guide5 = 3'd5;
      end
      2'd2: begin
        guide0 = 3'd1; guide1 = 3'd2; guide2 = 3'd3;
        guide3 = 3'd1; guide4 = 3'd2; guide5 = 3'd3;
      end
      2'd3: begin
        guide0 = 3'd0; guide1 = 3'd0; guide2 = 3'd0;
        guide3 = 3'd0; guide4 = 3'd0; guide5 = 3'd0;
      end
      default: begin
        guide0 = 3'd2; guide1 = 3'd1; guide2 = 3'd3;
        guide3 = 3'd2; guide4 = 3'd1; guide5 = 3'd3;
      end
    endcase
  end

  // Drawing
  wire body_outline = ((pix_x >= 10'd238) && (pix_x <= 10'd420) &&
                       (pix_y >= 10'd184) && (pix_y <= 10'd196)) ||
                      ((pix_x >= 10'd218) && (pix_x <= 10'd452) &&
                       (pix_y >= 10'd197) && (pix_y <= 10'd213)) ||
                      ((pix_x >= 10'd218) && (pix_x <= 10'd472) &&
                       (pix_y >= 10'd214) && (pix_y <= 10'd246)) ||
                      ((pix_x >= 10'd218) && (pix_x <= 10'd452) &&
                       (pix_y >= 10'd247) && (pix_y <= 10'd263)) ||
                      ((pix_x >= 10'd238) && (pix_x <= 10'd420) &&
                       (pix_y >= 10'd264) && (pix_y <= 10'd276)) ||
                      ((pix_x >= 10'd278) && (pix_x <= 10'd340) &&
                       (pix_y >= 10'd124) && (pix_y <= 10'd188));

  wire body_on = ((pix_x >= 10'd244) && (pix_x <= 10'd414) &&
                  (pix_y >= 10'd190) && (pix_y <= 10'd202)) ||
                 ((pix_x >= 10'd225) && (pix_x <= 10'd445) &&
                  (pix_y >= 10'd203) && (pix_y <= 10'd219)) ||
                 ((pix_x >= 10'd225) && (pix_x <= 10'd462) &&
                  (pix_y >= 10'd220) && (pix_y <= 10'd240)) ||
                 ((pix_x >= 10'd225) && (pix_x <= 10'd445) &&
                  (pix_y >= 10'd241) && (pix_y <= 10'd257)) ||
                 ((pix_x >= 10'd244) && (pix_x <= 10'd414) &&
                  (pix_y >= 10'd258) && (pix_y <= 10'd270)) ||
                 ((pix_x >= 10'd284) && (pix_x <= 10'd334) &&
                  (pix_y >= 10'd130) && (pix_y <= 10'd189));

  wire body_highlight = (((pix_x >= 10'd250) && (pix_x <= 10'd390) &&
                          (pix_y >= 10'd195) && (pix_y <= 10'd198)) ||
                         ((pix_x >= 10'd230) && (pix_x <= 10'd285) &&
                          (pix_y >= 10'd230) && (pix_y <= 10'd232))) ||
                        ((pix_x >= 10'd325) && (pix_x <= 10'd330) &&
                         (pix_y >= 10'd130) && (pix_y <= 10'd179));

  wire body_shadow = ((pix_x >= 10'd244) && (pix_x <= 10'd414) &&
                      (pix_y >= 10'd265) && (pix_y <= 10'd270)) ||
                     ((pix_x >= 10'd415) && (pix_x <= 10'd445) &&
                      (pix_y >= 10'd250) && (pix_y <= 10'd257)) ||
                     ((pix_x >= 10'd446) && (pix_x <= 10'd462) &&
                      (pix_y >= 10'd235) && (pix_y <= 10'd240));

  wire blow_hole = ((pix_x >= 10'd294) && (pix_x <= 10'd314) &&
                    (pix_y >= 10'd130) && (pix_y <= 10'd149));

  wire hole_l_ring = (((pix_x >= 10'd255) && (pix_x <= 10'd265) && (pix_y >= 10'd202) && (pix_y <= 10'd222)) ||
                      ((pix_x >= 10'd251) && (pix_x <= 10'd269) && (pix_y >= 10'd206) && (pix_y <= 10'd218)));
  wire hole_r_ring = (((pix_x >= 10'd375) && (pix_x <= 10'd385) && (pix_y >= 10'd202) && (pix_y <= 10'd222)) ||
                      ((pix_x >= 10'd371) && (pix_x <= 10'd389) && (pix_y >= 10'd206) && (pix_y <= 10'd218)));
  wire hole_y_ring = (((pix_x >= 10'd280) && (pix_x <= 10'd290) && (pix_y >= 10'd230) && (pix_y <= 10'd250)) ||
                      ((pix_x >= 10'd276) && (pix_x <= 10'd294) && (pix_y >= 10'd234) && (pix_y <= 10'd246)));
  wire hole_x_ring = (((pix_x >= 10'd320) && (pix_x <= 10'd330) && (pix_y >= 10'd240) && (pix_y <= 10'd260)) ||
                      ((pix_x >= 10'd316) && (pix_x <= 10'd334) && (pix_y >= 10'd244) && (pix_y <= 10'd256)));
  wire hole_a_ring = (((pix_x >= 10'd420) && (pix_x <= 10'd430) && (pix_y >= 10'd220) && (pix_y <= 10'd240)) ||
                      ((pix_x >= 10'd416) && (pix_x <= 10'd434) && (pix_y >= 10'd224) && (pix_y <= 10'd236)));

  wire hole_l = (pix_x >= 10'd256) && (pix_x <= 10'd264) &&
                (pix_y >= 10'd208) && (pix_y <= 10'd216);
  wire hole_r = (pix_x >= 10'd376) && (pix_x <= 10'd384) &&
                (pix_y >= 10'd208) && (pix_y <= 10'd216);
  wire hole_y = (pix_x >= 10'd281) && (pix_x <= 10'd289) &&
                (pix_y >= 10'd236) && (pix_y <= 10'd244);
  wire hole_x = (pix_x >= 10'd321) && (pix_x <= 10'd329) &&
                (pix_y >= 10'd246) && (pix_y <= 10'd254);
  wire hole_a = (pix_x >= 10'd421) && (pix_x <= 10'd429) &&
                (pix_y >= 10'd226) && (pix_y <= 10'd234);

  wire hole_ring_on = hole_l_ring | hole_r_ring | hole_y_ring | hole_x_ring | hole_a_ring;

  wire mod_up = (pix_x >= 10'd525) && (pix_x <= 10'd534) &&
                (pix_y >= 10'd165) && (pix_y <= 10'd174);

  wire mod_down = (pix_x >= 10'd525) && (pix_x <= 10'd534) &&
                  (pix_y >= 10'd255) && (pix_y <= 10'd264);

  // Staff area and rows.
  wire staff_x = (pix_x >= 10'd70) && (pix_x <= 10'd570);
  wire staff_line0 = staff_x && (pix_y >= 10'd310) && (pix_y <= 10'd313);
  wire staff_line1 = staff_x && (pix_y >= 10'd330) && (pix_y <= 10'd333);
  wire staff_line2 = staff_x && (pix_y >= 10'd350) && (pix_y <= 10'd353);
  wire staff_line3 = staff_x && (pix_y >= 10'd370) && (pix_y <= 10'd373);
  wire staff_line4 = staff_x && (pix_y >= 10'd390) && (pix_y <= 10'd393);
  wire staff_on = staff_line0 | staff_line1 | staff_line2 | staff_line3 | staff_line4;

  wire staff_key_on =
      ((pix_x >= 10'd94) && (pix_x <= 10'd99) &&
       (pix_y >= 10'd306) && (pix_y <= 10'd394)) ||
      ((pix_x >= 10'd84) && (pix_x <= 10'd108) &&
       (pix_y >= 10'd346) && (pix_y <= 10'd352)) ||
      ((pix_x >= 10'd84) && (pix_x <= 10'd90) &&
       (pix_y >= 10'd352) && (pix_y <= 10'd372)) ||
      ((pix_x >= 10'd82) && (pix_x <= 10'd100) &&
       (pix_y >= 10'd388) && (pix_y <= 10'd394));

  wire row_a = (pix_y >= 10'd305) && (pix_y <= 10'd317);
  wire row_x = (pix_y >= 10'd325) && (pix_y <= 10'd337);
  wire row_y = (pix_y >= 10'd345) && (pix_y <= 10'd357);
  wire row_r = (pix_y >= 10'd365) && (pix_y <= 10'd377);
  wire row_l = (pix_y >= 10'd385) && (pix_y <= 10'd397);

  wire slot0_x = (pix_x >= 10'd169) && (pix_x <= 10'd181);
  wire slot1_x = (pix_x >= 10'd219) && (pix_x <= 10'd231);
  wire slot2_x = (pix_x >= 10'd269) && (pix_x <= 10'd281);
  wire slot3_x = (pix_x >= 10'd319) && (pix_x <= 10'd331);
  wire slot4_x = (pix_x >= 10'd369) && (pix_x <= 10'd381);
  wire slot5_x = (pix_x >= 10'd419) && (pix_x <= 10'd431);

  wire slot0_x_n = (pix_x >= 10'd172) && (pix_x <= 10'd178);
  wire slot1_x_n = (pix_x >= 10'd222) && (pix_x <= 10'd228);
  wire slot2_x_n = (pix_x >= 10'd272) && (pix_x <= 10'd278);
  wire slot3_x_n = (pix_x >= 10'd322) && (pix_x <= 10'd328);
  wire slot4_x_n = (pix_x >= 10'd372) && (pix_x <= 10'd378);
  wire slot5_x_n = (pix_x >= 10'd422) && (pix_x <= 10'd428);
  wire slot_x_narrow = slot0_x_n | slot1_x_n | slot2_x_n |
                       slot3_x_n | slot4_x_n | slot5_x_n;

  reg [2:0] guide_pix;
  reg [2:0] hist_pix;

  always @(*) begin
    guide_pix = 3'd0;
    hist_pix  = 3'd0;

    if (slot0_x) begin
      guide_pix = guide0;
      hist_pix  = hist0;
    end else if (slot1_x) begin
      guide_pix = guide1;
      hist_pix  = hist1;
    end else if (slot2_x) begin
      guide_pix = guide2;
      hist_pix  = hist2;
    end else if (slot3_x) begin
      guide_pix = guide3;
      hist_pix  = hist3;
    end else if (slot4_x) begin
      guide_pix = guide4;
      hist_pix  = hist4;
    end else if (slot5_x) begin
      guide_pix = guide5;
      hist_pix  = hist5;
    end
  end

  wire target_note_on  = (guide_pix != 3'd0) &&
                         slot_x_narrow &&
                         row_for_btn(guide_pix, row_a, row_x, row_y, row_r, row_l);

  wire history_note_on = (hist_pix != 3'd0) &&
                         slot_x_narrow &&
                         row_for_btn(hist_pix, row_a, row_x, row_y, row_r, row_l);

  // ------------------------------------------------------------
  // Colors
  // ------------------------------------------------------------
  localparam [5:0] C_BLACK = 6'b000000;
  localparam [5:0] C_BG    = 6'b011001;
  localparam [5:0] C_BODY  = 6'b010111;
  localparam [5:0] C_HOLE  = 6'b000000;
  localparam [5:0] C_GRAY  = 6'b010101;
  localparam [5:0] C_GREEN = 6'b001100;
  localparam [5:0] C_RED   = 6'b110000;
  localparam [5:0] C_WHITE = 6'b111111;
  localparam [5:0] C_RIM   = 6'b000010;
  localparam [5:0] C_NOTE  = 6'b111000;

  reg [5:0] rgb_next;
  reg [5:0] rgb;

  always @(*) begin
    rgb_next = C_BLACK;

    if (video_active) begin
      rgb_next = C_BG;

      if (staff_on)        rgb_next = C_RED;
      if (staff_key_on)    rgb_next = C_NOTE;
      if (target_note_on)  rgb_next = C_GRAY;
      if (history_note_on) rgb_next = C_NOTE;

      if (body_outline)   rgb_next = C_HOLE;
      if (body_on)        rgb_next = C_BODY;
      if (body_shadow)    rgb_next = C_RIM;
      if (body_highlight) rgb_next = C_WHITE;
      if (blow_hole)      rgb_next = C_HOLE;

      if (hole_ring_on) rgb_next = C_RIM;
      if (hole_l) rgb_next = inp_l ? C_GREEN : C_HOLE;
      if (hole_r) rgb_next = inp_r ? C_GREEN : C_HOLE;
      if (hole_y) rgb_next = inp_y ? C_GREEN : C_HOLE;
      if (hole_x) rgb_next = inp_x ? C_GREEN : C_HOLE;
      if (hole_a) rgb_next = inp_a ? C_GREEN : C_HOLE;

      if (mod_up)   rgb_next = inp_up   ? C_GREEN : C_GRAY;
      if (mod_down) rgb_next = inp_down ? C_GREEN : C_GRAY;
    end
  end

  // Register video output to reduce timing violations.
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rgb     <= 6'b000000;
      hsync_r <= 1'b0;
      vsync_r <= 1'b0;
    end else begin
      rgb     <= rgb_next;
      hsync_r <= hsync;
      vsync_r <= vsync;
    end
  end

  assign {R, G, B} = rgb;

  wire _unused_ok = &{
    ena,
    uio_in,
    ui_in[7],
    ui_in[3:0],
    inp_select,
    inp_start
  };

endmodule

`default_nettype wire

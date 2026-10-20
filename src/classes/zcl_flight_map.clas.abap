CLASS zcl_flight_map DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_service_extension.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    " one line on the map = one airport pair, all flights summed up
    TYPES: BEGIN OF ty_route,
             origin      TYPE zairport-airport_id,
             dest        TYPE zairport-airport_id,
             flights     TYPE i,
             total_delay TYPE i,
             worst       TYPE i,   " 0 = low ... 3 = critical
           END OF ty_route.

    " builds the whole HTML page (used by the web call AND by F9)
    METHODS build_page RETURNING VALUE(html) TYPE string.

    " turn lat/long into pixel positions on a 1000 x 800 canvas
    METHODS px IMPORTING lon TYPE zairport-longitude RETURNING VALUE(x) TYPE i.
    METHODS py IMPORTING lat TYPE zairport-latitude  RETURNING VALUE(y) TYPE i.
ENDCLASS.

CLASS zcl_flight_map IMPLEMENTATION.

  METHOD px.
    " map covers longitude -12 to 32
    x = ( lon + 12 ) * 1000 / 44.
  ENDMETHOD.

  METHOD py.
    " map covers latitude 34 to 58
    y = ( 58 - lat ) * 800 / 24.
  ENDMETHOD.

  METHOD if_http_service_extension~handle_request.
    response->set_header_field( i_name = 'Content-Type' i_value = 'text/html; charset=utf-8' ).
    response->set_text( build_page( ) ).
  ENDMETHOD.

  METHOD if_oo_adt_classrun~main.
    " F9 prints the page into the console, we copy it into a .html file
    out->write( build_page( ) ).
  ENDMETHOD.

  METHOD build_page.

    DATA routes TYPE SORTED TABLE OF ty_route WITH UNIQUE KEY origin dest.
    DATA a    TYPE zairport-airport_id.
    DATA b    TYPE zairport-airport_id.
    DATA rank TYPE i.

    " 1) read both tables
    SELECT airport_id, city, latitude, longitude
      FROM zairport INTO TABLE @DATA(airports).
    SELECT flight_id, origin_airport, destination_airport, delay_minutes, risk_level
      FROM zflightleg INTO TABLE @DATA(flights).

    " 2) group the flights per airport pair (FRA-BER and BER-FRA = same line)
    LOOP AT flights ASSIGNING FIELD-SYMBOL(<f>).
      IF <f>-origin_airport < <f>-destination_airport.
        a = <f>-origin_airport.
        b = <f>-destination_airport.
      ELSE.
        a = <f>-destination_airport.
        b = <f>-origin_airport.
      ENDIF.

      CASE <f>-risk_level.
        WHEN 'Medium'.   rank = 1.
        WHEN 'High'.     rank = 2.
        WHEN 'Critical'. rank = 3.
        WHEN OTHERS.     rank = 0.
      ENDCASE.

      ASSIGN routes[ origin = a dest = b ] TO FIELD-SYMBOL(<r>).
      IF sy-subrc <> 0.
        INSERT VALUE #( origin = a dest = b ) INTO TABLE routes ASSIGNING <r>.
      ENDIF.
      <r>-flights     = <r>-flights + 1.
      <r>-total_delay = <r>-total_delay + <f>-delay_minutes.
      <r>-worst       = nmax( val1 = <r>-worst val2 = rank ).
    ENDLOOP.

    " 3) numbers for the cards at the top
    DATA(total)     = lines( flights ).
    DATA(sum_delay) = REDUCE i( INIT s = 0 FOR fl IN flights NEXT s = s + fl-delay_minutes ).
    DATA(critical)  = REDUCE i( INIT c = 0 FOR fl IN flights
                                WHERE ( risk_level = 'Critical' ) NEXT c = c + 1 ).
    DATA(avg_delay) = COND i( WHEN total > 0 THEN sum_delay / total ).

    " 4) build the SVG map as one long string
    DATA svg TYPE string.
    DATA g   TYPE i.
    DATA gx  TYPE i.
    DATA gy  TYPE i.

    svg = |<svg viewBox="0 0 1000 800" style="width:100%;max-width:1100px;display:block;margin:0 auto">| &&
          |<defs><filter id="glow"><feGaussianBlur stdDeviation="4"/></filter></defs>| &&
          |<rect width="1000" height="800" rx="16" fill="#0f1b33"/>|.

    " background grid so it feels like a radar screen
    DO 5 TIMES.
      g  = -10 + ( sy-index - 1 ) * 10.
      gx = ( g + 12 ) * 1000 / 44.
      svg = svg && |<line x1="{ gx }" y1="0" x2="{ gx }" y2="800" stroke="#1e2d4d"/>|.
    ENDDO.
    DO 2 TIMES.
      g  = 30 + sy-index * 10.
      gy = ( 58 - g ) * 800 / 24.
      svg = svg && |<line x1="0" y1="{ gy }" x2="1000" y2="{ gy }" stroke="#1e2d4d"/>|.
    ENDDO.

    " the arcs: curved line per route, colour = worst risk, thickness = flight count
    LOOP AT routes ASSIGNING FIELD-SYMBOL(<rt>).
      ASSIGN airports[ airport_id = <rt>-origin ] TO FIELD-SYMBOL(<pa>).
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      ASSIGN airports[ airport_id = <rt>-dest ] TO FIELD-SYMBOL(<pb>).
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      DATA(x1) = px( <pa>-longitude ).
      DATA(y1) = py( <pa>-latitude ).
      DATA(x2) = px( <pb>-longitude ).
      DATA(y2) = py( <pb>-latitude ).
      DATA(mx) = ( x1 + x2 ) / 2.
      DATA(mid_y) = ( y1 + y2 ) / 2.
      DATA(dist) = sqrt( ( x2 - x1 ) * ( x2 - x1 ) + ( y2 - y1 ) * ( y2 - y1 ) ).
      " pull the middle of the line upwards so it looks like a flight arc
      DATA(cy) = mid_y - CONV i( dist / 5 ).

      DATA(color) = SWITCH string( <rt>-worst
                      WHEN 3 THEN '#ef4444'
                      WHEN 2 THEN '#f97316'
                      WHEN 1 THEN '#facc15'
                      ELSE '#22c55e' ).
      DATA(width) = nmin( val1 = 6 val2 = 1 + <rt>-flights / 2 ).
      DATA(avg)   = <rt>-total_delay / <rt>-flights.

      svg = svg &&
        |<path d="M{ x1 } { y1 } Q{ mx } { cy } { x2 } { y2 }" fill="none" | &&
        |stroke="{ color }" stroke-width="{ width }" stroke-opacity="0.75">| &&
        |<title>{ <rt>-origin } - { <rt>-dest }: { <rt>-flights } flights, avg delay { avg } min</title></path>|.
    ENDLOOP.

    " the airports: glowing dot + code
    LOOP AT airports ASSIGNING FIELD-SYMBOL(<ap>).
      DATA(ax) = px( <ap>-longitude ).
      DATA(ay) = py( <ap>-latitude ).
      svg = svg &&
        |<circle cx="{ ax }" cy="{ ay }" r="12" fill="#38bdf8" filter="url(#glow)"/>| &&
        |<circle cx="{ ax }" cy="{ ay }" r="6" fill="#e0f2fe"><title>{ <ap>-city }</title></circle>| &&
        |<text x="{ ax + 10 }" y="{ ay - 12 }" fill="#e5e7eb" font-size="16" font-weight="bold">{ <ap>-airport_id }</text>|.
    ENDLOOP.

    " legend
    svg = svg &&
      |<text x="30" y="40" fill="#e5e7eb" font-size="16" font-weight="bold">Route risk (worst flight)</text>| &&
      |<rect x="30" y="52" width="18" height="6" fill="#22c55e"/><text x="54" y="60" fill="#cbd5e1" font-size="13">Low</text>| &&
      |<rect x="100" y="52" width="18" height="6" fill="#facc15"/><text x="124" y="60" fill="#cbd5e1" font-size="13">Medium</text>| &&
      |<rect x="190" y="52" width="18" height="6" fill="#f97316"/><text x="214" y="60" fill="#cbd5e1" font-size="13">High</text>| &&
      |<rect x="260" y="52" width="18" height="6" fill="#ef4444"/><text x="284" y="60" fill="#cbd5e1" font-size="13">Critical</text>| &&
      |</svg>|.

    " 5) wrap in a small HTML page with KPI cards
    html =
      |<!DOCTYPE html><html><head><meta charset="utf-8"><title>Flight Network Monitor</title></head>| &&
      |<body style="margin:0;padding:24px;background:#0b1220;color:#e5e7eb;font-family:Segoe UI,Arial,sans-serif">| &&
      |<h1 style="text-align:center;margin:0 0 4px">Flight Delay Risk and Network Monitor</h1>| &&
      |<p style="text-align:center;color:#94a3b8;margin:0 0 20px">Generated by ABAP Cloud from tables ZAIRPORT and ZFLIGHTLEG</p>| &&
      |<div style="display:flex;gap:16px;justify-content:center;margin-bottom:20px">| &&
      |<div style="background:#13213f;padding:12px 28px;border-radius:12px;text-align:center">| &&
      |<div style="font-size:28px;font-weight:bold">{ total }</div><div style="color:#94a3b8">Flights</div></div>| &&
      |<div style="background:#13213f;padding:12px 28px;border-radius:12px;text-align:center">| &&
      |<div style="font-size:28px;font-weight:bold">{ avg_delay } min</div><div style="color:#94a3b8">Average delay</div></div>| &&
      |<div style="background:#13213f;padding:12px 28px;border-radius:12px;text-align:center">| &&
      |<div style="font-size:28px;font-weight:bold;color:#ef4444">{ critical }</div><div style="color:#94a3b8">Critical flights</div></div>| &&
      |</div>| && svg && |</body></html>|.

  ENDMETHOD.

ENDCLASS.

CLASS zcl_flightleg_generator DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
ENDCLASS.

CLASS zcl_flightleg_generator IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    DATA flights TYPE STANDARD TABLE OF zflightleg WITH EMPTY KEY.
    DATA codes   TYPE STANDARD TABLE OF zairport-airport_id WITH EMPTY KEY.
    DATA delay   TYPE i.
    DATA risk    TYPE c LENGTH 10.
    DATA ts      TYPE timestampl.

    GET TIME STAMP FIELD ts.
    DATA(user) = cl_abap_context_info=>get_user_technical_name( ).
    DATA(now)  = utclong_current( ).

    " take the airport codes from the master table we filled before
    SELECT airport_id FROM zairport INTO TABLE @codes.

    " fixed seed so the random data is the same every run
    DATA(rnd) = cl_abap_random_int=>create( seed = 42 min = 1 max = 100 ).

    DELETE FROM zflightleg.

    DO 40 TIMES.
      DATA(n) = sy-index.

      " pick two different airports
      DATA(o) = rnd->get_next( ) MOD lines( codes ) + 1.
      DATA(d) = rnd->get_next( ) MOD lines( codes ) + 1.
      IF d = o.
        d = d MOD lines( codes ) + 1.
      ENDIF.

      " random delay: 40% on time, the rest from small to really bad
      DATA(roll) = rnd->get_next( ).
      IF roll <= 40.
        delay = 0.
      ELSEIF roll <= 65.
        delay = 5 + roll MOD 10.
      ELSEIF roll <= 80.
        delay = 15 + roll MOD 45.
      ELSEIF roll <= 92.
        delay = 60 + roll MOD 120.
      ELSE.
        delay = 180 + roll MOD 120.
      ENDIF.

      " planned times: spread over today and yesterday
      DATA(dep) = utclong_add( val = now days = -1 minutes = n * 37 ).
      DATA(arr) = utclong_add( val = dep hours = 2 minutes = roll ).

      " first 32 flights already left, the rest are still planned
      DATA(departed) = xsdbool( n <= 32 ).
      IF departed = abap_false.
        delay = 0.
      ENDIF.

      " same risk rule as in the RAP determination
      IF delay < 15.
        risk = 'Low'.
      ELSEIF delay < 60.
        risk = 'Medium'.
      ELSEIF delay < 180.
        risk = 'High'.
      ELSE.
        risk = 'Critical'.
      ENDIF.

      APPEND VALUE #(
        flight_id             = |LH{ 1000 + n }|
        origin_airport        = codes[ o ]
        destination_airport   = codes[ d ]
        scheduled_departure   = dep
        scheduled_arrival     = arr
        actual_departure      = COND #( WHEN departed = abap_true THEN utclong_add( val = dep minutes = delay ) )
        actual_arrival        = COND #( WHEN departed = abap_true THEN utclong_add( val = arr minutes = delay ) )
        delay_minutes         = delay
        risk_level            = risk
        status                = COND #( WHEN departed = abap_true THEN 'DEPARTED' ELSE 'SCHEDULED' )
        local_created_by      = user
        local_created_at      = ts
        local_last_changed_by = user
        local_last_changed_at = ts
        last_changed_at       = ts ) TO flights.
    ENDDO.

    INSERT zflightleg FROM TABLE @flights.
    out->write( |{ sy-dbcnt } flights inserted| ).

  ENDMETHOD.

ENDCLASS.

CLASS zcl_airport_generator DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
ENDCLASS.

CLASS zcl_airport_generator IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    " table for the airports we want to insert
    DATA airports TYPE STANDARD TABLE OF zairport WITH EMPTY KEY.
    DATA ts       TYPE timestampl.

    " current time + technical user for the admin fields
    GET TIME STAMP FIELD ts.
    DATA(user) = cl_abap_context_info=>get_user_technical_name( ).

    " wipe old data so we can run this as many times as we want
    DELETE FROM zairport.

    " 8 airports with real coordinates (needed later for the map)
    airports = VALUE #(
      ( airport_id = 'TIA' city = 'Tirana'    country = 'Albania'        latitude = '41.414700' longitude = '19.720600' )
      ( airport_id = 'FRA' city = 'Frankfurt' country = 'Germany'        latitude = '50.037900' longitude = '8.562200' )
      ( airport_id = 'MUC' city = 'Munich'    country = 'Germany'        latitude = '48.353800' longitude = '11.786100' )
      ( airport_id = 'BER' city = 'Berlin'    country = 'Germany'        latitude = '52.366700' longitude = '13.503300' )
      ( airport_id = 'VIE' city = 'Vienna'    country = 'Austria'        latitude = '48.110300' longitude = '16.569700' )
      ( airport_id = 'ZRH' city = 'Zurich'    country = 'Switzerland'    latitude = '47.464700' longitude = '8.549200' )
      ( airport_id = 'LHR' city = 'London'    country = 'United Kingdom' latitude = '51.470000' longitude = '-0.454300' )
      ( airport_id = 'IST' city = 'Istanbul'  country = 'Turkey'         latitude = '41.275300' longitude = '28.751900' )
    ).

    " fill the admin fields on every row (RAP expects them)
    LOOP AT airports ASSIGNING FIELD-SYMBOL(<airport>).
      <airport>-local_created_by      = user.
      <airport>-local_created_at      = ts.
      <airport>-local_last_changed_by = user.
      <airport>-local_last_changed_at = ts.
      <airport>-last_changed_at       = ts.
    ENDLOOP.

    INSERT zairport FROM TABLE @airports.

    out->write( |{ sy-dbcnt } airports inserted| ).

  ENDMETHOD.

ENDCLASS.

CLASS lhc_flightleg DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR ZrFlightleg RESULT result.

    METHODS setDefaults    FOR DETERMINE ON MODIFY IMPORTING keys FOR ZrFlightleg~setDefaults.
    METHODS calculateDelay FOR DETERMINE ON MODIFY IMPORTING keys FOR ZrFlightleg~calculateDelay.
    METHODS calculateRisk  FOR DETERMINE ON MODIFY IMPORTING keys FOR ZrFlightleg~calculateRisk.
    METHODS checkDates     FOR VALIDATE ON SAVE IMPORTING keys FOR ZrFlightleg~checkDates.
    METHODS checkAirports  FOR VALIDATE ON SAVE IMPORTING keys FOR ZrFlightleg~checkAirports.
    METHODS escalate FOR MODIFY IMPORTING keys FOR ACTION ZrFlightleg~escalate RESULT result.
    METHODS resolve  FOR MODIFY IMPORTING keys FOR ACTION ZrFlightleg~resolve  RESULT result.
ENDCLASS.

CLASS lhc_flightleg IMPLEMENTATION.

  METHOD get_global_authorizations.
    " no auth checks for this demo, everyone can do everything
  ENDMETHOD.

  METHOD setDefaults.
    " every new flight starts as SCHEDULED
    READ ENTITIES OF zr_flightleg IN LOCAL MODE
      ENTITY ZrFlightleg FIELDS ( Status )
      WITH CORRESPONDING #( keys )
      RESULT DATA(flights).

    " only touch the ones that don't have a status yet
    DELETE flights WHERE Status IS NOT INITIAL.
    CHECK flights IS NOT INITIAL.

    MODIFY ENTITIES OF zr_flightleg IN LOCAL MODE
      ENTITY ZrFlightleg UPDATE FIELDS ( Status )
      WITH VALUE #( FOR f IN flights ( %tky = f-%tky Status = 'SCHEDULED' ) ).
  ENDMETHOD.

  METHOD calculateDelay.
    READ ENTITIES OF zr_flightleg IN LOCAL MODE
      ENTITY ZrFlightleg FIELDS ( ScheduledDeparture ActualDeparture )
      WITH CORRESPONDING #( keys )
      RESULT DATA(flights).

    DATA updates TYPE TABLE FOR UPDATE zr_flightleg.

    LOOP AT flights INTO DATA(f).
      DATA(delay) = 0.
      " no actual departure yet = no delay known
      IF f-ActualDeparture IS NOT INITIAL.
        " utclong_diff gives seconds, divide by 60 for minutes
        delay = nmax( val1 = 0
                      val2 = CONV i( utclong_diff( high = f-ActualDeparture
                                                   low  = f-ScheduledDeparture ) / 60 ) ).
      ENDIF.
      APPEND VALUE #( %tky = f-%tky DelayMinutes = delay ) TO updates.
    ENDLOOP.

    MODIFY ENTITIES OF zr_flightleg IN LOCAL MODE
      ENTITY ZrFlightleg UPDATE FIELDS ( DelayMinutes )
      WITH updates.
  ENDMETHOD.

  METHOD calculateRisk.
    READ ENTITIES OF zr_flightleg IN LOCAL MODE
      ENTITY ZrFlightleg FIELDS ( DelayMinutes )
      WITH CORRESPONDING #( keys )
      RESULT DATA(flights).

    DATA updates TYPE TABLE FOR UPDATE zr_flightleg.

    LOOP AT flights INTO DATA(f).
      DATA risk TYPE c LENGTH 10.
      " simple rule: the longer the delay, the higher the risk
      IF f-DelayMinutes < 15.
        risk = 'Low'.
      ELSEIF f-DelayMinutes < 60.
        risk = 'Medium'.
      ELSEIF f-DelayMinutes < 180.
        risk = 'High'.
      ELSE.
        risk = 'Critical'.
      ENDIF.
      APPEND VALUE #( %tky = f-%tky RiskLevel = risk ) TO updates.
    ENDLOOP.

    MODIFY ENTITIES OF zr_flightleg IN LOCAL MODE
      ENTITY ZrFlightleg UPDATE FIELDS ( RiskLevel )
      WITH updates.
  ENDMETHOD.

  METHOD checkDates.
    READ ENTITIES OF zr_flightleg IN LOCAL MODE
      ENTITY ZrFlightleg FIELDS ( ScheduledDeparture ScheduledArrival )
      WITH CORRESPONDING #( keys )
      RESULT DATA(flights).

    LOOP AT flights INTO DATA(f).
      " clear old message for this row first (otherwise it sticks on screen)
      APPEND VALUE #( %tky = f-%tky %state_area = 'CHECK_DATES' ) TO reported-zrflightleg.

      IF f-ScheduledDeparture IS INITIAL OR f-ScheduledArrival IS INITIAL
         OR f-ScheduledArrival <= f-ScheduledDeparture.
        APPEND VALUE #( %tky = f-%tky ) TO failed-zrflightleg.
        APPEND VALUE #( %tky        = f-%tky
                        %state_area = 'CHECK_DATES'
                        %msg        = new_message_with_text(
                                        severity = if_abap_behv_message=>severity-error
                                        text     = 'Arrival must be after departure' )
                        %element-ScheduledArrival = if_abap_behv=>mk-on )
          TO reported-zrflightleg.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD checkAirports.
    READ ENTITIES OF zr_flightleg IN LOCAL MODE
      ENTITY ZrFlightleg FIELDS ( OriginAirport DestinationAirport )
      WITH CORRESPONDING #( keys )
      RESULT DATA(flights).

    LOOP AT flights INTO DATA(f).
      APPEND VALUE #( %tky = f-%tky %state_area = 'CHECK_AIRPORTS' ) TO reported-zrflightleg.

      " both airports must exist in our ZAIRPORT master table
      SELECT SINGLE airport_id FROM zairport
        WHERE airport_id = @f-OriginAirport
        INTO @DATA(origin_ok).
      DATA(origin_found) = xsdbool( sy-subrc = 0 ).

      SELECT SINGLE airport_id FROM zairport
        WHERE airport_id = @f-DestinationAirport
        INTO @DATA(dest_ok).
      DATA(dest_found) = xsdbool( sy-subrc = 0 ).

      IF origin_found = abap_false OR dest_found = abap_false
         OR f-OriginAirport = f-DestinationAirport.
        APPEND VALUE #( %tky = f-%tky ) TO failed-zrflightleg.
        APPEND VALUE #( %tky        = f-%tky
                        %state_area = 'CHECK_AIRPORTS'
                        %msg        = new_message_with_text(
                                        severity = if_abap_behv_message=>severity-error
                                        text     = 'Origin/destination must be known airports and different' )
                        %element-OriginAirport      = if_abap_behv=>mk-on
                        %element-DestinationAirport = if_abap_behv=>mk-on )
          TO reported-zrflightleg.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD escalate.
    READ ENTITIES OF zr_flightleg IN LOCAL MODE
      ENTITY ZrFlightleg FIELDS ( RiskLevel )
      WITH CORRESPONDING #( keys )
      RESULT DATA(flights).

    LOOP AT flights INTO DATA(f).
      IF f-RiskLevel = 'Critical'.
        MODIFY ENTITIES OF zr_flightleg IN LOCAL MODE
          ENTITY ZrFlightleg UPDATE FIELDS ( Status )
          WITH VALUE #( ( %tky = f-%tky Status = 'ESCALATED' ) ).
      ELSE.
        " only critical flights can be escalated
        APPEND VALUE #( %tky = f-%tky ) TO failed-zrflightleg.
        APPEND VALUE #( %tky = f-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = 'Only Critical flights can be escalated' ) )
          TO reported-zrflightleg.
      ENDIF.
    ENDLOOP.

    " give the updated rows back to the UI so it refreshes
    READ ENTITIES OF zr_flightleg IN LOCAL MODE
      ENTITY ZrFlightleg ALL FIELDS
      WITH CORRESPONDING #( keys )
      RESULT DATA(updated).
    result = VALUE #( FOR u IN updated ( %tky = u-%tky %param = u ) ).
  ENDMETHOD.

  METHOD resolve.
    MODIFY ENTITIES OF zr_flightleg IN LOCAL MODE
      ENTITY ZrFlightleg UPDATE FIELDS ( Status )
      WITH VALUE #( FOR k IN keys ( %tky = k-%tky Status = 'RESOLVED' ) ).

    READ ENTITIES OF zr_flightleg IN LOCAL MODE
      ENTITY ZrFlightleg ALL FIELDS
      WITH CORRESPONDING #( keys )
      RESULT DATA(updated).
    result = VALUE #( FOR u IN updated ( %tky = u-%tky %param = u ) ).
  ENDMETHOD.

ENDCLASS.

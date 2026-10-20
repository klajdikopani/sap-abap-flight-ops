@AccessControl.authorizationCheck: #MANDATORY
@Metadata.allowExtensions: true
@ObjectModel.sapObjectNodeType.name: 'ZFLIGHTLEG'
@EndUserText.label: 'Flight Leg'
define root view entity ZR_FLIGHTLEG
  as select from ZFLIGHTLEG
{
  key flight_id as FlightID,
  origin_airport as OriginAirport,
  destination_airport as DestinationAirport,
  scheduled_departure as ScheduledDeparture,
  scheduled_arrival as ScheduledArrival,
  actual_departure as ActualDeparture,
  actual_arrival as ActualArrival,
  delay_minutes as DelayMinutes,
  risk_level as RiskLevel,
  status as Status,

  // color code for the UI: 3 = green, 2 = yellow, 1 = red, 0 = grey
  cast( case risk_level
          when 'Low'      then 3
          when 'Medium'   then 2
          when 'High'     then 1
          when 'Critical' then 1
          else 0
        end as abap.int1 ) as RiskCriticality,

  @Semantics.user.createdBy: true
  local_created_by as LocalCreatedBy,
  @Semantics.systemDateTime.createdAt: true
  local_created_at as LocalCreatedAt,
  @Semantics.user.localInstanceLastChangedBy: true
  local_last_changed_by as LocalLastChangedBy,
  @Semantics.systemDateTime.localInstanceLastChangedAt: true
  local_last_changed_at as LocalLastChangedAt,
  @Semantics.systemDateTime.lastChangedAt: true
  last_changed_at as LastChangedAt
}

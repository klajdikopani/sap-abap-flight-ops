@Metadata.allowExtensions: true
@Metadata.ignorePropagatedAnnotations: true
@EndUserText.label: 'Flight Leg'
@ObjectModel.sapObjectNodeType.name: 'ZFLIGHTLEG'
@AccessControl.authorizationCheck: #MANDATORY
define root view entity ZC_FLIGHTLEG
  provider contract TRANSACTIONAL_QUERY
  as projection on ZR_FLIGHTLEG
  association [1..1] to ZR_FLIGHTLEG as _BaseEntity on $projection.FLIGHTID = _BaseEntity.FLIGHTID
{
  key FlightID,
  OriginAirport,
  DestinationAirport,
  ScheduledDeparture,
  ScheduledArrival,
  ActualDeparture,
  ActualArrival,
  DelayMinutes,
  RiskLevel,
  Status,
  RiskCriticality,
  @Semantics: {
    User.Createdby: true
  }
  LocalCreatedBy,
  @Semantics: {
    Systemdatetime.Createdat: true
  }
  LocalCreatedAt,
  @Semantics: {
    User.Localinstancelastchangedby: true
  }
  LocalLastChangedBy,
  @Semantics: {
    Systemdatetime.Localinstancelastchangedat: true
  }
  LocalLastChangedAt,
  @Semantics: {
    Systemdatetime.Lastchangedat: true
  }
  LastChangedAt,
  _BaseEntity
}

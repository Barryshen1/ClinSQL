WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 50
),
ICUStays AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE
    icustays.subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    )
),
HeartRateEvents AS (
  SELECT
    chartevents.subject_id,
    chartevents.hadm_id,
    chartevents.stay_id,
    chartevents.charttime,
    chartevents.valuenum AS heart_rate
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    chartevents.itemid = 220187 -- Heart Rate
    AND chartevents.stay_id IN (
      SELECT
        stay_id
      FROM ICUStays
    )
),
ICUStayDays AS (
  SELECT
    HeartRateEvents.subject_id,
    HeartRateEvents.hadm_id,
    HeartRateEvents.stay_id,
    HeartRateEvents.charttime,
    HeartRateEvents.heart_rate,
    DATE_DIFF(HeartRateEvents.charttime, ICUStays.intime, DAY) AS icu_day
  FROM HeartRateEvents
  INNER JOIN ICUStays
    ON HeartRateEvents.subject_id = ICUStays.subject_id AND HeartRateEvents.hadm_id = ICUStays.hadm_id AND HeartRateEvents.stay_id = ICUStays.stay_id
)
SELECT
  PERCENTILE_CONT(0.25, heart_rate) AS iqr_25,
  PERCENTILE_CONT(0.75, heart_rate) AS iqr_75
FROM ICUStayDays
WHERE
  icu_day >= 2;
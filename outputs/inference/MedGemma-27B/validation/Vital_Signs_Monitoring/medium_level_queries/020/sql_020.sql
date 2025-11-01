WITH PatientCohort AS (
  SELECT
    icustays.stay_id,
    icustays.subject_id,
    icustays.intime,
    icustays.outtime,
    patients.gender,
    patients.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS patients
      ON icustays.subject_id = patients.subject_id
  WHERE
    patients.gender = 'F'
    AND patients.anchor_age BETWEEN 58 AND 68
),
HourlyMAP AS (
  SELECT
    PatientCohort.stay_id,
    PatientCohort.subject_id,
    PatientCohort.intime,
    PatientCohort.outtime,
    chartevents.charttime,
    chartevents.valuenum AS map_value
  FROM
    PatientCohort
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS chartevents
      ON PatientCohort.stay_id = chartevents.stay_id
      AND chartevents.itemid = 455 -- MAP itemid
  WHERE
    chartevents.valuenum IS NOT NULL
    AND chartevents.valuenum > 0
),
DailyMAP AS (
  SELECT
    stay_id,
    subject_id,
    intime,
    outtime,
    DATE(charttime) AS chart_date,
    AVG(map_value) AS daily_avg_map
  FROM
    HourlyMAP
  GROUP BY
    stay_id,
    subject_id,
    intime,
    outtime,
    chart_date
),
StayMAP AS (
  SELECT
    stay_id,
    subject_id,
    intime,
    outtime,
    AVG(daily_avg_map) AS mean_map_per_stay
  FROM
    DailyMAP
  GROUP BY
    stay_id,
    subject_id,
    intime,
    outtime
),
PercentileCalculation AS (
  SELECT
    mean_map_per_stay,
    PERCENTILE_CONT(mean_map_per_stay, 0.5) OVER (ORDER BY mean_map_per_stay) AS median_map,
    PERCENTILE_CONT(mean_map_per_stay, 0.16) OVER (ORDER BY mean_map_per_stay) AS p16_map,
    PERCENTILE_CONT(mean_map_per_stay, 0.84) OVER (ORDER BY mean_map_per_stay) AS p84_map
  FROM
    StayMAP
),
FinalResult AS (
  SELECT
    mean_map_per_stay,
    median_map,
    p16_map,
    p84_map
  FROM
    PercentileCalculation
)
SELECT
  mean_map_per_stay,
  median_map,
  (mean_map_per_stay - median_map) / (p84_map - p16_map) AS percentile_rank
FROM
  FinalResult
WHERE
  mean_map_per_stay = 85;
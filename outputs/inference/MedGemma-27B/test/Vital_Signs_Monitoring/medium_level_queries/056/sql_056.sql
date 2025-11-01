WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.subject_id = 94 -- Specific patient ID
), ICUStays AS (
  SELECT
    s.subject_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  WHERE
    s.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
), TemperatureMeasurements AS (
  SELECT
    c.subject_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS temperature
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS c
  WHERE
    c.itemid = 220187 -- Temperature measurement item ID
    AND c.stay_id IN (
      SELECT
        stay_id
      FROM
        ICUStays
    )
), TemperatureCategories AS (
  SELECT
    subject_id,
    stay_id,
    charttime,
    CASE
      WHEN temperature < 36 THEN '<36'
      WHEN temperature >= 36 AND temperature <= 37.9 THEN '36–37.9'
      ELSE '≥38'
    END AS temperature_category
  FROM
    TemperatureMeasurements
), PatientStats AS (
  SELECT
    subject_id,
    COUNT(DISTINCT stay_id) AS unique_patients,
    COUNT(DISTINCT stay_id) AS unique_measurements
  FROM
    TemperatureCategories
  GROUP BY
    subject_id
), MIStats AS (
  SELECT
    subject_id,
    COUNT(DISTINCT d.hadm_id) AS mi_rate
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    d.icd_code LIKE '410%' -- ICD-9 codes for Myocardial Infarction
    AND d.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
  GROUP BY
    subject_id
)
SELECT
  tc.temperature_category,
  AVG(tc.temperature) AS mean_temperature,
  MEDIAN(tc.temperature) AS median_temperature,
  PERCENTILE_CONT(0.25, tc.temperature) AS iqr_25,
  PERCENTILE_CONT(0.75, tc.temperature) AS iqr_75,
  COUNT(DISTINCT tc.subject_id) AS unique_patients,
  COUNT(DISTINCT tc.stay_id) AS unique_measurements,
  AVG(mis.mi_rate) AS mi_rate
FROM
  TemperatureCategories AS tc
LEFT JOIN
  MIStats AS mis
  ON tc.subject_id = mis.subject_id
GROUP BY
  tc.temperature_category
ORDER BY
  tc.temperature_category;
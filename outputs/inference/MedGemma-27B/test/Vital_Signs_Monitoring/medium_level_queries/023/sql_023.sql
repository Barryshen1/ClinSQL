WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age BETWEEN 62 AND 72
    AND gender = 'F'
),
ICUStays AS (
  SELECT
    p.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN
    PatientInfo AS p
    ON ic.subject_id = p.subject_id
),
TemperatureMeasurements AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ce.charttime,
    ce.valuenum AS temperature
  FROM
    ICUStays AS ic
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ic.subject_id = ce.subject_id
    AND ic.hadm_id = ce.hadm_id
    AND ic.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220177 -- Temperature Celsius
    AND ce.valuenum IS NOT NULL
),
First24hTemperature AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    charttime,
    temperature
  FROM
    TemperatureMeasurements
  WHERE
    charttime BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 24 HOUR)
),
TemperatureCategories AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    charttime,
    temperature,
    CASE
      WHEN temperature < 36.0 THEN '<36.0'
      WHEN temperature BETWEEN 36.0 AND 37.9 THEN '36.0–37.9'
      ELSE '≥38.0'
    END AS temperature_category
  FROM
    First24hTemperature
),
AKIRates AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM
          `physionet-data.mimiciv_3_1_icu.diagnoses_icd` AS di
        WHERE
          di.subject_id = subject_id
          AND di.hadm_id = hadm_id
          AND di.icd_code LIKE 'N17%' -- AKI ICD-10 codes
      ) THEN 1
      ELSE 0
    END AS has_aki
  FROM
    ICUStays
)
SELECT
  tc.temperature_category,
  AVG(tc.temperature) AS mean_temp,
  MEDIAN(tc.temperature) AS median_temp,
  PERCENTILE_CONT(0.25, tc.temperature) AS iqr_25,
  PERCENTILE_CONT(0.75, tc.temperature) AS iqr_75,
  AVG(ak.has_aki) AS aki_rate
FROM
  TemperatureCategories AS tc
JOIN
  AKIRates AS ak
  ON tc.subject_id = ak.subject_id
  AND tc.hadm_id = ak.hadm_id
  AND tc.stay_id = ak.stay_id
GROUP BY
  tc.temperature_category
ORDER BY
  tc.temperature_category;
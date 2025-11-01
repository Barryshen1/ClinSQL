WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age BETWEEN 81 AND 91
    AND gender = 'F'
),
ICUStays AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    ic.stay_id,
    ic.intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
      ON a.hadm_id = ic.hadm_id
    JOIN PatientInfo AS p
      ON a.subject_id = p.subject_id
),
TemperatureEvents AS (
  SELECT
    ic.stay_id,
    ce.charttime,
    ce.valuenum AS temperature
  FROM
    ICUStays AS ic
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON ic.stay_id = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON ce.itemid = di.itemid
  WHERE
    di.label = 'Temperature'
    AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 24 HOUR)
),
TemperatureStats AS (
  SELECT
    stay_id,
    AVG(temperature) AS mean_temp,
    MEDIAN(temperature) AS median_temp,
    PERCENTILE_CONT(temperature, 0.25) AS iqr_25,
    PERCENTILE_CONT(temperature, 0.75) AS iqr_75,
    COUNT(temperature) AS n_temp
  FROM
    TemperatureEvents
  GROUP BY
    stay_id
),
TemperatureCategories AS (
  SELECT
    stay_id,
    CASE
      WHEN mean_temp < 36.0 THEN '<36.0'
      WHEN mean_temp BETWEEN 36.0 AND 37.9 THEN '36.0–37.9'
      ELSE '≥38.0'
    END AS temp_category
  FROM
    TemperatureStats
),
MIEvents AS (
  SELECT
    ic.stay_id,
    COUNT(DISTINCT pe.stay_id) AS mi_count
  FROM
    ICUStays AS ic
    JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
      ON ic.stay_id = pe.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON pe.itemid = di.itemid
  WHERE
    di.label LIKE '%Myocardial Infarction%'
  GROUP BY
    ic.stay_id
)
SELECT
  tc.temp_category,
  COUNT(DISTINCT tc.stay_id) AS N,
  AVG(ts.mean_temp) AS mean,
  AVG(ts.median_temp) AS median,
  AVG(ts.iqr_75 - ts.iqr_25) AS IQR,
  AVG(CASE WHEN mie.mi_count > 0 THEN 1 ELSE 0 END) * 100 AS MI_rate_percent
FROM
  TemperatureCategories AS tc
  JOIN TemperatureStats AS ts
    ON tc.stay_id = ts.stay_id
  LEFT JOIN MIEvents AS mie
    ON tc.stay_id = mie.stay_id
GROUP BY
  tc.temp_category
ORDER BY
  tc.temp_category;
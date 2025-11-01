WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 71 AND 81
),
ICUStays AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  INNER JOIN
    PatientAge AS pa
    ON s.subject_id = pa.subject_id
),
TemperatureEvents AS (
  SELECT
    s.stay_id,
    s.charttime,
    s.valuenum AS temperature
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS s
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS d
    ON s.itemid = d.itemid
  WHERE
    d.label = 'Temperature'
    AND s.stay_id IN (
      SELECT
        stay_id
      FROM
        ICUStays
    )
),
First48hTemperature AS (
  SELECT
    stay_id,
    charttime,
    temperature
  FROM
    TemperatureEvents
  WHERE
    charttime BETWEEN intime AND TIMESTAMP_ADD(intime, INTERVAL 48 HOUR)
),
AvgTemperature AS (
  SELECT
    stay_id,
    AVG(temperature) AS avg_temp
  FROM
    First48hTemperature
  GROUP BY
    stay_id
),
TemperatureCategories AS (
  SELECT
    stay_id,
    CASE
      WHEN avg_temp < 36.0
      THEN '<36.0'
      WHEN avg_temp BETWEEN 36.0 AND 37.9
      THEN '36.0–37.9'
      ELSE '≥38.0'
    END AS temp_category
  FROM
    AvgTemperature
),
MI_Events AS (
  SELECT
    subject_id,
    hadm_id,
    chartdate
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code LIKE '410%'
),
MI_Rate AS (
  SELECT
    s.stay_id,
    COUNT(DISTINCT mi.subject_id) AS mi_count
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  LEFT JOIN
    MI_Events AS mi
    ON s.subject_id = mi.subject_id AND s.hadm_id = mi.hadm_id
  WHERE
    s.subject_id IN (
      SELECT
        subject_id
      FROM
        ICUStays
    )
  GROUP BY
    s.stay_id
),
FinalResult AS (
  SELECT
    tc.temp_category,
    AVG(mr.mi_count) AS mi_rate,
    AVG(at.avg_temp) AS avg_temp,
    MEDIAN(at.avg_temp) AS median_temp,
    PERCENTILE_CONT(at.avg_temp, 0.25) AS iqr_25,
    PERCENTILE_CONT(at.avg_temp, 0.75) AS iqr_75
  FROM
    TemperatureCategories AS tc
  INNER JOIN
    AvgTemperature AS at
    ON tc.stay_id = at.stay_id
  LEFT JOIN
    MI_Rate AS mr
    ON tc.stay_id = mr.stay_id
  GROUP BY
    tc.temp_category
)
SELECT
  temp_category,
  mi_rate,
  avg_temp,;
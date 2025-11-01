WITH temp_data AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    AVG(c.valuenum) AS mean_temp
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND c.itemid = 223761
    AND c.charttime BETWEEN i.intime AND i.intime + INTERVAL '24' HOUR
  GROUP BY
    i.stay_id, i.hadm_id
),
admissions_data AS (
  SELECT
    t.stay_id,
    t.mean_temp,
    a.hospital_expire_flag
  FROM
    temp_data t
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON t.hadm_id = a.hadm_id
)
SELECT
  CASE
    WHEN mean_temp < 36.0 THEN '<36.0'
    WHEN mean_temp >= 36.0 AND mean_temp < 38.0 THEN '36.0-37.9'
    ELSE '>=38.0'
  END AS temp_category,
  COUNT(*) AS N,
  AVG(mean_temp) AS mean,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY mean_temp) AS median,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY mean_temp) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY mean_temp) AS iqr,
  (SUM(hospital_expire_flag) * 100.0) / COUNT(*) AS mortality_rate
FROM
  admissions_data
GROUP BY
  temp_category;
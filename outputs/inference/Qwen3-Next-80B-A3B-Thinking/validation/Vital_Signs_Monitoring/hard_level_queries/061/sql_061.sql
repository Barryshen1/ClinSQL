WITH cohort AS (
  SELECT
    p.subject_id,
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
),
hr_avg AS (
  SELECT
    c.subject_id,
    AVG(ce.valuenum) AS avg_hr
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.itemid = 211
    AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id
),
percentile_of_70 AS (
  SELECT
    (COUNTIF(avg_hr <= 70) * 100.0) / COUNT(*) AS percentile
  FROM hr_avg
),
top_decile_threshold AS (
  SELECT PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY avg_hr) AS threshold
  FROM hr_avg
),
top_decile_patients AS (
  SELECT
    c.los,
    c.hospital_expire_flag
  FROM cohort c
  JOIN hr_avg h ON c.subject_id = h.subject_id
  WHERE h.avg_hr >= (SELECT threshold FROM top_decile_threshold)
)
SELECT
  (SELECT percentile FROM percentile_of_70) AS percentile,
  AVG(los) AS mean_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct
FROM top_decile_patients;
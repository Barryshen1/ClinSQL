WITH cohort AS (
  SELECT 
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 38 AND 48
),
bp_measurements AS (
  SELECT 
    c.stay_id,
    ce.valuenum AS sbp
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid = 220050  -- Arterial Blood Pressure systolic
    AND ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
),
per_stay_avg AS (
  SELECT 
    stay_id,
    AVG(sbp) AS avg_sbp
  FROM bp_measurements
  GROUP BY stay_id
)
SELECT 
  CASE 
    WHEN COUNT(*) = 0 THEN NULL 
    ELSE (COUNTIF(avg_sbp <= 120) * 100.0) / COUNT(*) 
  END AS percentile
FROM per_stay_avg;
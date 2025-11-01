WITH eligible_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code = '518.81')
     OR (icd_version = 10 AND (icd_code LIKE 'J96.0%' OR icd_code LIKE 'J96.2%'))
),
cohort AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN eligible_hadm e ON i.hadm_id = e.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
),
vitals_abnormal AS (
  SELECT 
    ce.stay_id,
    SUM(CASE
      WHEN ce.itemid = 220045 AND ce.valuenum IS NOT NULL AND (ce.valuenum < 60 OR ce.valuenum > 100) THEN 1
      WHEN ce.itemid = 220179 AND ce.valuenum IS NOT NULL AND (ce.valuenum < 90 OR ce.valuenum > 180) THEN 1
      WHEN ce.itemid = 220180 AND ce.valuenum IS NOT NULL AND (ce.valuenum < 60 OR ce.valuenum > 100) THEN 1
      WHEN ce.itemid = 220210 AND ce.valuenum IS NOT NULL AND (ce.valuenum < 12 OR ce.valuenum > 24) THEN 1
      WHEN ce.itemid = 223761 AND ce.valuenum IS NOT NULL AND (ce.valuenum < 36 OR ce.valuenum > 38.5) THEN 1
      WHEN ce.itemid = 220277 AND ce.valuenum IS NOT NULL AND ce.valuenum < 92 THEN 1
      ELSE 0
    END) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort c ON ce.stay_id = c.stay_id
  WHERE ce.charttime >= c.intime
    AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 1 DAY)
    AND ce.itemid IN (220045, 220179, 220180, 220210, 223761, 220277)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
scores AS (
  SELECT 
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    COALESCE(v.instability_score, 0) AS instability_score
  FROM cohort c
  LEFT JOIN vitals_abnormal v ON c.stay_id = v.stay_id
),
quantiles AS (
  SELECT APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS q75
  FROM scores
)
SELECT 
  (SELECT COUNTIF(instability_score <= 85) * 100.0 / COUNT(*) FROM scores) AS percentile_rank_85,
  (SELECT AVG(los) FROM scores WHERE instability_score >= (SELECT q75 FROM quantiles)) AS avg_los_most_unstable_quartile,
  (SELECT AVG(hospital_expire_flag) FROM scores WHERE instability_score >= (SELECT q75 FROM quantiles)) AS mortality_rate_most_unstable_quartile
FROM scores
LIMIT 1;
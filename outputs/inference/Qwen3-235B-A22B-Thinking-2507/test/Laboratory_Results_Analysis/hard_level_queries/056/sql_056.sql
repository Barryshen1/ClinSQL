WITH base_cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 55 AND 65
),
lab_scores AS (
  SELECT 
    bc.hadm_id,
    bc.admittime,
    bc.dischtime,
    bc.hospital_expire_flag,
    COUNT(le.labevent_id) AS lab_instability_score
  FROM base_cohort bc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON bc.hadm_id = le.hadm_id
    AND le.charttime >= bc.admittime
    AND le.charttime <= bc.admittime + INTERVAL '48' HOUR
    AND le.flag = 'abnormal'
  GROUP BY bc.hadm_id, bc.admittime, bc.dischtime, bc.hospital_expire_flag
),
p95_value AS (
  SELECT 
    APPROX_QUANTILES(CAST(lab_instability_score AS FLOAT64), 1000)[OFFSET(950)] AS p95
  FROM lab_scores
)
SELECT
  'top_tier' AS group_name,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(lab_instability_score) AS avg_critical_lab_rate
FROM lab_scores
WHERE lab_instability_score >= (SELECT p95 FROM p95_value)

UNION ALL

SELECT
  'entire_cohort',
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0),
  AVG(hospital_expire_flag),
  AVG(lab_instability_score)
FROM lab_scores;
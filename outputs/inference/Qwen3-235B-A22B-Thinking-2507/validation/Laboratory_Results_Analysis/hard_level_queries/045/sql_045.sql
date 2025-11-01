WITH patients_cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 52 AND 62
),
asthma_exacerbation AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code = '49391')
     OR (icd_version = 10 AND icd_code = 'J45901')
  GROUP BY hadm_id
),
cohort AS (
  SELECT pc.*
  FROM patients_cohort pc
  INNER JOIN asthma_exacerbation ae
    ON pc.hadm_id = ae.hadm_id
),
instability_scores AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    COUNT(CASE 
            WHEN l.valuenum IS NOT NULL 
              AND l.ref_range_lower IS NOT NULL 
              AND l.ref_range_upper IS NOT NULL
              AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
            THEN 1 
          END) AS instability_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime <= DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id, c.admittime
),
p90 AS (
  SELECT 
    PERCENTILE_CONT(instability_score, 0.9) OVER () AS p90_value
  FROM instability_scores
  LIMIT 1
),
with_decile AS (
  SELECT 
    i.*,
    NTILE(10) OVER (ORDER BY i.instability_score DESC) AS decile
  FROM instability_scores i
)
-- Entire cohort metrics
SELECT 
  'entire cohort' AS group_name,
  MAX(p.p90_value) AS p90_value,
  AVG(c.hospital_expire_flag) AS mortality,
  AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0) AS mean_los,
  AVG(i.instability_score) AS avg_critical_labs
FROM cohort c
INNER JOIN instability_scores i
  ON c.hadm_id = i.hadm_id
CROSS JOIN p90 p
UNION ALL
-- Top decile metrics
SELECT 
  'top decile',
  MAX(p.p90_value) AS p90_value,
  AVG(c.hospital_expire_flag),
  AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0),
  AVG(i.instability_score)
FROM cohort c
INNER JOIN with_decile i
  ON c.hadm_id = i.hadm_id
CROSS JOIN p90 p
WHERE i.decile = 1;
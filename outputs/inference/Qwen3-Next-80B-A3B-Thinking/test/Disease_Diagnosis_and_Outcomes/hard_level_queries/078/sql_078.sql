WITH hf_patients AS (
  SELECT DISTINCT a.hadm_id, a.admittime, a.deathtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
),

mortality_rate AS (
  SELECT 
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS mortality_rate
  FROM hf_patients
),

aki_rate AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '584%') OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%') THEN a.hadm_id END) * 1.0 / COUNT(DISTINCT a.hadm_id) AS aki_rate
  FROM hf_patients a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
),

ards_rate AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN (d.icd_version = 9 AND d.icd_code = '518.82') OR (d.icd_version = 10 AND d.icd_code = 'J80') THEN a.hadm_id END) * 1.0 / COUNT(DISTINCT a.hadm_id) AS ards_rate
  FROM hf_patients a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
),

median_survival AS (
  SELECT 
    PERCENTILE_CONT(TIMESTAMP_DIFF(deathtime, admittime, HOUR), 0.5) WITHIN GROUP (ORDER BY TIMESTAMP_DIFF(deathtime, admittime, HOUR)) AS median_survival
  FROM hf_patients
  WHERE hospital_expire_flag = 1
),

sofa_distribution AS (
  SELECT 
    MIN(sofa_score) AS min_sofa,
    PERCENTILE_CONT(sofa_score, 0.25) WITHIN GROUP (ORDER BY sofa_score) AS p25_sofa,
    PERCENTILE_CONT(sofa_score, 0.5) WITHIN GROUP (ORDER BY sofa_score) AS median_sofa,
    PERCENTILE_CONT(sofa_score, 0.75) WITHIN GROUP (ORDER BY sofa_score) AS p75_sofa,
    PERCENTILE_CONT(sofa_score, 0.9) WITHIN GROUP (ORDER BY sofa_score) AS p90_sofa,
    MAX(sofa_score) AS max_sofa
  FROM (
    SELECT 
      i.hadm_id,
      MAX(CAST(c.value AS FLOAT64)) AS sofa_score
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON i.stay_id = c.stay_id
    WHERE c.itemid = 223762  -- SOFA score max
      AND i.hadm_id IN (SELECT hadm_id FROM hf_patients)
    GROUP BY i.hadm_id
  )
)

SELECT 
  m.mortality_rate,
  a.aki_rate,
  ar.ards_rate,
  s.median_survival,
  sd.min_sofa,
  sd.p25_sofa,
  sd.median_sofa,
  sd.p75_sofa,
  sd.p90_sofa,
  sd.max_sofa
FROM mortality_rate m
CROSS JOIN aki_rate a
CROSS JOIN ards_rate ar
CROSS JOIN median_survival s
CROSS JOIN sofa_distribution sd;
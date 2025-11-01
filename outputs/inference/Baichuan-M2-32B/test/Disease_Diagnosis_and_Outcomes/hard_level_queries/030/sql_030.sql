WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.deathtime,
    a.hospital_expire_flag,
    a.dischtime,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 64 AND 74
),
diagnoses_summary AS (
  SELECT 
    hadm_id,
    COUNT(*) AS diagnosis_count,
    MAX(CASE WHEN icd_code REGEXP '^(A40|A41|N17|T8[0-8])' THEN 1 ELSE 0 END) AS has_major_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
  GROUP BY hadm_id
),
cohort_with_risk AS (
  SELECT 
    c.*,
    COALESCE(d.diagnosis_count, 0) AS diagnosis_count,
    COALESCE(d.has_major_complication, 0) AS has_major_complication,
    COALESCE(d.diagnosis_count, 0) + 20 * COALESCE(d.has_major_complication, 0) AS composite_risk_score,
    CASE 
      WHEN c.deathtime IS NOT NULL AND c.deathtime <= TIMESTAMP_ADD(c.admittime, INTERVAL 30 DAY) THEN 1 
      ELSE 0 
    END AS died_30day,
    CASE 
      WHEN c.hospital_expire_flag = 0 THEN DATEDIFF(c.dischtime, c.admittime) 
    END AS los
  FROM cohort c
  LEFT JOIN diagnoses_summary d 
    ON c.hadm_id = d.hadm_id
),
quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY composite_risk_score) AS quintile
  FROM cohort_with_risk
)
SELECT 
  quintile,
  COUNT(*) AS n,
  AVG(composite_risk_score) AS mean_score,
  100.0 * AVG(died_30day) AS mortality_percent,
  100.0 * AVG(has_major_complication) AS complication_percent,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median_los
FROM quintiles
GROUP BY quintile
ORDER BY quintile;
WITH base_cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_at_admission,
    pt.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE 
    pt.gender = 'M'
    AND (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) BETWEEN 39 AND 49
),

dka_diagnoses AS (
  SELECT 
    hadm_id,
    1 AS is_dka
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '250.1%') 
    OR (icd_version = 10 AND icd_code IN (
      'E0810', 'E0811', 'E0910', 'E0911', 'E1010', 'E1011', 
      'E1110', 'E1111', 'E1310', 'E1311'
    ))
),

drg_severity_data AS (
  SELECT 
    hadm_id, 
    MAX(drg_severity) AS drg_severity  -- Highest severity if multiple
  FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
  WHERE drg_type = 'APRDRG'
  GROUP BY hadm_id
),

complications AS (
  SELECT 
    hadm_id,
    MAX(CASE 
      WHEN (icd_version = 9 AND icd_code IN ('410', '427.5', '428'))
        OR (icd_version = 10 AND icd_code IN ('I21', 'I22', 'I46', 'I50'))
      THEN 1 ELSE 0 
    END) AS cardiovascular,
    MAX(CASE 
      WHEN (icd_version = 9 AND icd_code IN ('430', '431', '432', '433', '434', '436', '437', '348.3', '780.3'))
        OR (icd_version = 10 AND icd_code IN ('I60', 'I61', 'I62', 'I63', 'G93.4', 'R56'))
      THEN 1 ELSE 0 
    END) AS neurologic
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE seq_num > 1  -- Secondary diagnoses only
  GROUP BY hadm_id
),

cohort_with_data AS (
  SELECT 
    b.*,
    COALESCE(dka.is_dka, 0) AS is_dka,
    drg.drg_severity,
    COALESCE(c.cardiovascular, 0) AS cardiovascular_complication,
    COALESCE(c.neurologic, 0) AS neurologic_complication
  FROM base_cohort b
  LEFT JOIN dka_diagnoses dka ON b.hadm_id = dka.hadm_id
  LEFT JOIN drg_severity_data drg ON b.hadm_id = drg.hadm_id
  LEFT JOIN complications c ON b.hadm_id = c.hadm_id
  WHERE drg.drg_severity IS NOT NULL  -- Exclude admissions without risk score
),

dka_avg_risk AS (
  SELECT AVG(drg_severity) AS avg_dka_risk
  FROM cohort_with_data
  WHERE is_dka = 1
),

entire_cohort_risk AS (
  SELECT drg_severity
  FROM cohort_with_data
),

risk_percentile AS (
  SELECT 
    SAFE_DIVIDE(
      COUNTIF(drg_severity <= (SELECT avg_dka_risk FROM dka_avg_risk)),
      COUNT(*)
    ) * 100 AS risk_percentile
  FROM entire_cohort_risk
)

SELECT 
  'DKA' AS group_label,
  AVG(drg_severity) AS mean_risk_score,
  AVG(CASE 
      WHEN deathtime IS NOT NULL AND 
           DATETIME_DIFF(deathtime, admittime, DAY) <= 30 
      THEN 1 ELSE 0 
  END) AS mortality_30d,
  AVG(cardiovascular_complication) AS cv_complication_rate,
  AVG(neurologic_complication) AS neuro_complication_rate,
  AVG(CASE 
      WHEN hospital_expire_flag = 0 THEN 
        DATETIME_DIFF(dischtime, admittime, DAY) 
      ELSE NULL 
  END) AS mean_survivor_los,
  (SELECT risk_percentile FROM risk_percentile) AS risk_percentile
FROM cohort_with_data
WHERE is_dka = 1

UNION ALL

SELECT 
  'All Males' AS group_label,
  AVG(drg_severity) AS mean_risk_score,
  AVG(CASE 
      WHEN deathtime IS NOT NULL AND 
           DATETIME_DIFF(deathtime, admittime, DAY) <= 30 
      THEN 1 ELSE 0 
  END) AS mortality_30d,
  AVG(cardiovascular_complication) AS cv_complication_rate,
  AVG(neurologic_complication) AS neuro_complication_rate,
  AVG(CASE 
      WHEN hospital_expire_flag = 0 THEN 
        DATETIME_DIFF(dischtime, admittime, DAY) 
      ELSE NULL 
  END) AS mean_survivor_los,
  NULL AS risk_percentile
FROM cohort_with_data;
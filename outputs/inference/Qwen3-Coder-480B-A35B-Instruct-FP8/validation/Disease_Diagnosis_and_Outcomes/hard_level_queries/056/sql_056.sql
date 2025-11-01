WITH septic_shock_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code = '78552')
     OR (icd_version = 10 AND icd_code = 'R6521')
),

admission_diagnosis_counts AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT icd_code) AS diagnosis_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    p.anchor_age,
    p.gender,
    p.dod,
    adc.diagnosis_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN admission_diagnosis_counts adc
    ON a.hadm_id = adc.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND adc.diagnosis_count > 15
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN septic_shock_codes ssc
        ON d.icd_code = ssc.icd_code AND d.icd_version = ssc.icd_version
      WHERE d.hadm_id = a.hadm_id
    )
),

-- 90-day mortality flag
cohort_outcomes AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 1
      WHEN dod IS NOT NULL AND DATE_DIFF(dod, admittime, DAY) <= 90 THEN 1
      ELSE 0
    END AS mortality_90d
  FROM cohort
),

-- General inpatients (excluding cohort)
general_inpatients AS (
  SELECT 
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.hospital_expire_flag,
    p.dod,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE a.hadm_id NOT IN (SELECT hadm_id FROM cohort)
),

general_outcomes AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 1
      WHEN dod IS NOT NULL AND DATE_DIFF(dod, admittime, DAY) <= 90 THEN 1
      ELSE 0
    END AS mortality_90d
  FROM general_inpatients
),

-- Metrics for cohort
cohort_metrics AS (
  SELECT
    AVG(CAST(diagnosis_count AS FLOAT64)) AS mean_risk_score_proxy,
    AVG(CAST(mortality_90d AS FLOAT64)) AS mortality_90d_rate,
    AVG(CASE WHEN diagnosis_count > 1 THEN 1 ELSE 0 END) AS major_complication_rate,
    AVG(CASE WHEN mortality_90d = 0 THEN los ELSE NULL END) AS survivor_avg_los
  FROM cohort_outcomes
),

-- Metrics for general inpatients
general_metrics AS (
  SELECT
    AVG(CAST(mortality_90d AS FLOAT64)) AS mortality_90d_rate,
    AVG(CASE WHEN mortality_90d = 0 THEN los ELSE NULL END) AS survivor_avg_los
  FROM general_outcomes
),

-- Percentile for 68M with 16 diagnoses
percentile_calc AS (
  SELECT
    PERCENTILE_CONT(CASE WHEN mortality_90d = 0 THEN los ELSE NULL END, 0.5) OVER() AS median_survivor_los,
    PERCENTILE_CONT(CASE WHEN mortality_90d = 0 THEN los ELSE NULL END, 0.68) OVER() AS percentile_68_survivor_los
  FROM cohort_outcomes
  WHERE anchor_age = 68 AND diagnosis_count = 16
  LIMIT 1
)

-- Final output
SELECT
  c.mean_risk_score_proxy,
  c.mortality_90d_rate,
  c.major_complication_rate,
  c.survivor_avg_los AS cohort_survivor_los,
  g.mortality_90d_rate AS general_mortality_90d_rate,
  g.survivor_avg_los AS general_survivor_los,
  p.percentile_68_survivor_los
FROM cohort_metrics c
CROSS JOIN general_metrics g
LEFT JOIN percentile_calc p ON TRUE;
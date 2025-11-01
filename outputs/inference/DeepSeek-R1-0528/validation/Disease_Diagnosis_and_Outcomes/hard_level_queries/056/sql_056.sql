WITH base_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.deathtime, 
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.dod,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    COUNT(diag.icd_code) AS num_diagnoses,
    MAX(
      CASE 
        WHEN (Diag.icd_code = '785.52' AND Diag.icd_version = 9) 
          OR (Diag.icd_code = 'R65.21' AND Diag.icd_version = 10) 
        THEN 1 ELSE 0 
      END
    ) AS has_septic_shock
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` Diag 
    ON a.hadm_id = Diag.hadm_id
  GROUP BY 
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, 
    a.hospital_expire_flag, p.gender, p.anchor_age, p.anchor_year, p.dod
),
drg_severity AS (
  SELECT 
    hadm_id, 
    MAX(CAST(drg_severity AS INT64)) AS max_drg_severity
  FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
  GROUP BY hadm_id
),
base_with_drg AS (
  SELECT 
    b.*,
    d.max_drg_severity
  FROM base_admissions b
  LEFT JOIN drg_severity d 
    ON b.hadm_id = d.hadm_id
),
study_group AS (
  SELECT *
  FROM base_with_drg
  WHERE 
    gender = 'M'
    AND age_at_admission BETWEEN 63 AND 73
    AND has_septic_shock = 1
    AND num_diagnoses > 15
),
general_population AS (
  SELECT *
  FROM base_with_drg
),
metrics AS (
  SELECT 
    'Study Group' AS cohort,
    AVG(max_drg_severity) AS mean_risk_score,
    AVG(
      CASE 
        WHEN dod IS NOT NULL 
          AND DATE_DIFF(CAST(dod AS DATE), CAST(admittime AS DATE), DAY) <= 90 
        THEN 1 
        ELSE 0 
      END
    ) AS mortality_90d,
    AVG(
      CASE 
        WHEN max_drg_severity IN (3, 4) THEN 1 
        ELSE 0 
      END
    ) AS major_complication_rate,
    AVG(
      CASE 
        WHEN hospital_expire_flag = 0 
          THEN DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) 
        ELSE NULL 
      END
    ) AS survivor_LOS
  FROM study_group
  UNION ALL
  SELECT 
    'General Inpatients' AS cohort,
    AVG(max_drg_severity) AS mean_risk_score,
    AVG(
      CASE 
        WHEN dod IS NOT NULL 
          AND DATE_DIFF(CAST(dod AS DATE), CAST(admittime AS DATE), DAY) <= 90 
        THEN 1 
        ELSE 0 
      END
    ) AS mortality_90d,
    AVG(
      CASE 
        WHEN max_drg_severity IN (3, 4) THEN 1 
        ELSE 0 
      END
    ) AS major_complication_rate,
    AVG(
      CASE 
        WHEN hospital_expire_flag = 0 
          THEN DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) 
        ELSE NULL 
      END
    ) AS survivor_LOS
  FROM general_population
),
percentile_calc AS (
  SELECT 
    (COUNTIF(num_diagnoses <= 16) * 100.0 / COUNT(*)) 
      AS percentile_16_diagnoses
  FROM general_population
  WHERE 
    gender = 'M' 
    AND age_at_admission = 68
)
SELECT 
  cohort,
  ROUND(mean_risk_score, 2) AS mean_risk_score,
  ROUND(mortality_90d, 4) AS mortality_90d,
  ROUND(major_complication_rate, 4) AS major_complication_rate,
  ROUND(survivor_LOS, 2) AS survivor_LOS,
  NULL AS percentile_16_diagnoses
FROM metrics
UNION ALL
SELECT 
  'Percentile for 68M with 16 diagnoses' AS cohort,
  NULL, NULL, NULL, NULL,
  ROUND(percentile_16_diagnoses, 2)
FROM percentile_calc;
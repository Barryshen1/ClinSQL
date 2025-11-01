WITH diabetes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code LIKE '249%' OR icd_code LIKE '250%'))
     OR (icd_version = 10 AND icd_code BETWEEN 'E08' AND 'E13Z') -- E08-E13 variants
),
heart_failure AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
cohort AS (
  SELECT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN diabetes d USING (hadm_id)
  JOIN heart_failure hf USING (hadm_id)
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 56 AND 66
),
glp1_meds AS (
  SELECT hadm_id, starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%liraglutide%'
     OR LOWER(drug) LIKE '%exenatide%'
     OR LOWER(drug) LIKE '%dulaglutide%'
     OR LOWER(drug) LIKE '%semaglutide%'
     OR LOWER(drug) LIKE '%lixisenatide%'
     OR LOWER(drug) LIKE '%albiglutide%'
),
usage_flags AS (
  SELECT
    c.hadm_id,
    MAX(CASE WHEN g.starttime BETWEEN c.admittime 
                               AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR) 
             THEN 1 ELSE 0 END) AS use_first_48h,
    MAX(CASE WHEN g.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR)
                               AND c.dischtime
             THEN 1 ELSE 0 END) AS use_final_24h
  FROM cohort c
  LEFT JOIN glp1_meds g
    ON c.hadm_id = g.hadm_id
  GROUP BY c.hadm_id
),
stats AS (
  SELECT
    COUNT(*) AS n_cohort,
    SUM(use_first_48h) AS n_first_48h,
    SUM(use_final_24h) AS n_final_24h
  FROM usage_flags
)
SELECT
  n_cohort,
  ROUND(100 * n_first_48h / n_cohort, 2) AS prevalence_first_48h_pct,
  ROUND(100 * n_final_24h / n_cohort, 2) AS prevalence_final_24h_pct,
  ROUND( (100 * n_final_24h / n_cohort) - (100 * n_first_48h / n_cohort), 2) AS net_change_pct
FROM stats;
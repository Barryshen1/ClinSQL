WITH diabetes_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '250%')
     OR (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%'))
),
hf_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
cohort AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN diabetes_hadm d ON a.hadm_id = d.hadm_id
  JOIN hf_hadm h ON a.hadm_id = h.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.hadm_id IS NOT NULL
),
first48_presc AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres ON c.hadm_id = pres.hadm_id
  WHERE pres.starttime >= c.admittime
    AND pres.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND (LOWER(pres.drug) LIKE '%liraglutide%'
         OR LOWER(pres.drug) LIKE '%semaglutide%'
         OR LOWER(pres.drug) LIKE '%dulaglutide%'
         OR LOWER(pres.drug) LIKE '%exenatide%'
         OR LOWER(pres.drug) LIKE '%albiglutide%'
         OR LOWER(pres.drug) LIKE '%lixisenatide%')
),
last12_presc AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres ON c.hadm_id = pres.hadm_id
  WHERE pres.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
    AND pres.starttime < c.dischtime
    AND (LOWER(pres.drug) LIKE '%liraglutide%'
         OR LOWER(pres.drug) LIKE '%semaglutide%'
         OR LOWER(pres.drug) LIKE '%dulaglutide%'
         OR LOWER(pres.drug) LIKE '%exenatide%'
         OR LOWER(pres.drug) LIKE '%albiglutide%'
         OR LOWER(pres.drug) LIKE '%lixisenatide%')
),
totals AS (
  SELECT
    COUNT(*) AS total_admissions,
    COUNT(DISTINCT f.hadm_id) AS first48_count,
    COUNT(DISTINCT l.hadm_id) AS last12_count
  FROM cohort c
  LEFT JOIN first48_presc f ON c.hadm_id = f.hadm_id
  LEFT JOIN last12_presc l ON c.hadm_id = l.hadm_id
)
SELECT
  total_admissions,
  ROUND((first48_count * 100.0 / total_admissions), 2) AS first48_prevalence_pct,
  ROUND((last12_count * 100.0 / total_admissions), 2) AS last12_prevalence_pct,
  ROUND((last12_count * 100.0 / total_admissions) - (first48_count * 100.0 / total_admissions), 2) AS absolute_change_pct,
  ROUND(
    CASE 
      WHEN first48_count = 0 THEN NULL 
      ELSE (((last12_count * 100.0 / total_admissions) - (first48_count * 100.0 / total_admissions)) / (first48_count * 100.0 / total_admissions)) * 100 
    END, 2
  ) AS relative_change_pct
FROM totals;
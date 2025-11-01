WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 58 AND 68
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 72
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = adm.subject_id 
        AND diag.hadm_id = adm.hadm_id 
        AND diag.icd_code LIKE 'E11%'
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = adm.subject_id 
        AND diag.hadm_id = adm.hadm_id 
        AND diag.icd_code LIKE 'I50%'
    )
),

glp1_first72 AS (
  SELECT 
    c.hadm_id,
    MAX(1) AS glp1_first72_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON c.hadm_id = rx.hadm_id
  WHERE 
    LOWER(rx.drug) LIKE '%glp-1%' 
    OR LOWER(rx.drug) LIKE '%glucagon-like peptide-1%'
    OR LOWER(rx.drug) LIKE '%semaglutide%'
    OR LOWER(rx.drug) LIKE '%liraglutide%'
    OR LOWER(rx.drug) LIKE '%dulaglutide%'
    OR LOWER(rx.drug) LIKE '%exenatide%'
    AND DATETIME_DIFF(rx.starttime, c.admittime, HOUR) <= 72
  GROUP BY c.hadm_id
),

glp1_final12 AS (
  SELECT 
    c.hadm_id,
    MAX(1) AS glp1_final12_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON c.hadm_id = rx.hadm_id
  WHERE 
    LOWER(rx.drug) LIKE '%glp-1%' 
    OR LOWER(rx.drug) LIKE '%glucagon-like peptide-1%'
    OR LOWER(rx.drug) LIKE '%semaglutide%'
    OR LOWER(rx.drug) LIKE '%liraglutide%'
    OR LOWER(rx.drug) LIKE '%dulaglutide%'
    OR LOWER(rx.drug) LIKE '%exenatide%'
    AND rx.starttime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)
    AND rx.starttime <= c.dischtime
  GROUP BY c.hadm_id
)

SELECT 
  COUNT(*) AS total_admissions,
  ROUND(100 * COUNT(glp1_first72_flag) / COUNT(*), 2) AS pct_first_72h,
  ROUND(100 * COUNT(glp1_final12_flag) / COUNT(*), 2) AS pct_final_12h,
  ROUND(100 * COUNT(glp1_first72_flag) / COUNT(*) - 100 * COUNT(glp1_final12_flag) / COUNT(*), 2) AS absolute_difference_pp
FROM cohort c
LEFT JOIN glp1_first72 f72 ON c.hadm_id = f72.hadm_id
LEFT JOIN glp1_final12 f12 ON c.hadm_id = f12.hadm_id;
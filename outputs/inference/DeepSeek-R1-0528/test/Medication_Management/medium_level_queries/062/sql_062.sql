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
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 50 AND 60
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 72
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        diag.subject_id = adm.subject_id 
        AND diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '250%') OR 
          (diag.icd_version = 10 AND diag.icd_code LIKE 'E1%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        diag.subject_id = adm.subject_id 
        AND diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '428%') OR 
          (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
        )
    )
),

glp1_first_72h AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON c.hadm_id = rx.hadm_id
  WHERE 
    LOWER(rx.drug) LIKE '%exenatide%'
    OR LOWER(rx.drug) LIKE '%liraglutide%'
    OR LOWER(rx.drug) LIKE '%dulaglutide%'
    OR LOWER(rx.drug) LIKE '%semaglutide%'
    OR LOWER(rx.drug) LIKE '%lixisenatide%'
    OR LOWER(rx.drug) LIKE '%albiglutide%'
  AND LOWER(rx.route) IN ('iv', 'subq', 'subcutaneous', 'intravenous', 'injection')
  AND rx.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
),

glp1_final_72h AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON c.hadm_id = rx.hadm_id
  WHERE 
    LOWER(rx.drug) LIKE '%exenatide%'
    OR LOWER(rx.drug) LIKE '%liraglutide%'
    OR LOWER(rx.drug) LIKE '%dulaglutide%'
    OR LOWER(rx.drug) LIKE '%semaglutide%'
    OR LOWER(rx.drug) LIKE '%lixisenatide%'
    OR LOWER(rx.drug) LIKE '%albiglutide%'
  AND LOWER(rx.route) IN ('iv', 'subq', 'subcutaneous', 'intravenous', 'injection')
  AND rx.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime
)

SELECT
  COUNT(c.hadm_id) AS total_admissions,
  COUNT(DISTINCT f72.hadm_id) AS first_72h_initiations,
  COUNT(DISTINCT l72.hadm_id) AS final_72h_initiations,
  ROUND(COUNT(DISTINCT f72.hadm_id) / COUNT(c.hadm_id), 4) AS first_72h_rate,
  ROUND(COUNT(DISTINCT l72.hadm_id) / COUNT(c.hadm_id), 4) AS final_72h_rate,
  ROUND(
    (COUNT(DISTINCT l72.hadm_id) - COUNT(DISTINCT f72.hadm_id)) / COUNT(c.hadm_id), 
    4
  ) AS absolute_change,
  ROUND(
    (COUNT(DISTINCT l72.hadm_id) - COUNT(DISTINCT f72.hadm_id)) 
    / NULLIF(COUNT(DISTINCT f72.hadm_id), 0), 
    4
  ) AS relative_change
FROM cohort c
LEFT JOIN glp1_first_72h f72
  ON c.hadm_id = f72.hadm_id
LEFT JOIN glp1_final_72h l72
  ON c.hadm_id = l72.hadm_id;
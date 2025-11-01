WITH eligible_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.admittime,
    a.dischtime,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON p.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND (
      -- Diabetes ICD-10 or ICD-9
      (ddi.icd_version = 10 AND (ddi.icd_code LIKE 'E10%' OR ddi.icd_code LIKE 'E11%' OR ddi.icd_code LIKE 'E13%'))
      OR
      (ddi.icd_version = 9 AND ddi.icd_code LIKE '250%')
    )
    AND (
      -- Heart failure ICD-10 or ICD-9
      (ddi.icd_version = 10 AND ddi.icd_code LIKE 'I50%')
      OR
      (ddi.icd_version = 9 AND ddi.icd_code LIKE '428%')
    )
),

glp1_prescriptions AS (
  SELECT DISTINCT
    ep.subject_id,
    ep.admittime,
    ep.dischtime,
    pr.starttime,
    pr.route,
    pr.drug
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON ep.subject_id = pr.subject_id AND ep.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) LIKE '%liraglutide%'
     OR LOWER(pr.drug) LIKE '%semaglutide%'
     OR LOWER(pr.drug) LIKE '%exenatide%'
     OR LOWER(pr.drug) LIKE '%dulaglutide%'
     OR LOWER(pr.drug) LIKE '%lixisenatide%'
     OR LOWER(pr.drug) LIKE '%albiglutide%'
     OR LOWER(pr.drug) LIKE '%tirzepatide%'  -- newer dual GIP/GLP-1
     OR LOWER(pr.drug) LIKE '%glp-1%'
  AND (
    LOWER(pr.route) LIKE '%subcutaneous%'
    OR LOWER(pr.route) LIKE '%sc%'
    OR LOWER(pr.route) LIKE '%sq%'
  )
),

glp1_flags AS (
  SELECT
    subject_id,
    admittime,
    dischtime,
    CASE
      WHEN starttime >= admittime AND starttime <= admittime + INTERVAL '24' HOUR THEN 1
      ELSE 0
    END AS glp1_first24,
    CASE
      WHEN dischtime - admittime >= INTERVAL '12' HOUR
        AND starttime >= dischtime - INTERVAL '12' HOUR
        AND starttime <= dischtime THEN 1
      ELSE 0
    END AS glp1_last12
  FROM glp1_prescriptions
),

final_counts AS (
  SELECT
    COUNT(*) AS total_patients,
    SUM(glp1_first24) AS count_glp1_first24,
    SUM(glp1_last12) AS count_glp1_last12
  FROM glp1_flags
)

SELECT
  ROUND(100.0 * count_glp1_first24 / total_patients, 2) AS prevalence_first24_percent,
  ROUND(100.0 * count_glp1_last12 / total_patients, 2) AS prevalence_last12_percent
FROM final_counts;
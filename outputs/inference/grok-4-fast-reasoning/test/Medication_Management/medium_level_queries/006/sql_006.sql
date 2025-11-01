WITH cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime,
    p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),
has_t2dm AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND icd_code LIKE '250.%' 
     AND icd_code NOT LIKE '250.1%' AND icd_code NOT LIKE '250.3%')
    OR (icd_version = 10 AND icd_code LIKE 'E11.%')
  )
  GROUP BY hadm_id
),
has_hf AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND icd_code LIKE '428.%')
    OR (icd_version = 10 AND icd_code LIKE 'I50.%')
  )
  GROUP BY hadm_id
),
patient_cohort AS (
  SELECT c.*
  FROM cohort c
  JOIN has_t2dm t ON c.hadm_id = t.hadm_id
  JOIN has_hf h ON c.hadm_id = h.hadm_id
),
glp1_admin AS (
  SELECT e.subject_id, e.hadm_id, e.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed 
    ON e.subject_id = ed.subject_id 
    AND e.emar_id = ed.emar_id 
    AND e.emar_seq = ed.emar_seq
  WHERE (
    LOWER(e.medication) LIKE '%liraglutide%'
    OR LOWER(e.medication) LIKE '%exenatide%'
    OR LOWER(e.medication) LIKE '%dulaglutide%'
    OR LOWER(e.medication) LIKE '%semaglutide%'
    OR LOWER(e.medication) LIKE '%albiglutide%'
    OR LOWER(e.medication) LIKE '%lixisenatide%'
  )
    AND LOWER(ed.route) IN ('subcutaneous', 'intravenous', 'intramuscular')
    AND e.hadm_id IS NOT NULL
),
glp1_first AS (
  SELECT subject_id, hadm_id, MIN(charttime) AS first_time
  FROM glp1_admin
  GROUP BY subject_id, hadm_id
),
analysis AS (
  SELECT pc.*,
    gf.first_time,
    CASE 
      WHEN gf.first_time >= pc.admittime 
        AND gf.first_time < pc.dischtime 
        AND gf.first_time < pc.admittime + INTERVAL 72 HOUR 
      THEN 1 
      ELSE 0 
    END AS init_first72,
    CASE 
      WHEN gf.first_time >= pc.admittime 
        AND gf.first_time < pc.dischtime 
        AND gf.first_time >= pc.dischtime - INTERVAL 48 HOUR 
      THEN 1 
      ELSE 0 
    END AS init_last48
  FROM patient_cohort pc
  LEFT JOIN glp1_first gf 
    ON pc.subject_id = gf.subject_id AND pc.hadm_id = gf.hadm_id
)
SELECT 
  ROUND(AVG(init_first72) * 100, 2) AS first72_rate_pct,
  ROUND(AVG(init_last48) * 100, 2) AS last48_rate_pct,
  ROUND(ABS(AVG(init_first72) - AVG(init_last48)) * 100, 2) AS abs_diff_pp
FROM analysis;
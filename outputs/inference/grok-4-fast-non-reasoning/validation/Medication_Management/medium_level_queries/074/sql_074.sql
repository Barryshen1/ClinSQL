WITH cohort AS (
  -- Qualifying patients and admissions with diabetes and heart failure
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id 
    AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND EXTRACT(YEAR FROM a.admittime) = p.anchor_year
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND a.hospital_expire_flag = 0
    AND d.icd_version = '10'
    AND (
      -- Diabetes ICD-10
      d.icd_code LIKE 'E1[0-3]%' OR
      -- Heart failure ICD-10
      d.icd_code LIKE 'I50%'
    )
  GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime
  HAVING COUNT(CASE WHEN d.icd_code LIKE 'E1[0-3]%' THEN 1 END) > 0
     AND COUNT(CASE WHEN d.icd_code LIKE 'I50%' THEN 1 END) > 0
),

first24h_starts AS (
  -- GLP-1 subcutaneous starts in first 24h
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON c.subject_id = pres.subject_id 
    AND c.hadm_id = pres.hadm_id
  WHERE pres.starttime IS NOT NULL
    AND LOWER(pres.route) LIKE '%sub%'
    AND (
      pres.drug LIKE '%semaglutide%' OR
      pres.drug LIKE '%liraglutide%' OR
      pres.drug LIKE '%dulaglutide%' OR
      pres.drug LIKE '%exenatide%' OR
      pres.drug LIKE '%albiglutide%' OR
      pres.drug LIKE '%lixisenatide%' OR
      pres.drug LIKE '%Ozempic%' OR
      pres.drug LIKE '%Rybelsus%' OR
      pres.drug LIKE '%Victoza%' OR
      pres.drug LIKE '%Saxenda%' OR
      pres.drug LIKE '%Trulicity%' OR
      pres.drug LIKE '%Bydureon%' OR
      pres.drug LIKE '%Byetta%'
    )
    AND pres.starttime >= c.admittime
    AND pres.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
),

final12h_starts AS (
  -- GLP-1 subcutaneous starts in final 12h (exclude if dischtime NULL)
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON c.subject_id = pres.subject_id 
    AND c.hadm_id = pres.hadm_id
  WHERE c.dischtime IS NOT NULL
    AND pres.starttime IS NOT NULL
    AND LOWER(pres.route) LIKE '%sub%'
    AND (
      pres.drug LIKE '%semaglutide%' OR
      pres.drug LIKE '%liraglutide%' OR
      pres.drug LIKE '%dulaglutide%' OR
      pres.drug LIKE '%exenatide%' OR
      pres.drug LIKE '%albiglutide%' OR
      pres.drug LIKE '%lixisenatide%' OR
      pres.drug LIKE '%Ozempic%' OR
      pres.drug LIKE '%Rybelsus%' OR
      pres.drug LIKE '%Victoza%' OR
      pres.drug LIKE '%Saxenda%' OR
      pres.drug LIKE '%Trulicity%' OR
      pres.drug LIKE '%Bydureon%' OR
      pres.drug LIKE '%Byetta%'
    )
    AND pres.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
    AND pres.starttime < c.dischtime
)

-- Compute prevalences
SELECT 
  COUNT(DISTINCT c.hadm_id) AS total_qualifying_admissions,
  COUNT(DISTINCT f.hadm_id) AS first24h_glp1_admissions,
  SAFE_DIVIDE(COUNT(DISTINCT f.hadm_id), COUNT(DISTINCT c.hadm_id)) * 100 AS first24h_prevalence_pct,
  COUNT(DISTINCT l.hadm_id) AS final12h_glp1_admissions,
  SAFE_DIVIDE(COUNT(DISTINCT l.hadm_id), COUNT(DISTINCT c.hadm_id)) * 100 AS final12h_prevalence_pct
FROM cohort c
LEFT JOIN first24h_starts f ON c.hadm_id = f.hadm_id
LEFT JOIN final12h_starts l ON c.hadm_id = l.hadm_id;
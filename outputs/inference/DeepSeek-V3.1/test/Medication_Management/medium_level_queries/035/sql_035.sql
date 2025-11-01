WITH cohort AS (
  -- Get female inpatients aged 57-67 with diabetes and heart failure
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 57 AND 67
    AND adm.hadm_id IN (
      -- Admissions with diabetes
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      WHERE dx.icd_code LIKE 'E1%' -- ICD-10 diabetes codes
    )
    AND adm.hadm_id IN (
      -- Admissions with heart failure
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      WHERE dx.icd_code LIKE 'I50%' -- ICD-10 heart failure
    )
    AND adm.dischtime IS NOT NULL
    -- Exclude very short stays (<12h) to ensure final 12h window exists
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 12
),

glp1_first48h AS (
  -- Check for GLP-1 RA in first 48h
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON c.hadm_id = rx.hadm_id AND c.subject_id = rx.subject_id
  WHERE rx.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    AND (LOWER(rx.drug) LIKE '%semaglutide%'
       OR LOWER(rx.drug) LIKE '%liraglutide%'
       OR LOWER(rx.drug) LIKE '%dulaglutide%'
       OR LOWER(rx.drug) LIKE '%exenatide%'
       OR LOWER(rx.drug) LIKE '%lixisenatide%')
),

glp1_final12h AS (
  -- Check for GLP-1 RA in final 12h
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON c.hadm_id = rx.hadm_id AND c.subject_id = rx.subject_id
  WHERE rx.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime
    AND (LOWER(rx.drug) LIKE '%semaglutide%'
       OR LOWER(rx.drug) LIKE '%liraglutide%'
       OR LOWER(rx.drug) LIKE '%dulaglutide%'
       OR LOWER(rx.drug) LIKE '%exenatide%'
       OR LOWER(rx.drug) LIKE '%lixisenatide%')
)

SELECT
  COUNT(*) AS total_admissions,
  COUNT(DISTINCT f48.hadm_id) AS first48h_count,
  ROUND(COUNT(DISTINCT f48.hadm_id) / COUNT(*) * 100, 2) AS first48h_prevalence,
  COUNT(DISTINCT f12.hadm_id) AS final12h_count,
  ROUND(COUNT(DISTINCT f12.hadm_id) / COUNT(*) * 100, 2) AS final12h_prevalence,
  ROUND(COUNT(DISTINCT f12.hadm_id) / COUNT(*) * 100 - COUNT(DISTINCT f48.hadm_id) / COUNT(*) * 100, 2) AS absolute_change,
  ROUND((COUNT(DISTINCT f12.hadm_id) - COUNT(DISTINCT f48.hadm_id)) / COUNT(DISTINCT f48.hadm_id) * 100, 2) AS relative_change
FROM cohort c
LEFT JOIN glp1_first48h f48 ON c.hadm_id = f48.hadm_id
LEFT JOIN glp1_final12h f12 ON c.hadm_id = f12.hadm_id;
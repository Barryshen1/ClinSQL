WITH cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dx
    ON diag.icd_code = dx.icd_code
    AND diag.icd_version = dx.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 35 AND 45
    AND (
      -- ICD-9 chest pain: 786.5xx ; ICD-10: R07.x
      diag.icd_version = 9 AND (
        diag.icd_code LIKE '7865%' OR diag.icd_code LIKE '410%' 
      )
      OR 
      diag.icd_version = 10 AND (
        diag.icd_code LIKE 'R07%' OR diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%' 
      )
    )
),
troponin AS (
  SELECT le.subject_id, le.hadm_id, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin t%'
    AND LOWER(di.label) LIKE '%high sensitivity%'
    AND le.valuenum IS NOT NULL
),
first_trop AS (
  SELECT t.subject_id, t.hadm_id, t.valuenum,
         ROW_NUMBER() OVER (PARTITION BY t.hadm_id ORDER BY t.charttime ASC) AS rn
  FROM troponin t
  JOIN cohort c
    ON t.subject_id = c.subject_id
    AND t.hadm_id = c.hadm_id
)
SELECT 
  CASE
    WHEN valuenum <= 14 THEN 'Normal'
    WHEN valuenum > 14 AND valuenum <= 30 THEN 'Borderline'
    WHEN valuenum > 30 THEN 'Myocardial injury'
    ELSE 'Unknown'
  END AS troponin_category,
  COUNT(*) AS patient_count
FROM first_trop
WHERE rn = 1
GROUP BY troponin_category
ORDER BY troponin_category;
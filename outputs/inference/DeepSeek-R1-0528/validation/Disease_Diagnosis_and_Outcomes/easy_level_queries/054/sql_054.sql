WITH stroke_admissions AS (
  SELECT 
      a.subject_id, 
      a.hadm_id, 
      a.admittime, 
      a.dischtime,
      -- Calculate exact age at admission
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admission,
      -- Calculate LOS in fractional days
      DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      ON a.hadm_id = diag.hadm_id AND a.subject_id = diag.subject_id
  WHERE 
      p.gender = 'M'
      AND diag.seq_num = 1  -- Primary diagnosis
      AND (
          -- ICD-10 codes
          (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^(I60|I61|I62)'))
          OR 
          -- ICD-9 codes
          (diag.icd_version = 9 AND diag.icd_code IN ('430', '431', '432'))
      )
)
SELECT 
    STDDEV(los_days) AS sd_length_of_stay_days
FROM 
    stroke_admissions
WHERE 
    age_admission BETWEEN 51 AND 61;
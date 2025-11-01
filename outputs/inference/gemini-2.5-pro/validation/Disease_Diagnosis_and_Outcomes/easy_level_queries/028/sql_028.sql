WITH pneumonia_admissions AS (
  -- First, identify all unique hospital admissions (hadm_id) that match the criteria
  SELECT DISTINCT adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    -- Condition 1: Female patients
    pat.gender = 'F'
    -- Condition 2: Aged 67-77 at the time of admission
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age BETWEEN 67 AND 77
    -- Condition 3: Primary diagnosis
    AND dx.seq_num = 1
    -- Condition 4: Diagnosis is a form of community-acquired pneumonia (CAP)
    AND (
      -- ICD-9 codes for pneumonia
      (dx.icd_version = 9 AND (
          dx.icd_code LIKE '480%' -- Viral pneumonia
          OR dx.icd_code = '481'   -- Pneumococcal pneumonia
          OR dx.icd_code LIKE '482%' -- Other bacterial pneumonia
          OR dx.icd_code LIKE '483%' -- Pneumonia due to other specified organism
          OR dx.icd_code = '485'   -- Bronchopneumonia, organism unspecified
          OR dx.icd_code = '486'   -- Pneumonia, organism unspecified
      ))
      OR
      -- ICD-10 codes for pneumonia
      (dx.icd_version = 10 AND (
          dx.icd_code LIKE 'J12%' -- Viral pneumonia, not elsewhere classified
          OR dx.icd_code = 'J13'  -- Pneumonia due to Streptococcus pneumoniae
          OR dx.icd_code = 'J14'  -- Pneumonia due to Haemophilus influenzae
          OR dx.icd_code LIKE 'J15%' -- Bacterial pneumonia, not elsewhere classified
          OR dx.icd_code LIKE 'J16%' -- Pneumonia due to other infectious organisms, not elsewhere classified
          OR dx.icd_code LIKE 'J18%' -- Pneumonia, unspecified organism
      ))
    )
)
-- Now, calculate the length of stay for these admissions and find the 25th percentile
SELECT
  APPROX_QUANTILES(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY), 100)[OFFSET(25)] AS los_25th_percentile_days
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN pneumonia_admissions AS pa
  ON adm.hadm_id = pa.hadm_id;
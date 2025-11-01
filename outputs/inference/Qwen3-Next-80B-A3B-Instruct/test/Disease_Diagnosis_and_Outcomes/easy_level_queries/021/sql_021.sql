WITH cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND (
      -- Hemorrhagic stroke: ICD-9 codes
      (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432'))
      OR
      -- Hemorrhagic stroke: ICD-10 codes
      (d.icd_version = 10 AND d.icd_code IN ('I60', 'I61', 'I62'))
      OR
      -- Fallback: text match
      LOWER(d_icd.long_title) LIKE '%hemorrhagic stroke%'
    )
    AND (
      -- COPD exacerbation: ICD-9
      (d.icd_version = 9 AND d.icd_code = '491.21')
      OR
      -- COPD exacerbation: ICD-10
      (d.icd_version = 10 AND d.icd_code = 'J44.1')
      OR
      -- Fallback: text match
      LOWER(d_icd.long_title) LIKE '%exacerbation of chronic obstructive pulmonary disease%'
      OR LOWER(d_icd.long_title) LIKE '%copd exacerbation%'
    )
),
filtered_cohort AS (
  -- Ensure each hadm_id has BOTH conditions
  SELECT hadm_id, los
  FROM cohort
  GROUP BY hadm_id, los
  HAVING COUNT(*) >= 2  -- at least one row for stroke and one for COPD exacerbation
)
SELECT
  (SELECT APPROX_QUANTILES(los, 100)[OFFSET(75)] FROM filtered_cohort) - 
  (SELECT APPROX_QUANTILES(los, 100)[OFFSET(25)] FROM filtered_cohort) AS iqr_los;
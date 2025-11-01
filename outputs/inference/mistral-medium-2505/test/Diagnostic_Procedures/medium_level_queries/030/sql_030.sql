WITH
-- Get female patients aged 53-63
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 53 AND 63
),

-- Get admissions with upper GI bleeding and 1-8 day stays
upper_gi_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN female_patients fp ON a.subject_id = fp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  WHERE
    -- Upper GI bleeding ICD codes (K25-K28 or K92.0-K92.2)
    (di.icd_code LIKE 'K25%' OR di.icd_code LIKE 'K26%' OR di.icd_code LIKE 'K27%'
     OR di.icd_code LIKE 'K28%' OR di.icd_code LIKE 'K92.0%' OR di.icd_code LIKE 'K92.1%'
     OR di.icd_code LIKE 'K92.2%')
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
    AND a.hospital_expire_flag = 0  -- Exclude patients who died in hospital
),

-- Count diagnostic procedures per admission
procedure_counts AS (
  SELECT
    uga.hadm_id,
    uga.los_days,
    COUNT(DISTINCT pi.icd_code) AS procedure_count
  FROM upper_gi_admissions uga
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi ON uga.hadm_id = pi.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip ON pi.icd_code = dip.icd_code
  WHERE
    -- Filter for diagnostic procedures (this is a simplified approach)
    -- In a real scenario, you'd need a more comprehensive list of diagnostic procedure codes
    dip.long_title LIKE '%diagnostic%' OR
    dip.long_title LIKE '%endoscopy%' OR
    dip.long_title LIKE '%imaging%' OR
    dip.long_title LIKE '%radiology%' OR
    dip.long_title LIKE '%biopsy%'
  GROUP BY uga.hadm_id, uga.los_days
),

-- Categorize by LOS duration
los_categories AS (
  SELECT
    hadm_id,
    procedure_count,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_category
  FROM procedure_counts
)

-- Calculate percentiles
SELECT
  los_category,
  APPROX_QUANTILES(procedure_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(procedure_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(procedure_count, 4)[OFFSET(3)] AS p75
FROM los_categories
GROUP BY los_category
ORDER BY los_category;
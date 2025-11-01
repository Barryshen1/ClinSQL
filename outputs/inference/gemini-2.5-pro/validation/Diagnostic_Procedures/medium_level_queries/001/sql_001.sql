WITH acs_admissions AS (
  -- Step 1: Identify ACS admissions and classify them as Primary or Secondary
  SELECT
    hadm_id,
    CASE
      WHEN MIN(seq_num) = 1
      THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_rank
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for Acute Coronary Syndrome
    (
      icd_version = 9
      AND (
        icd_code LIKE '410%' -- Acute Myocardial Infarction
        OR icd_code = '4111' -- Unstable Angina (code for 411.1)
      )
    )
    OR -- ICD-10 codes for Acute Coronary Syndrome
    (
      icd_version = 10
      AND (
        icd_code LIKE 'I21%' -- Acute Myocardial Infarction
        OR icd_code LIKE 'I22%' -- Subsequent MI
        OR icd_code = 'I200' -- Unstable Angina (code for I20.0)
      )
    )
  GROUP BY
    hadm_id
),
radiology_counts AS (
  -- Step 2: Count Radiography/CT procedures for each admission
  SELECT
    hadm_id,
    COUNT(*) AS radiology_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  -- CPT codes for Diagnostic Radiology (70010-79999) cover X-rays, CTs, MRIs, etc.
  WHERE
    hcpcs_cd BETWEEN '70010' AND '79999'
  GROUP BY
    hadm_id
)
-- Step 3: Combine, filter, and aggregate the data
SELECT
  acs.diagnosis_rank,
  CASE
    WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 4
    THEN '1-4 days'
    WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 5 AND 8
    THEN '5-8 days'
  END AS los_category,
  COUNT(DISTINCT adm.hadm_id) AS num_admissions,
  ROUND(AVG(COALESCE(rad.radiology_count, 0)), 2) AS mean_radiology_count,
  MIN(COALESCE(rad.radiology_count, 0)) AS min_radiology_count,
  MAX(COALESCE(rad.radiology_count, 0)) AS max_radiology_count
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON adm.subject_id = p.subject_id
INNER JOIN
  acs_admissions AS acs
  ON adm.hadm_id = acs.hadm_id
LEFT JOIN
  radiology_counts AS rad
  ON adm.hadm_id = rad.hadm_id
WHERE
  -- Filter for age at admission
  (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) + p.anchor_age BETWEEN 77 AND 87
  -- Filter for length of stay
  AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 8
GROUP BY
  diagnosis_rank,
  los_category
ORDER BY
  diagnosis_rank,
  los_category;
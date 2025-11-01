WITH
-- Step 1: Identify all hospital admissions for heart failure.
HFCohort AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for Heart Failure start with '428'
    (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428')
    OR
    -- ICD-10 codes for Heart Failure start with 'I50'
    (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50')
),

-- Step 2: Define the main cohort: male patients 59-69 with HF, and categorize their admissions.
AdmissionsWithFeatures AS (
  SELECT
    adm.hadm_id,
    CASE
      WHEN CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_category,
    -- If any ICU stay exists for this admission, flag as 'ICU'.
    MAX(CASE WHEN icu.stay_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END) AS icu_use
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN HFCohort AS hf
    ON adm.hadm_id = hf.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON adm.hadm_id = icu.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) BETWEEN 1 AND 8
  GROUP BY
    adm.hadm_id,
    los_category
),

-- Step 3: Create a reference list of HCPCS codes for Radiography/CT procedures.
RadiologyCodes AS (
  SELECT DISTINCT code
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE
    REGEXP_CONTAINS(LOWER(short_description), r'\b(ct|x-ray|xray|radiograph|radiologic exam)\b')
),

-- Step 4: Count the number of relevant imaging procedures for each admission in our cohort.
AdmissionProcedureCounts AS (
  SELECT
    a.los_category,
    a.icu_use,
    -- Count the radiology codes that joined successfully.
    -- The LEFT JOINs ensure that admissions with zero relevant procedures are kept and result in a count of 0.
    COUNT(rc.code) AS procedure_count
  FROM AdmissionsWithFeatures AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS h
    ON a.hadm_id = h.hadm_id
  LEFT JOIN RadiologyCodes AS rc
    ON h.hcpcs_cd = rc.code
  GROUP BY
    a.hadm_id,
    a.los_category,
    a.icu_use
)

-- Step 5: Calculate the 25th, 50th, and 75th percentiles of procedure counts for each group.
SELECT
  los_category,
  icu_use,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(25)] AS percentile_25,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(50)] AS percentile_50,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS percentile_75
FROM AdmissionProcedureCounts
GROUP BY
  los_category,
  icu_use
ORDER BY
  los_category,
  icu_use;
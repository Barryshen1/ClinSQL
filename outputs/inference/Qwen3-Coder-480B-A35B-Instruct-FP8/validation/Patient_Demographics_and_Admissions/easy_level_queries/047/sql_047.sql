WITH akf_patients AS (
  -- Step 1: Identify female patients aged 82–92 with AKI
  SELECT DISTINCT p.subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND dd.icd_code IN ('N17.9', '584.9') -- ICD-10 and ICD-9 codes for AKI
),

first_icu_stays AS (
  -- Step 2: Get first ICU stay for each hospital admission of these patients
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.los,
    ROW_NUMBER() OVER (PARTITION BY icu.hadm_id ORDER BY icu.intime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN akf_patients p
    ON icu.subject_id = p.subject_id
)

-- Step 3: Compute 25th percentile of ICU LOS for first ICU stays
SELECT
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_25th_percentile
FROM first_icu_stays
WHERE rn = 1;
WITH acs_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE adm.subject_id = diag.subject_id
        AND adm.hadm_id = diag.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '410%' OR diag.icd_code IN ('4111', '41181'))
          OR 
          (diag.icd_version = 10 AND diag.icd_code LIKE 'I20%' OR diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%' OR diag.icd_code LIKE 'I23%' OR diag.icd_code LIKE 'I24%')
        )
    )
),
troponin_tests AS (
  SELECT 
    lab.subject_id,
    lab.hadm_id,
    lab.charttime,
    lab.valuenum,
    lab.ref_range_upper,
    -- Compute ratio to upper reference limit (standardize across assays)
    lab.valuenum / lab.ref_range_upper AS troponin_ratio
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
  WHERE lab.itemid IN (51002, 51003, 51004)  -- Troponin T, I, T-high-sensitivity
    AND lab.valuenum IS NOT NULL
    AND lab.ref_range_upper IS NOT NULL
    AND lab.ref_range_upper > 0  -- Ensure valid reference range
),
acs_troponin AS (
  SELECT 
    acs.subject_id,
    acs.hadm_id,
    tt.troponin_ratio
  FROM acs_admissions acs
  INNER JOIN troponin_tests tt
    ON acs.subject_id = tt.subject_id
    AND acs.hadm_id = tt.hadm_id
    AND tt.charttime BETWEEN acs.admittime AND acs.dischtime  -- In-hospital labs only
),
peak_troponin_per_admission AS (
  SELECT 
    subject_id,
    hadm_id,
    MAX(troponin_ratio) AS peak_troponin_ratio
  FROM acs_troponin
  GROUP BY subject_id, hadm_id
)
SELECT 
  APPROX_QUANTILES(peak_troponin_ratio, 100)[OFFSET(75)] AS percentile_75_troponin_ratio
FROM peak_troponin_per_admission;
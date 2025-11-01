WITH sepsis_admissions AS (
  -- First, identify all unique hospital admissions (hadm_id) associated with a sepsis diagnosis.
  SELECT DISTINCT
    dx.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
    ON dx.icd_code = ddx.icd_code
    AND dx.icd_version = ddx.icd_version
  WHERE
    LOWER(ddx.long_title) LIKE '%sepsis%'
)

-- Now, find the platelet counts for the relevant cohort and calculate the 75th percentile.
SELECT
  -- APPROX_QUANTILES calculates approximate percentiles.
  -- We ask for 100 quantiles (percentiles) and select the 75th one.
  APPROX_QUANTILES(le.valuenum, 100)[OFFSET(75)] AS platelet_count_75th_percentile
FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
-- Join to get patient gender.
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON le.subject_id = pat.subject_id
-- Join to get hospital admission details like discharge time.
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  ON le.hadm_id = adm.hadm_id
-- Use an INNER JOIN with our CTE to filter for sepsis admissions only.
INNER JOIN sepsis_admissions AS sa
  ON le.hadm_id = sa.hadm_id
WHERE
  -- Filter for 'Platelet Count' (itemid = 51265).
  le.itemid = 51265
  -- Filter for male patients.
  AND pat.gender = 'M'
  -- Filter for lab results on the same calendar day as hospital discharge.
  AND DATE(le.charttime) = DATE(adm.dischtime)
  -- Ensure the platelet value is a valid number.
  AND le.valuenum IS NOT NULL;
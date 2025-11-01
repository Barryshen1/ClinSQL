WITH sepsis_admissions AS (
  -- First, find all hospital admissions (hadm_id) with a diagnosis of sepsis
  SELECT DISTINCT
    diag.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
    ON diag.icd_code = d_diag.icd_code
    AND diag.icd_version = d_diag.icd_version
  WHERE
    LOWER(d_diag.long_title) LIKE '%sepsis%'
), peak_platelets_per_admission AS (
  -- Next, find the peak platelet count for each male patient during their sepsis admission
  SELECT
    le.subject_id,
    le.hadm_id,
    MAX(le.valuenum) AS peak_platelet_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  -- Join with sepsis admissions to filter for the relevant hospital stays
  INNER JOIN
    sepsis_admissions AS sa
    ON le.hadm_id = sa.hadm_id
  -- Join with patients to filter for males
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pa
    ON le.subject_id = pa.subject_id
  WHERE
    pa.gender = 'M'
    -- itemid for Platelet Count
    AND le.itemid = 51265
    -- Ensure the value is a valid number
    AND le.valuenum IS NOT NULL
  GROUP BY
    le.subject_id,
    le.hadm_id
)
-- Finally, calculate the 75th percentile of all the peak platelet counts
SELECT
  APPROX_QUANTILES(peak_platelet_count, 100)[OFFSET(75)] AS p75_peak_platelet_count
FROM
  peak_platelets_per_admission;
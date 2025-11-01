WITH PatientCohort AS (
  -- First, define the cohort: Male patients, aged 90-100, admitted with a diagnosis of chest pain.
  SELECT DISTINCT
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code
    AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 90 AND 100
    AND LOWER(d_dx.long_title) LIKE '%chest pain%'
),

InitialTroponin AS (
  -- Second, find the first Troponin I measurement for each hospital admission.
  SELECT
    hadm_id,
    valuenum,
    ref_range_upper,
    -- Use ROW_NUMBER to find the first measurement per admission based on chart time
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE
    itemid = 51003 -- itemid for Troponin I
    AND valuenum IS NOT NULL -- Ensure the value is numeric
)

-- Finally, join the cohort with their initial, elevated troponin levels and calculate statistics.
SELECT
  APPROX_QUANTILES(it.valuenum, 100)[OFFSET(25)] AS troponin_i_p25,
  APPROX_QUANTILES(it.valuenum, 100)[OFFSET(50)] AS troponin_i_p50,
  APPROX_QUANTILES(it.valuenum, 100)[OFFSET(75)] AS troponin_i_p75,
  MIN(it.valuenum) AS troponin_i_min,
  MAX(it.valuenum) AS troponin_i_max
FROM
  InitialTroponin AS it
JOIN
  PatientCohort AS pc
  ON it.hadm_id = pc.hadm_id
WHERE
  it.rn = 1 -- Filter for the initial measurement only
  AND it.valuenum > it.ref_range_upper; -- Filter for elevated values;
WITH pneumonia_admissions AS (
  -- First, find all hospital admissions (hadm_id) with a diagnosis of pneumonia.
  SELECT DISTINCT dx.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code
    AND dx.icd_version = d_dx.icd_version
  WHERE
    LOWER(d_dx.long_title) LIKE '%pneumonia%'
),

first_icu_stays AS (
  -- Next, identify the first ICU stay for each male patient aged 43-53.
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.los,
    -- Rank ICU stays for each patient chronologically to find the first one.
    ROW_NUMBER() OVER(PARTITION BY pat.subject_id ORDER BY icu.intime ASC) AS stay_rank
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 43 AND 53
)

-- Finally, combine the two sets and calculate the 25th percentile LOS.
SELECT
  APPROX_QUANTILES(fs.los, 100)[OFFSET(25)] AS p25_los_days
FROM first_icu_stays AS fs
-- Join to ensure the first ICU stay occurred during a pneumonia-related hospital admission.
JOIN pneumonia_admissions AS pa
  ON fs.hadm_id = pa.hadm_id
WHERE
  -- Filter for only the first ICU stay for each patient.
  fs.stay_rank = 1;
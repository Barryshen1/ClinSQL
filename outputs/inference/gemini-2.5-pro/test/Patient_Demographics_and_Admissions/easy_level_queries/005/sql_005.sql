WITH dialysis_patients AS (
  -- Find all unique patients who have a recorded dialysis procedure
  SELECT DISTINCT pro.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pro
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
    ON pro.icd_code = d_proc.icd_code
    AND pro.icd_version = d_proc.icd_version
  WHERE
    LOWER(d_proc.long_title) LIKE '%dialysis%'
),

first_icu_stays AS (
  -- Rank ICU stays for each patient to identify the first one
  SELECT
    subject_id,
    los,
    ROW_NUMBER() OVER(PARTITION BY subject_id ORDER BY intime ASC) AS stay_rank
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
)

-- Final calculation for the target cohort
SELECT
  -- APPROX_QUANTILES(value, 4) returns an array: [min, 25th_percentile, median, 75th_percentile, max]
  -- IQR is the 75th percentile (offset 3) minus the 25th percentile (offset 1)
  APPROX_QUANTILES(f.los, 4)[OFFSET(3)] - APPROX_QUANTILES(f.los, 4)[OFFSET(1)] AS iqr_first_icu_los_days
FROM first_icu_stays AS f
-- Filter for patients with the correct demographic profile
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON f.subject_id = p.subject_id
-- Ensure the patients are part of the dialysis cohort
INNER JOIN dialysis_patients AS dp
  ON f.subject_id = dp.subject_id
WHERE
  f.stay_rank = 1 -- Only consider the first ICU stay
  AND p.gender = 'F' -- Female patients
  AND p.anchor_age BETWEEN 77 AND 87; -- Age between 77 and 87;
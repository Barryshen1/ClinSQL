WITH aki_admissions AS (
  -- Step 1: Identify hospital admissions with an AKI diagnosis
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code IN (
      SELECT
        icd_code
      FROM
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
      WHERE
        LOWER(long_title) LIKE '%acute kidney failure%'
        OR LOWER(long_title) LIKE '%acute kidney injury%'
    )
), first_icu_los AS (
  -- Step 2 & 3: Filter patients by demographics and find their first ICU stay LOS
  SELECT
    icu.los,
    -- Rank ICU stays chronologically for each patient
    ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS stay_rank
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  -- Filter for females aged 82-92 with an AKI diagnosis during their hospital stay
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 82 AND 92
    AND icu.hadm_id IN (
      SELECT hadm_id FROM aki_admissions
    )
)
-- Step 4: Calculate the 25th percentile of the first ICU stay LOS
SELECT
  APPROX_QUANTILES(los, 100) [OFFSET(25)] AS los_25th_percentile_days
FROM
  first_icu_los
WHERE
  stay_rank = 1;
WITH chest_pain_adms AS (
  -- Step 1: Identify all hospital admissions with a diagnosis related to 'chest pain'.
  SELECT DISTINCT
    dx.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code
    AND dx.icd_version = d_dx.icd_version
  WHERE
    LOWER(d_dx.long_title) LIKE '%chest pain%'
),

patient_cohort AS (
  -- Step 2: Filter the chest pain admissions to include only male patients aged 39-49.
  SELECT
    adm.subject_id,
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    adm.hadm_id IN (SELECT hadm_id FROM chest_pain_adms)
    AND pat.gender = 'M'
    AND pat.anchor_age BETWEEN 39 AND 49
),

initial_troponin AS (
  -- Step 3: For the filtered cohort, find the first Troponin T measurement for each admission.
  SELECT
    pc.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY pc.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM
    patient_cohort AS pc
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON pc.hadm_id = le.hadm_id
  WHERE
    le.itemid = 50912 -- ITEMID for 'Troponin T'
    AND le.valuenum IS NOT NULL -- Ensure the value is a number for calculations
),

categorized_troponin AS (
  -- Step 4: Categorize the initial troponin values based on clinical cutoffs.
  -- The unit for Troponin T (50912) is ng/mL.
  SELECT
    hadm_id,
    valuenum,
    CASE
      WHEN valuenum < 0.014
      THEN 'Normal'
      WHEN valuenum BETWEEN 0.014 AND 0.052
      THEN 'Borderline'
      WHEN valuenum > 0.052
      THEN 'Myocardial Injury'
      ELSE NULL
    END AS tnt_category
  FROM
    initial_troponin
  WHERE
    rn = 1 -- Keep only the first measurement
)

-- Step 5: Aggregate the results by category to compute the final statistics.
SELECT
  tnt_category,
  COUNT(hadm_id) AS count_admissions,
  SAFE_DIVIDE(COUNT(hadm_id) * 100.0, SUM(COUNT(hadm_id)) OVER ()) AS percentage_of_total,
  AVG(valuenum) AS mean_hs_tnt,
  APPROX_QUANTILES(valuenum, 2) [OFFSET (1)] AS median_hs_tnt,
  -- IQR = 75th percentile - 25th percentile
  (
    APPROX_QUANTILES(valuenum, 4) [OFFSET (3)] - APPROX_QUANTILES(valuenum, 4) [OFFSET (1)]
  ) AS iqr_hs_tnt
FROM
  categorized_troponin
WHERE
  tnt_category IS NOT NULL
GROUP BY
  tnt_category
ORDER BY
  -- Custom sort order for logical presentation
  CASE tnt_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
  END;
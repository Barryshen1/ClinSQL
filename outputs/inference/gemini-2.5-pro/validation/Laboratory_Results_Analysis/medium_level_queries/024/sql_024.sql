WITH p99_threshold AS (
  -- Step 1: Calculate the 99th percentile threshold for hs-Troponin T across all patients
  SELECT
    APPROX_QUANTILES(le.valuenum, 100)[OFFSET(99)] AS p99_val
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  WHERE
    le.itemid = 52554 -- hs-Troponin T
    AND le.valuenum IS NOT NULL
),
first_troponin AS (
  -- Step 2: Identify the first hs-Troponin T measurement for each hospital admission
  SELECT
    hadm_id,
    valuenum
  FROM
    (
      SELECT
        hadm_id,
        valuenum,
        ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
      FROM
        `physionet-data.mimiciv_3_1_hosp.labevents`
      WHERE
        itemid = 52554 -- hs-Troponin T
        AND valuenum IS NOT NULL
    )
  WHERE
    rn = 1
),
chest_pain_adms AS (
  -- Step 3: Identify hospital admissions with a diagnosis of 'chest pain'
  SELECT DISTINCT
    diag.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE
    LOWER(d_diag.long_title) LIKE '%chest pain%'
)
-- Step 4: Combine the filters and calculate final statistics
SELECT
  COUNT(DISTINCT pat.subject_id) AS number_of_patients,
  COUNT(DISTINCT adm.hadm_id) AS number_of_admissions,
  AVG(adm.hospital_expire_flag) * 100 AS in_hospital_mortality_rate_percent,
  MIN(ft.valuenum) AS min_first_troponin_in_cohort,
  AVG(ft.valuenum) AS avg_first_troponin_in_cohort,
  APPROX_QUANTILES(ft.valuenum, 100)[OFFSET(50)] AS median_first_troponin_in_cohort,
  MAX(ft.valuenum) AS max_first_troponin_in_cohort,
  p99.p99_val AS p99_troponin_t_threshold
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN
  chest_pain_adms AS cpa
  ON adm.hadm_id = cpa.hadm_id
INNER JOIN
  first_troponin AS ft
  ON adm.hadm_id = ft.hadm_id
CROSS JOIN
  p99_threshold AS p99
WHERE
  -- Filter for male patients aged 64-74 at admission
  pat.gender = 'M'
  AND (
    pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year
  ) BETWEEN 64 AND 74
  -- Filter for patients whose first troponin exceeded the 99th percentile
  AND ft.valuenum > p99.p99_val
GROUP BY
  p99.p99_val;
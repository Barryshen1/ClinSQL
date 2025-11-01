WITH patient_cohort AS (
  -- Step 1: Identify male patients aged 76-86 admitted with AMI
  SELECT
    adm.subject_id,
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    -- Calculate age at admission and filter for the 76-86 range
    AND (
      pat.anchor_age + DATETIME_DIFF(adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR)
    ) BETWEEN 76 AND 86
    -- Filter for admissions that have an AMI diagnosis
    AND adm.hadm_id IN (
      SELECT DISTINCT
        dx.hadm_id
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
        ON dx.icd_code = ddx.icd_code
        AND dx.icd_version = ddx.icd_version
      WHERE
        ddx.long_title LIKE '%Acute myocardial infarction%'
    )
),
first_troponin AS (
  -- Step 2: Find the first Troponin I measurement for each admission in the cohort
  SELECT
    lab.hadm_id,
    lab.valuenum
  FROM
    (
      SELECT
        lab.hadm_id,
        lab.valuenum,
        ROW_NUMBER() OVER (PARTITION BY lab.hadm_id ORDER BY lab.charttime ASC) AS rn
      FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` AS lab
      INNER JOIN
        patient_cohort pc
        ON lab.hadm_id = pc.hadm_id
      WHERE
        lab.itemid = 51003 -- Troponin I
        AND lab.valuenum IS NOT NULL
    ) AS lab
  WHERE
    lab.rn = 1
),
categorized_troponin AS (
  -- Step 3: Categorize the first troponin values
  SELECT
    hadm_id,
    valuenum,
    CASE
      WHEN valuenum <= 0.04
      THEN 'Normal (<= 0.04 ng/mL)'
      WHEN valuenum > 0.04 AND valuenum <= 0.40
      THEN 'Borderline (0.04-0.40 ng/mL)'
      WHEN valuenum > 0.40
      THEN 'Elevated (> 0.40 ng/mL)'
    END AS troponin_category
  FROM
    first_troponin
),
overall_stats AS (
  -- Step 4: Calculate overall summary statistics for the entire cohort
  SELECT
    AVG(valuenum) AS mean_troponin,
    APPROX_QUANTILES(valuenum, 100) AS quantiles
  FROM
    first_troponin
)
-- Final Step: Present the categorical distribution along with the overall statistics
SELECT
  ct.troponin_category,
  COUNT(ct.hadm_id) AS count_admissions,
  ROUND(COUNT(ct.hadm_id) * 100.0 / SUM(COUNT(ct.hadm_id)) OVER (), 2) AS percentage_of_admissions,
  ROUND(s.mean_troponin, 4) AS overall_mean,
  ROUND(s.quantiles[OFFSET(50)], 4) AS overall_median,
  ROUND(s.quantiles[OFFSET(75)] - s.quantiles[OFFSET(25)], 4) AS overall_iqr
FROM
  categorized_troponin AS ct
CROSS JOIN
  overall_stats AS s
WHERE
  ct.troponin_category IS NOT NULL
GROUP BY
  ct.troponin_category,
  s.mean_troponin,
  s.quantiles
ORDER BY
  MIN(ct.valuenum);
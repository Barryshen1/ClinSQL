WITH icu_cohort AS (
  -- Step 1: Select female ICU patients aged 48-58
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    pat.anchor_age,
    pat.anchor_year
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND (
      pat.anchor_age + DATETIME_DIFF(icu.intime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR)
    ) BETWEEN 48 AND 58
),

stay_avg_hr AS (
  -- Step 2: Calculate average heart rate in the first 48 hours for each stay
  SELECT
    cohort.hadm_id,
    cohort.stay_id,
    AVG(ce.valuenum) AS avg_hr_48h
  FROM icu_cohort AS cohort
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON cohort.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220045 -- Heart Rate
    AND ce.charttime BETWEEN cohort.intime AND TIMESTAMP_ADD(cohort.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL AND ce.valuenum > 0 AND ce.valuenum < 300 -- Basic data cleaning
  GROUP BY
    cohort.hadm_id,
    cohort.stay_id
),

aki_admissions AS (
  -- Step 3: Identify hospital admissions with an AKI diagnosis
  SELECT DISTINCT
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code LIKE 'N17%' -- ICD-10 for Acute kidney failure
    OR icd_code LIKE '584%' -- ICD-9 for Acute kidney failure
),

categorized_stays AS (
  -- Step 4: Categorize stays by HR and flag for AKI
  SELECT
    hr.stay_id,
    CASE
      WHEN hr.avg_hr_48h < 60 THEN '<60'
      WHEN hr.avg_hr_48h BETWEEN 60 AND 99 THEN '60-99'
      WHEN hr.avg_hr_48h BETWEEN 100 AND 119 THEN '100-119'
      WHEN hr.avg_hr_48h >= 120 THEN '>=120'
    END AS hr_category,
    CASE
      WHEN aki.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS has_aki
  FROM stay_avg_hr AS hr
  LEFT JOIN aki_admissions AS aki
    ON hr.hadm_id = aki.hadm_id
)

-- Final Step: Calculate percent distribution and AKI rate per category
SELECT
  hr_category,
  COUNT(stay_id) * 100.0 / (SELECT COUNT(*) FROM categorized_stays) AS percent_distribution_of_stays,
  AVG(has_aki) * 100.0 AS aki_rate_by_category_percent
FROM categorized_stays
GROUP BY
  hr_category
ORDER BY
  CASE
    WHEN hr_category = '<60' THEN 1
    WHEN hr_category = '60-99' THEN 2
    WHEN hr_category = '100-119' THEN 3
    WHEN hr_category = '>=120' THEN 4
  END;
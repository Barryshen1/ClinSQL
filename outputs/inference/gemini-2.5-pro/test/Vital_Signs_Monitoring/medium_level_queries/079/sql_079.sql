WITH
-- Step 1: Identify ICU stays for male patients aged 40-50.
cohort_stays AS (
  SELECT
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON p.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),

-- Step 2: Get SBP measurements for the cohort within the first 48 hours of their ICU stay.
sbp_events AS (
  SELECT
    cs.stay_id,
    ce.valuenum
  FROM
    cohort_stays AS cs
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON cs.stay_id = ce.stay_id
  WHERE
    ce.itemid IN (
      220179, -- Non Invasive Blood Pressure systolic
      220050, -- Arterial Blood Pressure systolic
      225309  -- ART BP Systolic
    )
    AND ce.charttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0 AND ce.valuenum < 300 -- Exclude erroneous values
),

-- Step 3: Calculate the mean SBP per stay and assign a category.
-- This also implicitly filters for stays that have at least one SBP measurement.
mean_sbp_per_stay AS (
  SELECT
    s.stay_id,
    cs.hadm_id,
    CASE
      WHEN AVG(s.valuenum) < 140 THEN '<140 mmHg'
      WHEN AVG(s.valuenum) >= 140 AND AVG(s.valuenum) < 160 THEN '140-159 mmHg'
      WHEN AVG(s.valuenum) >= 160 THEN '>=160 mmHg'
    END AS sbp_category
  FROM
    sbp_events AS s
  INNER JOIN
    cohort_stays AS cs
    ON s.stay_id = cs.stay_id
  GROUP BY
    s.stay_id,
    cs.hadm_id
),

-- Step 4: Identify all hospital admissions with a diagnosis of Myocardial Infarction.
mi_admissions AS (
  SELECT DISTINCT
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for Acute Myocardial Infarction
    SUBSTR(icd_code, 1, 3) = '410'
    OR
    -- ICD-10 codes for Acute and Subsequent Myocardial Infarction
    SUBSTR(icd_code, 1, 3) IN ('I21', 'I22')
),

-- Step 5: Join SBP categories with MI diagnosis information for each stay.
stay_outcomes AS (
  SELECT
    ms.stay_id,
    ms.sbp_category,
    CASE
      WHEN mi.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS mi_flag
  FROM
    mean_sbp_per_stay AS ms
  LEFT JOIN
    mi_admissions AS mi
    ON ms.hadm_id = mi.hadm_id
)

-- Final Step: Aggregate results to get the count and percentages for each category.
SELECT
  so.sbp_category,
  -- Calculate the percentage of total stays that fall into this category
  (COUNT(so.stay_id) * 100.0) / SUM(COUNT(so.stay_id)) OVER () AS percent_of_total_stays,
  -- Calculate the MI rate (as a percentage) within this category
  (SUM(so.mi_flag) * 100.0) / COUNT(so.stay_id) AS mi_rate_percent
FROM
  stay_outcomes AS so
GROUP BY
  so.sbp_category
ORDER BY
  -- Order the categories logically from low to high SBP
  CASE
    WHEN so.sbp_category = '<140 mmHg' THEN 1
    WHEN so.sbp_category = '140-159 mmHg' THEN 2
    WHEN so.sbp_category = '>=160 mmHg' THEN 3
  END;
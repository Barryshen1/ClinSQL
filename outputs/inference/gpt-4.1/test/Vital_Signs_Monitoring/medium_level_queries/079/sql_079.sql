WITH sbp_items AS (
  -- Get itemids for Systolic Blood Pressure from d_items
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%' AND LOWER(label) LIKE '%blood pressure%'
),
cohort AS (
  -- Male ICU stays age 40-50
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 40 AND 50
),
sbp_48h AS (
  -- SBP measurements in first 48h of ICU stay
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    ce.charttime,
    ce.valuenum
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  JOIN sbp_items si
    ON ce.itemid = si.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
),
mean_sbp_per_stay AS (
  -- Compute mean SBP per ICU stay
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    AVG(valuenum) AS mean_sbp
  FROM sbp_48h
  GROUP BY subject_id, hadm_id, stay_id
),
sbp_categorized AS (
  -- Categorize mean SBP
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    mean_sbp,
    CASE
      WHEN mean_sbp < 140 THEN '<140'
      WHEN mean_sbp >= 140 AND mean_sbp < 160 THEN '140-159'
      WHEN mean_sbp >= 160 THEN '>=160'
      ELSE NULL
    END AS sbp_category
  FROM mean_sbp_per_stay
  WHERE mean_sbp IS NOT NULL
),
mi_codes AS (
  -- MI ICD codes (ICD-9 and ICD-10)
  SELECT '410' AS icd_code_prefix, 9 AS icd_version UNION ALL
  SELECT '4110', 9 UNION ALL
  SELECT '412', 9 UNION ALL
  SELECT 'I21', 10 UNION ALL
  SELECT 'I22', 10 UNION ALL
  SELECT 'I23', 10 UNION ALL
  SELECT 'I24', 10 UNION ALL
  SELECT 'I25', 10
),
mi_stays AS (
  -- ICU stays with MI diagnosis in hospital admission
  SELECT DISTINCT
    s.subject_id,
    s.hadm_id,
    s.stay_id
  FROM sbp_categorized s
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON s.hadm_id = d.hadm_id
  JOIN mi_codes m
    ON d.icd_version = m.icd_version
    AND (
      -- For ICD-9, match first 3 or 4 digits
      (m.icd_version = 9 AND (LEFT(d.icd_code, LENGTH(m.icd_code_prefix)) = m.icd_code_prefix))
      -- For ICD-10, match first 3 digits (I21, I22, I23, I24, I25)
      OR (m.icd_version = 10 AND LEFT(d.icd_code, LENGTH(m.icd_code_prefix)) = m.icd_code_prefix)
    )
),
final AS (
  -- Combine SBP category and MI flag
  SELECT
    s.sbp_category,
    s.stay_id,
    CASE WHEN mi.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_mi
  FROM sbp_categorized s
  LEFT JOIN mi_stays mi
    ON s.subject_id = mi.subject_id
    AND s.hadm_id = mi.hadm_id
    AND s.stay_id = mi.stay_id
  WHERE s.sbp_category IS NOT NULL
)
SELECT
  sbp_category,
  COUNT(*) AS n_stays,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percent_stays,
  SUM(has_mi) AS n_mi,
  ROUND(SUM(has_mi) * 100.0 / COUNT(*), 1) AS percent_mi
FROM final
GROUP BY sbp_category
ORDER BY
  CASE sbp_category
    WHEN '<140' THEN 1
    WHEN '140-159' THEN 2
    WHEN '>=160' THEN 3
    ELSE 4
  END;
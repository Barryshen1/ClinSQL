WITH sbp_itemids AS (
  -- Find SBP itemids from d_items
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%' AND LOWER(label) LIKE '%blood pressure%'
),

female_icu_70_80 AS (
  -- Get female ICU stays age 70-80
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 70 AND 80
),

sbp_first24h AS (
  -- Get max SBP in first 24h of ICU stay
  SELECT
    f.stay_id,
    f.hadm_id,
    MAX(c.valuenum) AS max_sbp
  FROM female_icu_70_80 f
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON f.stay_id = c.stay_id
  WHERE c.itemid IN (SELECT itemid FROM sbp_itemids)
    AND c.valuenum IS NOT NULL
    AND c.charttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 24 HOUR)
  GROUP BY f.stay_id, f.hadm_id
),

stroke_hadm AS (
  -- Identify admissions with stroke diagnosis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (
    -- ICD-10 stroke codes
    (d.icd_version = 10 AND (
      SAFE_CAST(SUBSTR(d.icd_code, 1, 3) AS STRING) IN ('I60', 'I61', 'I63', 'I64')
    ))
    -- ICD-9 stroke codes (optional, for completeness)
    OR (d.icd_version = 9 AND (
      SAFE_CAST(SUBSTR(d.icd_code, 1, 3) AS STRING) IN ('430', '431', '434', '436')
    ))
  )
),

sbp_categorized AS (
  -- Categorize SBP and flag stroke
  SELECT
    s.stay_id,
    s.hadm_id,
    s.max_sbp,
    CASE
      WHEN s.max_sbp < 130 THEN '<130'
      WHEN s.max_sbp >= 130 AND s.max_sbp < 140 THEN '130-139'
      WHEN s.max_sbp >= 140 AND s.max_sbp < 160 THEN '140-159'
      WHEN s.max_sbp >= 160 THEN '≥160'
      ELSE 'Unknown'
    END AS sbp_category,
    CASE WHEN sh.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS stroke_flag
  FROM sbp_first24h s
  LEFT JOIN stroke_hadm sh
    ON s.hadm_id = sh.hadm_id
)

SELECT
  sbp_category,
  COUNT(*) AS n_patients,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percent_patients,
  SUM(stroke_flag) AS n_stroke,
  ROUND(SUM(stroke_flag) * 100.0 / COUNT(*), 1) AS stroke_rate_percent
FROM sbp_categorized
WHERE sbp_category != 'Unknown'
GROUP BY sbp_category
ORDER BY
  CASE sbp_category
    WHEN '<130' THEN 1
    WHEN '130-139' THEN 2
    WHEN '140-159' THEN 3
    WHEN '≥160' THEN 4
    ELSE 5
  END;
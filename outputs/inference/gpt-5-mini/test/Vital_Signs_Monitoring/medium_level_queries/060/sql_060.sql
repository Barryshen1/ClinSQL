WITH
-- identify SBP-related itemids from ICU d_items
sbp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
),

-- cohort of ICU stays for female patients age 70-80
cohort_stays AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
),

-- maximum SBP per stay in the first 24 hours
stay_max_sbp AS (
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM cohort_stays cs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = cs.stay_id
  JOIN sbp_items si
    ON ce.itemid = si.itemid
  WHERE ce.valuenum IS NOT NULL
    -- restrict to first 24 hours of ICU stay
    AND ce.charttime BETWEEN cs.intime AND TIMESTAMP_ADD(cs.intime, INTERVAL 24 HOUR)
  GROUP BY cs.subject_id, cs.hadm_id, cs.stay_id
),

-- admissions flagged for stroke based on diagnosis descriptions
stroke_icd_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    LOWER(long_title) LIKE '%stroke%'
    OR LOWER(long_title) LIKE '%cva%'
    OR LOWER(long_title) LIKE '%cerebrovascular%'
    OR LOWER(long_title) LIKE '%intracerebral%'
    OR LOWER(long_title) LIKE '%cerebral infarct%'
  )
),

stroke_by_admission AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN stroke_icd_codes s
    ON d.icd_code = s.icd_code
   AND d.icd_version = s.icd_version
),

-- combine stays with SBP and stroke flag; exclude stays without SBP in first 24h
stays_with_cat AS (
  SELECT
    s.stay_id,
    s.hadm_id,
    s.max_sbp,
    CASE
      WHEN s.max_sbp < 130 THEN '<130'
      WHEN s.max_sbp BETWEEN 130 AND 139 THEN '130-139'
      WHEN s.max_sbp BETWEEN 140 AND 159 THEN '140-159'
      ELSE '>=160'
    END AS sbp_category,
    CASE WHEN st.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS stroke_flag
  FROM stay_max_sbp s
  LEFT JOIN stroke_by_admission st
    ON s.hadm_id = st.hadm_id
)

-- final aggregation: counts, percents, and stroke rates
SELECT
  sbp_category,
  COUNT(1) AS category_count,
  ROUND(100.0 * COUNT(1) / SUM(COUNT(1)) OVER (), 2) AS percent_of_cohort,
  SUM(stroke_flag) AS stroke_count,
  ROUND(100.0 * SUM(stroke_flag) / NULLIF(COUNT(1), 0), 2) AS stroke_rate_pct
FROM stays_with_cat
GROUP BY sbp_category
ORDER BY
  -- order categories in clinical ascending SBP
  CASE sbp_category
    WHEN '<130' THEN 1
    WHEN '130-139' THEN 2
    WHEN '140-159' THEN 3
    WHEN '>=160' THEN 4
    ELSE 5
  END;
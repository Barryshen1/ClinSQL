WITH sbp_itemids AS (
  -- Identify all itemids for Systolic BP
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%' AND LOWER(label) LIKE '%blood%'
),

female_icu_stays AS (
  -- Get all ICU stays for female patients aged 75-85
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
    AND pat.anchor_age BETWEEN 75 AND 85
),

sbp_first48 AS (
  -- Get all SBP measurements in first 48h of each ICU stay
  SELECT
    s.stay_id,
    ce.charttime,
    ce.valuenum
  FROM female_icu_stays s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON s.stay_id = ce.stay_id
  WHERE ce.itemid IN (SELECT itemid FROM sbp_itemids)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
),

mean_sbp_per_stay AS (
  -- Calculate mean SBP per ICU stay
  SELECT
    stay_id,
    AVG(valuenum) AS mean_sbp
  FROM sbp_first48
  GROUP BY stay_id
  HAVING COUNT(valuenum) > 0
),

percentile AS (
  -- Calculate percentile for mean SBP <= 140 mmHg
  SELECT
    COUNTIF(mean_sbp <= 140) AS num_le_140,
    COUNT(*) AS total_stays
  FROM mean_sbp_per_stay
)

SELECT
  SAFE_DIVIDE(num_le_140, total_stays) * 100 AS percentile_140_mmHg
FROM percentile;
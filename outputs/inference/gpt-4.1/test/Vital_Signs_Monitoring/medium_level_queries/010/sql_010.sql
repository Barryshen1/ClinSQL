WITH sbp_itemids AS (
  -- Systolic BP itemids from d_items
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%' AND LOWER(label) LIKE '%blood pressure%'
),
female_elderly_icu_stays AS (
  -- ICU stays for female patients aged 77-87 at ICU admission
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    pat.gender,
    -- Calculate age at ICU admission
    pat.anchor_age + EXTRACT(YEAR FROM icu.intime) - pat.anchor_year AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND (pat.anchor_age + EXTRACT(YEAR FROM icu.intime) - pat.anchor_year) BETWEEN 77 AND 87
),
sbp_per_stay AS (
  -- For each ICU stay, compute mean SBP over first 48 hours
  SELECT
    s.stay_id,
    AVG(c.valuenum) AS mean_sbp_48h
  FROM female_elderly_icu_stays s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.stay_id = c.stay_id
  WHERE c.itemid IN (SELECT itemid FROM sbp_itemids)
    AND c.valuenum IS NOT NULL
    AND c.charttime >= s.intime
    AND c.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
  GROUP BY s.stay_id
),
percentile AS (
  -- Calculate percentile of 160 mmHg among mean SBP values
  SELECT
    COUNTIF(mean_sbp_48h <= 160) AS num_le_160,
    COUNT(*) AS total_stays
  FROM sbp_per_stay
)
SELECT
  SAFE_DIVIDE(num_le_160, total_stays) * 100 AS percentile_160mmHg
FROM percentile;
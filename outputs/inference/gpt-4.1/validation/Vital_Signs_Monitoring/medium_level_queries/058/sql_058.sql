WITH systolic_bp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%' AND LOWER(label) LIKE '%blood pressure%'
),

female_icu_stays AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 38 AND 48
),

bp_first24h AS (
  SELECT
    ce.stay_id,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN female_icu_stays fs
    ON ce.stay_id = fs.stay_id
  JOIN systolic_bp_itemids sbi
    ON ce.itemid = sbi.itemid
  WHERE ce.charttime >= fs.intime
    AND ce.charttime < TIMESTAMP_ADD(fs.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
),

avg_bp_per_stay AS (
  SELECT
    stay_id,
    AVG(valuenum) AS avg_sbp
  FROM bp_first24h
  GROUP BY stay_id
)

SELECT
  COUNTIF(avg_sbp <= 120) AS stays_leq_120,
  COUNT(*) AS total_stays,
  SAFE_DIVIDE(COUNTIF(avg_sbp <= 120), COUNT(*)) * 100 AS percentile_120mmHg
FROM avg_bp_per_stay;
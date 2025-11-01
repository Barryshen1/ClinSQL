WITH systolic_bp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%' AND LOWER(label) LIKE '%blood%'
),

female_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 87 AND 97
),

bp_first24h AS (
  SELECT
    c.stay_id,
    AVG(c.valuenum) AS avg_sbp_24h
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN female_icu_stays s
    ON c.stay_id = s.stay_id
  INNER JOIN systolic_bp_items i
    ON c.itemid = i.itemid
  WHERE c.valuenum IS NOT NULL
    AND c.valuenum > 0
    AND c.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  GROUP BY c.stay_id
),

percentile_calc AS (
  SELECT
    COUNTIF(avg_sbp_24h <= 150) AS num_le_150,
    COUNT(*) AS total_stays
  FROM bp_first24h
)

SELECT
  num_le_150,
  total_stays,
  SAFE_DIVIDE(num_le_150, total_stays) * 100 AS percentile_150mmHg
FROM percentile_calc;
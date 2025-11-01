WITH sbp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%' 
    AND LOWER(label) LIKE '%blood pressure%'
),
cohort_sbp AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    p.gender,
    p.anchor_age,
    AVG(ce.valuenum) AS avg_sbp_24h
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND ce.itemid IN (SELECT itemid FROM sbp_items)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 30 AND 300
    AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
  GROUP BY ie.subject_id, ie.hadm_id, ie.stay_id, p.gender, p.anchor_age
),
percentile_calc AS (
  SELECT
    COUNTIF(avg_sbp_24h <= 150) AS num_le,
    COUNT(*) AS total_n
  FROM cohort_sbp
)
SELECT
  num_le,
  total_n,
  SAFE_DIVIDE(num_le, total_n) * 100 AS percentile_150
FROM percentile_calc;
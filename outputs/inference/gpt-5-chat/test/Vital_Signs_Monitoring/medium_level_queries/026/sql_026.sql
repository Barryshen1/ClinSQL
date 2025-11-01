WITH rr_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
),
cohort_rr AS (
  SELECT
    ie.stay_id,
    ie.subject_id,
    AVG(ce.valuenum) AS avg_rr
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
    ON p.subject_id = ie.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
  JOIN rr_itemids ri
    ON ce.itemid = ri.itemid
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= ie.intime
    AND ce.charttime < TIMESTAMP_ADD(ie.intime, INTERVAL 48 HOUR)
  GROUP BY ie.stay_id, ie.subject_id
),
percentile_calc AS (
  SELECT
    COUNTIF(avg_rr <= 12) / COUNT(*) * 100 AS percentile_12
  FROM cohort_rr
)
SELECT percentile_12
FROM percentile_calc;
WITH hr_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'heart rate'
),
cohort_avg AS (
  SELECT
    p.subject_id,
    icu.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id
    AND icu.stay_id = ce.stay_id
  JOIN hr_itemids hri
    ON ce.itemid = hri.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
    AND ce.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY p.subject_id, icu.stay_id
)
SELECT
  COUNTIF(avg_hr <= 110) / COUNT(*) * 100 AS percentile_110
FROM cohort_avg;
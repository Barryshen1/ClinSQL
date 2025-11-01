WITH female_80_90 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 80 AND 90
),
icu_stays AS (
  SELECT stay_id, subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE subject_id IN (SELECT subject_id FROM female_80_90)
),
heart_rate_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'heart rate'
  LIMIT 1
),
stay_avg_hr AS (
  SELECT
    icu_stays.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM icu_stays
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu_stays.subject_id = ce.subject_id
    AND icu_stays.stay_id = ce.stay_id
  JOIN heart_rate_itemid hri
    ON ce.itemid = hri.itemid
  WHERE ce.valuenum IS NOT NULL
  GROUP BY icu_stays.stay_id
)
SELECT
  COUNTIF(avg_hr <= 110) / COUNT(*) AS percentile_110_bpm
FROM stay_avg_hr
WHERE avg_hr IS NOT NULL;
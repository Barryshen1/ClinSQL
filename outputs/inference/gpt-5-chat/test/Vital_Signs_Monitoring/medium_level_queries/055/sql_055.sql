WITH spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
    AND linksto = 'chartevents'
),
female_icu AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
),
firstday_spo2 AS (
  SELECT
    c.stay_id,
    AVG(c.valuenum) AS mean_spo2
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN female_icu fi
    ON c.stay_id = fi.stay_id
   AND c.charttime >= fi.intime
   AND c.charttime < DATETIME_ADD(fi.intime, INTERVAL 24 HOUR)
  JOIN spo2_items si
    ON c.itemid = si.itemid
  WHERE c.valuenum IS NOT NULL
    AND c.valuenum > 0
    AND c.valuenum <= 100
  GROUP BY c.stay_id
),
percentile_calc AS (
  SELECT
    COUNTIF(mean_spo2 <= 88) / COUNT(*) * 100 AS percentile_88
  FROM firstday_spo2
)
SELECT percentile_88
FROM percentile_calc;
WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 87 AND 97
),
spo2_itemids AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE LOWER(label) LIKE '%spo2%'
),
spo2_first24h AS (
  SELECT
    c.stay_id,
    ce.charttime,
    ce.valuenum
  FROM cohort c
  JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON c.stay_id = ce.stay_id
  JOIN spo2_itemids s
    ON ce.itemid = s.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
),
stay_avg_spo2 AS (
  SELECT
    stay_id,
    AVG(valuenum) AS avg_spo2
  FROM spo2_first24h
  GROUP BY stay_id
)
SELECT
  COUNTIF(avg_spo2 <= 88) / COUNT(*) AS percentile_88_spo2
FROM stay_avg_spo2;
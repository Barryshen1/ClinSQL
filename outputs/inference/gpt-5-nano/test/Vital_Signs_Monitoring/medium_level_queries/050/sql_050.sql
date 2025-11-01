WITH hr_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%' OR LOWER(label) LIKE '%hr%'
),
stays_filtered AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pat.subject_id = icu.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 67 AND 77
),
hr_readings AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    ch.charttime,
    ch.valuenum
  FROM stays_filtered AS s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ch
    ON ch.stay_id = s.stay_id
   AND ch.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  WHERE ch.itemid IN (SELECT itemid FROM hr_itemids)
    AND ch.valuenum IS NOT NULL
),
per_stay AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    AVG(valuenum) AS hr_avg_24h
  FROM hr_readings
  GROUP BY stay_id, subject_id, hadm_id
)
SELECT
  100.0 * SUM(CASE WHEN hr_avg_24h <= 110 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_of_110
FROM per_stay;
WITH hr_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
),
female_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 67 AND 77
),
hr_first24h AS (
  SELECT
    c.subject_id,
    c.stay_id,
    c.charttime,
    c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN hr_itemids hri
    ON c.itemid = hri.itemid
  JOIN female_icu_stays fis
    ON c.subject_id = fis.subject_id
    AND c.stay_id = fis.stay_id
  WHERE c.valuenum IS NOT NULL
    AND c.charttime BETWEEN fis.intime AND DATETIME_ADD(fis.intime, INTERVAL 24 HOUR)
),
avg_hr_per_stay AS (
  SELECT
    subject_id,
    stay_id,
    AVG(valuenum) AS avg_hr
  FROM hr_first24h
  GROUP BY subject_id, stay_id
  HAVING COUNT(valuenum) > 0
)
SELECT
  ROUND(
    100.0 * SUM(CASE WHEN avg_hr < 110 THEN 1 ELSE 0 END) / COUNT(*),
    2
  ) AS percentile_110_bpm
FROM avg_hr_per_stay
WHERE avg_hr IS NOT NULL;
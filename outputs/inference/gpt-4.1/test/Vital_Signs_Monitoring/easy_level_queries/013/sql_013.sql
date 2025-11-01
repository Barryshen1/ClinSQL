WITH female_44_54 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 44 AND 54
),
icu_cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN female_44_54 f
    ON icu.subject_id = f.subject_id
),
heart_rate_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid IN (220045, 211) -- Heart Rate itemids
    AND ce.valuenum IS NOT NULL
)
SELECT
  icu.subject_id,
  icu.hadm_id,
  icu.stay_id,
  MIN(hr.valuenum) AS min_heart_rate_first_24hr
FROM icu_cohort icu
INNER JOIN heart_rate_events hr
  ON icu.subject_id = hr.subject_id
  AND icu.hadm_id = hr.hadm_id
  AND icu.stay_id = hr.stay_id
  AND hr.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
ORDER BY min_heart_rate_first_24hr ASC;
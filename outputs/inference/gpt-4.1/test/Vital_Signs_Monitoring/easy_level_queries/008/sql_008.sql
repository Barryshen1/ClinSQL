WITH male_52_62 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 52 AND 62
),
rr_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
),
icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN male_52_62 p ON i.subject_id = p.subject_id
),
rr_on_day2plus AS (
  SELECT
    c.subject_id,
    c.stay_id,
    c.charttime,
    c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN icu_stays s
    ON c.subject_id = s.subject_id
    AND c.stay_id = s.stay_id
  JOIN rr_items ri
    ON c.itemid = ri.itemid
  WHERE c.valuenum IS NOT NULL
    AND c.charttime >= TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
)
SELECT
  r.subject_id,
  r.stay_id,
  MAX(r.valuenum) AS max_respiratory_rate
FROM rr_on_day2plus r
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON r.subject_id = p.subject_id
WHERE p.anchor_age = 57
GROUP BY r.subject_id, r.stay_id
ORDER BY max_respiratory_rate DESC;
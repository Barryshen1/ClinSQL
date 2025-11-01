WITH sbp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) LIKE '%systolic%'
    AND LOWER(linksto) = 'chartevents'
),
icu_stays_with_age AS (
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
    AND i.intime IS NOT NULL
),
sbp_first_24h AS (
  SELECT 
    i.stay_id,
    AVG(ce.valuenum) AS avg_sbp_24h
  FROM icu_stays_with_age i
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON i.stay_id = ce.stay_id
  INNER JOIN sbp_itemids s
    ON ce.itemid = s.itemid
  WHERE ce.charttime >= i.intime
    AND ce.charttime < DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND i.age_at_admission >= 38
    AND i.age_at_admission <= 48
  GROUP BY i.stay_id
)
SELECT
  SUM(CASE WHEN avg_sbp_24h <= 120 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile_of_120
FROM sbp_first_24h;
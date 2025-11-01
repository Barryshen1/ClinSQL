WITH female_icu_stays AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    p.gender,
    (EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age) BETWEEN 42 AND 52
),
heart_rate_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'heart rate'
    AND LOWER(linksto) = 'chartevents'
),
stay_avg_hr AS (
  SELECT 
    c.stay_id,
    AVG(c.valuenum) AS avg_hr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN heart_rate_item hr ON c.itemid = hr.itemid
  JOIN female_icu_stays fis ON c.stay_id = fis.stay_id
  WHERE c.valuenum IS NOT NULL
    AND c.charttime >= fis.intime
    AND (c.charttime <= fis.outtime OR fis.outtime IS NULL)
  GROUP BY c.stay_id
)
SELECT 
  COUNT(*) AS cohort_size,
  ROUND(
    (SUM(CASE WHEN avg_hr < 90 THEN 1 ELSE 0 END) + 0.5 * SUM(CASE WHEN avg_hr = 90 THEN 1 ELSE 0 END)) * 100.0 / COUNT(*),
    2
  ) AS percentile_of_90_bpm
FROM stay_avg_hr;
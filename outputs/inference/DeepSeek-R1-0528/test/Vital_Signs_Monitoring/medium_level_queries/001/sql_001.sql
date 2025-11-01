WITH first_icu_stay AS (
  SELECT 
    p.subject_id,
    i.stay_id,
    i.intime,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) = 1
),
filtered_stays AS (
  SELECT 
    subject_id,
    stay_id,
    intime
  FROM first_icu_stay
  WHERE age_at_icu BETWEEN 45 AND 55
),
sbp_events AS (
  SELECT 
    fs.subject_id,
    fs.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM filtered_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.stay_id = ce.stay_id
    AND ce.itemid IN (220045, 220179)  -- SBP/IBP Systolic
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= fs.intime
    AND ce.charttime < DATETIME_ADD(fs.intime, INTERVAL 24 HOUR)
  GROUP BY fs.subject_id, fs.stay_id
  HAVING AVG(ce.valuenum) > 0  -- Exclude biologically implausible values
),
buckets AS (
  SELECT 
    subject_id,
    CASE 
      WHEN avg_sbp < 140 THEN '<140'
      WHEN avg_sbp BETWEEN 140 AND 159 THEN '140-159'
      WHEN avg_sbp >= 160 THEN '>=160'
    END AS sbp_bucket
  FROM sbp_events
)
SELECT 
  sbp_bucket,
  COUNT(DISTINCT subject_id) AS patient_count
FROM buckets
GROUP BY sbp_bucket
ORDER BY sbp_bucket;
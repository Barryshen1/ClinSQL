WITH cohort AS (
  SELECT 
    i.subject_id,
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 45 AND 55
),
sbp_measurements AS (
  SELECT 
    c.stay_id,
    c.subject_id,
    ce.valuenum AS sbp
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid IN (220050, 220179)  -- Primary SBP itemids
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime < c.intime + INTERVAL '24' HOUR
),
stay_avg AS (
  SELECT 
    stay_id,
    subject_id,
    AVG(sbp) AS avg_sbp
  FROM sbp_measurements
  GROUP BY stay_id, subject_id
  HAVING COUNT(sbp) > 0  -- Exclude stays with no measurements
)
SELECT 
  CASE 
    WHEN avg_sbp < 140 THEN '<140'
    WHEN avg_sbp < 160 THEN '140-159'  -- Covers 140 to 159.999...
    ELSE '>=160'
  END AS sbp_category,
  COUNT(DISTINCT subject_id) AS patient_count
FROM stay_avg
GROUP BY sbp_category
ORDER BY 
  CASE sbp_category
    WHEN '<140' THEN 1
    WHEN '140-159' THEN 2
    ELSE 3
  END;
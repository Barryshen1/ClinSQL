WITH cohort_stays AS (
  SELECT 
    icu.stay_id,
    icu.intime,
    -- Compute age at ICU admission
    pat.anchor_age + (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
),
filtered_stays AS (
  SELECT stay_id, intime
  FROM cohort_stays
  WHERE age BETWEEN 87 AND 97  -- Age filter applied after computation
),
sbp_per_stay AS (
  SELECT 
    fs.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM filtered_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (179, 220179)  -- Systolic BP item IDs
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 40 AND 300  -- Physiological range
    AND ce.charttime >= fs.intime
    AND ce.charttime < DATETIME_ADD(fs.intime, INTERVAL 24 HOUR)
  GROUP BY fs.stay_id
)
-- Calculate percentile for 150 mmHg
SELECT 
  (COUNTIF(avg_sbp <= 150) * 100.0) / COUNT(*) AS percentile
FROM sbp_per_stay;
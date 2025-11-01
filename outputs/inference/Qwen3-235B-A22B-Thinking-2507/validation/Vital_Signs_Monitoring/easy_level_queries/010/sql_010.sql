WITH dbp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%diastolic%'
    AND LOWER(label) NOT LIKE '%systolic%'
),
filtered_stays AS (
  SELECT 
    s.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM s.intime) - (p.anchor_year - p.anchor_age) BETWEEN 71 AND 81
),
dbp_measurements AS (
  SELECT 
    c.stay_id,
    c.valuenum AS dbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN dbp_items d 
    ON c.itemid = d.itemid
  WHERE c.valuenum IS NOT NULL
    AND c.stay_id IN (SELECT stay_id FROM filtered_stays)
),
per_stay_max AS (
  SELECT 
    stay_id,
    MAX(dbp) AS max_dbp
  FROM dbp_measurements
  GROUP BY stay_id
)
SELECT 
  APPROX_QUANTILES(max_dbp, 1000)[OFFSET(500)] AS median_max_dbp
FROM per_stay_max;
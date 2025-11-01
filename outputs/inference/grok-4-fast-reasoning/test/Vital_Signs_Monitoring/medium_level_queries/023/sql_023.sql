WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    i.hadm_id, 
    i.stay_id, 
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 62 AND 72
),
first_stays AS (
  SELECT *
  FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM cohort
  )
  WHERE rn = 1
),
aki AS (
  SELECT 
    fs.subject_id,
    CASE 
      WHEN LOGICAL_OR(icd_code LIKE '584%' OR icd_code LIKE 'N17%') THEN 1 
      ELSE 0 
    END AS has_aki
  FROM first_stays fs
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON fs.subject_id = d.subject_id 
    AND fs.hadm_id = d.hadm_id
  GROUP BY fs.subject_id
),
temps AS (
  SELECT 
    c.subject_id, 
    c.valuenum,
    CASE 
      WHEN c.valuenum < 36.0 THEN '<36.0'
      WHEN c.valuenum >= 36.0 AND c.valuenum <= 37.9 THEN '36.0–37.9'
      ELSE '>=38.0'
    END AS temp_category
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN first_stays fs
    ON c.stay_id = fs.stay_id
  WHERE c.itemid = 676
    AND c.valuenum IS NOT NULL
    AND c.charttime >= fs.intime
    AND c.charttime < TIMESTAMP_ADD(fs.intime, INTERVAL 24 HOUR)
),
temp_stats AS (
  SELECT 
    temp_category,
    COUNT(*) AS num_measurements,
    AVG(valuenum) AS mean_temp,
    APPROX_QUANTILES(valuenum, 5)[OFFSET(2)] AS median_temp,
    APPROX_QUANTILES(valuenum, 5)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 5)[OFFSET(1)] AS iqr_temp
  FROM temps
  GROUP BY temp_category
),
patient_categories AS (
  SELECT DISTINCT 
    subject_id, 
    temp_category
  FROM temps
),
aki_per_cat AS (
  SELECT 
    pc.temp_category,
    COUNT(DISTINCT pc.subject_id) AS num_patients,
    AVG(aki.has_aki) AS aki_rate
  FROM patient_categories pc
  INNER JOIN aki 
    ON pc.subject_id = aki.subject_id
  GROUP BY pc.temp_category
)
SELECT 
  ts.temp_category,
  ts.num_measurements,
  ROUND(ts.mean_temp, 2) AS mean_temp,
  ROUND(ts.median_temp, 2) AS median_temp,
  ROUND(ts.iqr_temp, 2) AS iqr_temp,
  ac.num_patients,
  ROUND(ac.aki_rate * 100, 2) AS aki_rate_percent
FROM temp_stats ts
LEFT JOIN aki_per_cat ac 
  ON ts.temp_category = ac.temp_category
ORDER BY 
  CASE temp_category
    WHEN '<36.0' THEN 1
    WHEN '36.0–37.9' THEN 2
    WHEN '>=38.0' THEN 3
  END;
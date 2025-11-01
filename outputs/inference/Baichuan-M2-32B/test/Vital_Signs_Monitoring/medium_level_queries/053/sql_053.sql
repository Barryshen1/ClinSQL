WITH patient_birth AS (
  SELECT 
    subject_id,
    gender,
    DATE_SUB(CAST(CONCAT(anchor_year, '-01-01') AS DATE), INTERVAL anchor_age YEAR) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
),
eligible_icu AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    p.birth_date,
    TIMESTAMP_DIFF(i.intime, p.birth_date, YEAR) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN patient_birth p
    ON i.subject_id = p.subject_id
  WHERE TIMESTAMP_DIFF(i.intime, p.birth_date, YEAR) BETWEEN 65 AND 75
),
sbp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE category = 'Vital Signs'
    AND (label LIKE '%Systolic BP%' OR label LIKE '%SBP%')
    AND unitname = 'mm Hg'
),
measurements AS (
  SELECT 
    e.stay_id,
    e.charttime,
    e.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` e
  INNER JOIN eligible_icu i
    ON e.subject_id = i.subject_id
    AND e.hadm_id = i.hadm_id
    AND e.stay_id = i.stay_id
  WHERE e.itemid IN (SELECT itemid FROM sbp_itemids)
    AND e.valuenum > 0
    AND e.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
),
categorized AS (
  SELECT 
    valuenum,
    CASE 
      WHEN valuenum < 140 THEN '<140'
      WHEN valuenum BETWEEN 140 AND 159 THEN '140-159'
      ELSE '>=160'
    END AS category
  FROM measurements
)
SELECT 
  category,
  mean_sbp,  -- Use the computed mean from the subquery
  q_array[OFFSET(50)] AS median_sbp,
  q_array[OFFSET(75)] - q_array[OFFSET(25)] AS iqr_sbp
FROM (
  SELECT 
    category,
    AVG(valuenum) AS mean_sbp,
    APPROX_QUANTILES(valuenum, 100) AS q_array
  FROM categorized
  GROUP BY category
)
ORDER BY 
  CASE category
    WHEN '<140' THEN 1
    WHEN '140-159' THEN 2
    WHEN '>=160' THEN 3
  END;
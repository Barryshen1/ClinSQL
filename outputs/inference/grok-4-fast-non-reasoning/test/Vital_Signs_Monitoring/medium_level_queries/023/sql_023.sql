WITH first_icu AS (
  SELECT *
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE first_careunit IS NOT NULL  -- Ensure valid ICU stay
  QUALIFY ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) = 1
),
patients_icu AS (
  SELECT 
    f.subject_id,
    f.stay_id,
    f.hadm_id,
    f.intime,
    p.gender,
    p.anchor_age
  FROM first_icu f
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON f.subject_id = p.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 62 AND 72
),
baseline_creat AS (
  SELECT 
    pi.subject_id,
    pi.stay_id,
    pi.intime,
    MIN(le.valuenum) AS baseline_creat
  FROM patients_icu pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON pi.subject_id = le.subject_id 
    AND pi.hadm_id = le.hadm_id
  WHERE le.itemid = 50912  -- Creatinine
    AND le.valuenum BETWEEN 0.1 AND 10
    AND le.charttime < pi.intime 
    AND le.charttime >= TIMESTAMP_SUB(pi.intime, INTERVAL 48 HOUR)
  GROUP BY pi.subject_id, pi.stay_id, pi.intime
  HAVING baseline_creat IS NOT NULL
),
post_creat AS (
  SELECT 
    pi.subject_id,
    pi.stay_id,
    MAX(le.valuenum) AS max_post_creat
  FROM patients_icu pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON pi.subject_id = le.subject_id 
    AND pi.hadm_id = le.hadm_id
  WHERE le.itemid = 50912
    AND le.valuenum BETWEEN 0.1 AND 10
    AND le.charttime >= pi.intime 
    AND le.charttime < TIMESTAMP_ADD(pi.intime, INTERVAL 48 HOUR)
  GROUP BY pi.subject_id, pi.stay_id
  HAVING max_post_creat IS NOT NULL
),
aki AS (
  SELECT 
    pi.subject_id,
    pi.stay_id,
    CASE 
      WHEN bc.baseline_creat IS NULL OR pc.max_post_creat IS NULL THEN NULL
      WHEN pc.max_post_creat >= bc.baseline_creat * 1.5 
        OR pc.max_post_creat >= bc.baseline_creat + 0.3 THEN 1
      ELSE 0 
    END AS has_aki
  FROM patients_icu pi
  LEFT JOIN baseline_creat bc ON pi.subject_id = bc.subject_id AND pi.stay_id = bc.stay_id
  LEFT JOIN post_creat pc ON pi.subject_id = pc.subject_id AND pi.stay_id = pc.stay_id
),
temps AS (
  SELECT 
    pi.*,
    ce.charttime,
    CASE 
      WHEN ce.itemid = 678 THEN (ce.valuenum - 32) * 5 / 9  -- F to C
      ELSE ce.valuenum 
    END AS temp_c
  FROM patients_icu pi
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON pi.subject_id = ce.subject_id 
    AND pi.hadm_id = ce.hadm_id 
    AND pi.stay_id = ce.stay_id
  WHERE ce.itemid IN (676, 678)  -- Temperature C or F
    AND ce.valuenum IS NOT NULL 
    AND ce.valuenum > 0
    AND ce.charttime >= pi.intime 
    AND ce.charttime < TIMESTAMP_ADD(pi.intime, INTERVAL 1 DAY)
    AND CASE 
      WHEN ce.itemid = 678 THEN (ce.valuenum - 32) * 5 / 9  -- F to C
      ELSE ce.valuenum 
    END BETWEEN 20 AND 45  -- Plausible range for temp_c
)
SELECT 
  CASE 
    WHEN temp_c < 36.0 THEN '<36.0'
    WHEN temp_c >= 36.0 AND temp_c < 38.0 THEN '36.0–37.9'
    ELSE '>=38.0'
  END AS temp_category,
  COUNT(*) AS n_measurements,
  ROUND(AVG(temp_c), 2) AS mean_temp_c,
  ROUND(APPROX_QUANTILES(temp_c, 4)[OFFSET(2)], 2) AS median_temp_c,
  ROUND(APPROX_QUANTILES(temp_c, 4)[OFFSET(1)], 2) AS q1_temp_c,
  ROUND(APPROX_QUANTILES(temp_c, 4)[OFFSET(3)], 2) AS q3_temp_c,
  ROUND(APPROX_QUANTILES(temp_c, 4)[OFFSET(3)] - APPROX_QUANTILES(temp_c, 4)[OFFSET(1)], 2) AS iqr_temp_c,
  -- AKI rate: average among patients with measurements in this category who have AKI data
  ROUND(AVG(CASE WHEN a.has_aki IS NOT NULL THEN a.has_aki ELSE NULL END), 3) AS aki_rate
FROM temps t
LEFT JOIN aki a ON t.subject_id = a.subject_id AND t.stay_id = a.stay_id
GROUP BY temp_category
ORDER BY 
  CASE temp_category
    WHEN '<36.0' THEN 1
    WHEN '36.0–37.9' THEN 2
    ELSE 3
  END;
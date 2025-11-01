WITH cohort AS (
  -- Define mixed shock patients: female, 60-70, with both vasopressors and inotropes in first 48h
  SELECT 
      ie.subject_id, 
      ie.hadm_id, 
      ie.stay_id,
      ie.intime,
      ie.outtime,
      ie.los,  -- Added los column
      p.anchor_age,
      adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON ie.hadm_id = adm.hadm_id
  WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 60 AND 70
  AND EXISTS (
      -- Vasopressors: norepinephrine (221906), epinephrine (221289), vasopressin (222315)
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` iv
      WHERE iv.subject_id = ie.subject_id
          AND iv.hadm_id = ie.hadm_id
          AND iv.stay_id = ie.stay_id
          AND iv.starttime >= ie.intime
          AND iv.starttime <= DATETIME_ADD(ie.intime, INTERVAL 48 HOUR)
          AND iv.itemid IN (221906, 221289, 222315)
  )
  AND EXISTS (
      -- Inotropes: dobutamine (221653), milrinone (221986)
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` iv
      WHERE iv.subject_id = ie.subject_id
          AND iv.hadm_id = ie.hadm_id
          AND iv.stay_id = ie.stay_id
          AND iv.starttime >= ie.intime
          AND iv.starttime <= DATETIME_ADD(ie.intime, INTERVAL 48 HOUR)
          AND iv.itemid IN (221653, 221986)
  )
),

vitals AS (
  -- Get MAP and HR measurements in first 48h
  SELECT 
      c.subject_id,
      c.stay_id,
      SUM(CASE WHEN ce.itemid = 220181 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_low_count,
      SUM(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS hr_high_count
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON c.subject_id = ce.subject_id
          AND c.stay_id = ce.stay_id
          AND ce.charttime >= c.intime
          AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  WHERE ce.itemid IN (220181, 220045)  -- MAP and HR
      AND ce.valuenum IS NOT NULL
  GROUP BY c.subject_id, c.stay_id
),

instability_scores AS (
  -- Compute instability score
  SELECT 
      c.*,
      v.map_low_count,
      v.hr_high_count,
      (v.map_low_count + v.hr_high_count) AS instability_score
  FROM cohort c
  INNER JOIN vitals v
      ON c.subject_id = v.subject_id AND c.stay_id = v.stay_id
),

percentiles AS (
  -- Compute 90th percentile
  SELECT 
      APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90
  FROM instability_scores
),

top_decile AS (
  -- Identify top decile patients
  SELECT 
      *,
      1 AS is_top_decile
  FROM instability_scores
  CROSS JOIN percentiles p
  WHERE instability_score >= p.p90
),

cohort_with_flag AS (
  -- Add flag for top decile
  SELECT 
      i.*,
      CASE WHEN t.subject_id IS NOT NULL THEN 1 ELSE 0 END AS is_top_decile
  FROM instability_scores i
  LEFT JOIN top_decile t
      ON i.subject_id = t.subject_id AND i.stay_id = t.stay_id
)

-- Compare top decile vs entire cohort
SELECT 
    'Entire cohort' AS group_label,
    COUNT(*) AS n_patients,
    ROUND(100.0 * SUM(CASE WHEN map_low_count > 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS percent_with_hypotension,
    ROUND(100.0 * SUM(CASE WHEN hr_high_count > 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS percent_with_tachycardia,
    ROUND(APPROX_QUANTILES(los, 100)[OFFSET(50)], 2) AS median_icu_los,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_percent
FROM cohort_with_flag
UNION ALL
SELECT 
    'Top decile' AS group_label,
    COUNT(*) AS n_patients,
    ROUND(100.0 * SUM(CASE WHEN map_low_count > 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS percent_with_hypotension,
    ROUND(100.0 * SUM(CASE WHEN hr_high_count > 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS percent_with_tachycardia,
    ROUND(APPROX_QUANTILES(los, 100)[OFFSET(50)], 2) AS median_icu_los,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_percent
FROM cohort_with_flag
WHERE is_top_decile = 1;
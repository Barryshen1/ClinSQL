WITH cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age_at_icu_adm,
    p.gender,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  WHERE p.gender = 'M'
),
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE age_at_icu_adm BETWEEN 70 AND 80
),
rrt_patients AS (
  SELECT DISTINCT ie.stay_id
  FROM filtered_cohort ie
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON ie.stay_id = pe.stay_id
  WHERE pe.itemid IN (225441, 225802, 225803, 225805, 225809)
),
cohort_with_rrt AS (
  SELECT 
    fc.*,
    CASE WHEN rrt.stay_id IS NOT NULL THEN 1 ELSE 0 END AS rrt_flag
  FROM filtered_cohort fc
  LEFT JOIN rrt_patients rrt
    ON fc.stay_id = rrt.stay_id
),
vitals AS (
  SELECT 
    ce.stay_id,
    MIN(CASE WHEN ce.itemid IN (220052, 220181, 225312, 220179) THEN ce.valuenum END) AS min_map,
    MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum END) AS max_hr,
    MIN(CASE WHEN ce.itemid = 220045 THEN ce.valuenum END) AS min_hr,
    MAX(CASE WHEN ce.itemid IN (220210, 224688, 224689, 224690) THEN ce.valuenum END) AS max_rr,
    MIN(CASE WHEN ce.itemid IN (220210, 224688, 224689, 224690) THEN ce.valuenum END) AS min_rr,
    MAX(CASE 
        WHEN ce.itemid IN (223762, 220739) THEN ce.valuenum 
        WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5/9 
    END) AS max_temp_c,
    MIN(CASE 
        WHEN ce.itemid IN (223762, 220739) THEN ce.valuenum 
        WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5/9 
    END) AS min_temp_c,
    MIN(CASE WHEN ce.itemid = 220277 THEN ce.valuenum END) AS min_spo2
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort_with_rrt cwr
    ON ce.stay_id = cwr.stay_id
    AND ce.charttime BETWEEN cwr.intime AND DATETIME_ADD(cwr.intime, INTERVAL 48 HOUR)
  WHERE ce.itemid IN (
    220052, 220181, 225312, 220179,  -- MAP
    220045,  -- HR
    220210, 224688, 224689, 224690,  -- RR
    223762, 220739, 223761,  -- Temp
    220277  -- SpO2
  )
  AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
scores AS (
  SELECT 
    v.stay_id,
    v.min_map,
    v.max_hr,
    v.min_hr,
    v.max_rr,
    v.min_rr,
    v.max_temp_c,
    v.min_temp_c,
    v.min_spo2,
    CASE 
      WHEN v.min_map < 40 THEN 4
      WHEN v.min_map < 55 THEN 3
      WHEN v.min_map < 65 THEN 2
      WHEN v.min_map < 70 THEN 1
      ELSE 0
    END AS map_score,
    GREATEST(
      CASE 
        WHEN v.max_hr >= 130 THEN 3
        WHEN v.max_hr >= 110 THEN 2
        WHEN v.max_hr >= 100 THEN 1
        ELSE 0
      END,
      CASE 
        WHEN v.min_hr <= 40 THEN 3
        WHEN v.min_hr <= 50 THEN 2
        WHEN v.min_hr <= 60 THEN 1
        ELSE 0
      END
    ) AS hr_score,
    GREATEST(
      CASE 
        WHEN v.max_rr >= 30 THEN 3
        WHEN v.max_rr >= 25 THEN 2
        WHEN v.max_rr >= 20 THEN 1
        ELSE 0
      END,
      CASE 
        WHEN v.min_rr <= 8 THEN 3
        WHEN v.min_rr <= 10 THEN 2
        WHEN v.min_rr <= 12 THEN 1
        ELSE 0
      END
    ) AS rr_score,
    GREATEST(
      CASE 
        WHEN v.max_temp_c >= 39.0 THEN 2
        WHEN v.max_temp_c >= 38.5 THEN 1
        ELSE 0
      END,
      CASE 
        WHEN v.min_temp_c <= 35.0 THEN 2
        WHEN v.min_temp_c <= 36.0 THEN 1
        ELSE 0
      END
    ) AS temp_score,
    CASE 
      WHEN v.min_spo2 < 85 THEN 3
      WHEN v.min_spo2 < 90 THEN 2
      WHEN v.min_spo2 < 94 THEN 1
      ELSE 0
    END AS spo2_score
  FROM vitals v
),
composite_scores AS (
  SELECT 
    s.stay_id,
    s.map_score + s.hr_score + s.rr_score + s.temp_score + s.spo2_score AS composite_score
  FROM scores s
),
rrt_p90 AS (
  SELECT 
    PERCENTILE_CONT(cs.composite_score, 0.9) AS p90_value
  FROM composite_scores cs
  INNER JOIN cohort_with_rrt cwr 
    ON cs.stay_id = cwr.stay_id
  WHERE cwr.rrt_flag = 1
),
hypotension_episodes AS (
  SELECT 
    ce.stay_id,
    COUNT(DISTINCT TIMESTAMP_TRUNC(ce.charttime, HOUR)) AS hypotension_hours
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort_with_rrt cwr
    ON ce.stay_id = cwr.stay_id
    AND ce.charttime BETWEEN cwr.intime AND DATETIME_ADD(cwr.intime, INTERVAL 48 HOUR)
  WHERE ce.itemid IN (220052, 220181, 225312, 220179)
    AND ce.valuenum < 65
  GROUP BY ce.stay_id
),
tachycardia_episodes AS (
  SELECT 
    ce.stay_id,
    COUNT(DISTINCT TIMESTAMP_TRUNC(ce.charttime, HOUR)) AS tachycardia_hours
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN cohort_with_rrt cwr
    ON ce.stay_id = cwr.stay_id
    AND ce.charttime BETWEEN cwr.intime AND DATETIME_ADD(cwr.intime, INTERVAL 48 HOUR)
  WHERE ce.itemid = 220045
    AND ce.valuenum > 100
  GROUP BY ce.stay_id
),
cohort_groups AS (
  -- Group A: Top decile RRT
  SELECT 
    cwr.stay_id,
    'Top Decile RRT' AS group_label
  FROM cohort_with_rrt cwr
  INNER JOIN composite_scores cs 
    ON cwr.stay_id = cs.stay_id
  CROSS JOIN rrt_p90
  WHERE cwr.rrt_flag = 1
    AND cs.composite_score >= rrt_p90.p90_value
  UNION ALL
  -- Group B: Non-RRT
  SELECT 
    stay_id,
    'Non-RRT' AS group_label
  FROM cohort_with_rrt
  WHERE rrt_flag = 0
)
SELECT 
  g.group_label,
  COUNT(DISTINCT g.stay_id) AS n_patients,
  AVG(COALESCE(he.hypotension_hours, 0)) AS avg_hypotension_episodes,
  AVG(COALESCE(te.tachycardia_hours, 0)) AS avg_tachycardia_episodes,
  AVG(cwr.los) AS avg_icu_los,
  AVG(cwr.hospital_expire_flag) AS mortality_rate
FROM cohort_groups g
INNER JOIN cohort_with_rrt cwr 
  ON g.stay_id = cwr.stay_id
LEFT JOIN hypotension_episodes he 
  ON g.stay_id = he.stay_id
LEFT JOIN tachycardia_episodes te 
  ON g.stay_id = te.stay_id
GROUP BY g.group_label;
WITH cardiac_arrest_patients AS (
  SELECT DISTINCT 
    i.stay_id, 
    i.subject_id, 
    i.intime, 
    i.los,
    p.gender, 
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d ON i.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses dic ON d.icd_code = dic.icd_code AND d.icd_version = dic.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
    AND (
      (d.icd_version = 9 AND d.icd_code = '427.5')
      OR (d.icd_version = 10 AND LOWER(dic.long_title) LIKE '%cardiac arrest%')
    )
),

vital_signs_24h AS (
  SELECT 
    c.stay_id,
    AVG(CASE WHEN di.label = 'Heart Rate' THEN c.valuenum END) AS mean_hr,
    AVG(CASE WHEN di.label = 'MAP' THEN c.valuenum END) AS mean_map,
    AVG(CASE WHEN di.label = 'SpO2' THEN c.valuenum END) AS mean_spo2,
    AVG(CASE WHEN di.label = 'Respiratory Rate' THEN c.valuenum END) AS mean_rr
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents c
  JOIN cardiac_arrest_patients cap ON c.stay_id = cap.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu`.d_items di ON c.itemid = di.itemid
  WHERE c.charttime >= cap.intime 
    AND c.charttime < DATE_ADD(cap.intime, INTERVAL 24 HOUR)
    AND di.label IN ('Heart Rate', 'MAP', 'SpO2', 'Respiratory Rate')
    AND c.valuenum IS NOT NULL
  GROUP BY c.stay_id
),

instability_score AS (
  SELECT 
    cap.stay_id,
    cap.los,
    cap.hospital_expire_flag,
    -- Compute z-score deviations for each vital sign
    -- HR: normal 60–100 → mean 80, sd 20 → z = |HR - 80| / 20
    -- MAP: normal 70–100 → mean 85, sd 15 → z = |MAP - 85| / 15
    -- SpO2: normal ≥95 → z = max(0, (95 - SpO2)/10) if <95, else 0
    -- RR: normal 12–20 → mean 16, sd 4 → z = |RR - 16| / 4
    COALESCE(ABS(v.mean_hr - 80) / 20, 0) +
    COALESCE(ABS(v.mean_map - 85) / 15, 0) +
    COALESCE(CASE WHEN v.mean_spo2 < 95 THEN (95 - v.mean_spo2) / 10 ELSE 0 END, 0) +
    COALESCE(ABS(v.mean_rr - 16) / 4, 0) AS instability_score
  FROM cardiac_arrest_patients cap
  JOIN vital_signs_24h v ON cap.stay_id = v.stay_id
  WHERE v.mean_hr IS NOT NULL 
    AND v.mean_map IS NOT NULL 
    AND v.mean_spo2 IS NOT NULL 
    AND v.mean_rr IS NOT NULL
),

percentile_and_decile AS (
  SELECT 
    instability_score,
    los,
    hospital_expire_flag,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile_rank,
    NTILE(10) OVER (ORDER BY instability_score) AS decile
  FROM instability_score
)

SELECT 
  -- Percentile of score = 70
  SUM(CASE WHEN instability_score <= 70 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile_of_70,
  -- Mean LOS and mortality for top decile (decile = 10)
  AVG(CASE WHEN decile = 10 THEN los END) AS mean_los_top_decile,
  AVG(CASE WHEN decile = 10 THEN hospital_expire_flag END) AS mortality_rate_top_decile
FROM percentile_and_decile;
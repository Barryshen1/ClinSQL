WITH first_icu_stays AS (
  SELECT 
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.los AS icu_los,
    p.gender,
    (EXTRACT(YEAR FROM ie.intime) - p.anchor_year + p.anchor_age) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM ie.intime) - p.anchor_year + p.anchor_age) BETWEEN 68 AND 78
),
ranked_stays AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS stay_rank
  FROM first_icu_stays
),
first_stays AS (
  SELECT * FROM ranked_stays WHERE stay_rank = 1
),
multi_trauma AS (
  SELECT 
    di.hadm_id,
    COUNT(*) AS trauma_diagnosis_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.icd_version = 10
    AND (d.icd_code LIKE 'S%' OR d.icd_code LIKE 'T%')
  GROUP BY di.hadm_id
  HAVING COUNT(*) >= 2
),
vital_items AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label IN ('Heart Rate', 
                  'Non Invasive Blood Pressure systolic', 
                  'Arterial Blood Pressure systolic',
                  'Respiratory Rate')
),
vitals_24h AS (
  SELECT 
    ce.stay_id,
    ce.itemid,
    di.label,
    ce.valuenum,
    ce.charttime,
    CASE 
      WHEN di.label = 'Heart Rate' AND ce.valuenum > 100 THEN 1
      WHEN (di.label = 'Non Invasive Blood Pressure systolic' OR di.label = 'Arterial Blood Pressure systolic') 
           AND ce.valuenum < 90 THEN 1
      WHEN di.label = 'Respiratory Rate' AND ce.valuenum > 20 THEN 1
      ELSE 0
    END AS is_abnormal
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN vital_items di ON ce.itemid = di.itemid
  JOIN first_stays fs ON ce.stay_id = fs.stay_id
  WHERE ce.charttime >= fs.intime 
    AND ce.charttime < DATETIME_ADD(fs.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),
instability_scores AS (
  SELECT 
    stay_id,
    SUM(is_abnormal) AS instability_score,
    SUM(CASE WHEN label = 'Heart Rate' AND is_abnormal = 1 THEN 1 ELSE 0 END) AS tachycardia_episodes,
    SUM(CASE WHEN (label LIKE '%systolic%' AND is_abnormal = 1) THEN 1 ELSE 0 END) AS hypotension_episodes,
    SUM(CASE WHEN label = 'Respiratory Rate' AND is_abnormal = 1 THEN 1 ELSE 0 END) AS tachypnea_episodes
  FROM vitals_24h
  GROUP BY stay_id
),
cohort AS (
  SELECT 
    fs.*,
    COALESCE(is.instability_score, 0) AS instability_score,
    COALESCE(is.tachycardia_episodes, 0) AS tachycardia_episodes,
    COALESCE(is.hypotension_episodes, 0) AS hypotension_episodes,
    COALESCE(is.tachypnea_episodes, 0) AS tachypnea_episodes,
    a.hospital_expire_flag
  FROM first_stays fs
  JOIN multi_trauma mt ON fs.hadm_id = mt.hadm_id
  LEFT JOIN instability_scores is ON fs.stay_id = is.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON fs.hadm_id = a.hadm_id
),
quartiles AS (
  SELECT *,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS pct_rank
  FROM cohort
)
-- Main results: by quartile
SELECT 
  quartile,
  COUNT(*) AS count,
  AVG(instability_score) AS mean_score,
  AVG(icu_los) AS mean_icu_los,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(tachycardia_episodes) AS mean_tachycardia_episodes,
  AVG(hypotension_episodes) AS mean_hypotension_episodes,
  AVG(tachypnea_episodes) AS mean_tachypnea_episodes
FROM quartiles
GROUP BY quartile
ORDER BY quartile

UNION ALL

-- Top decile: report mean episodes of each abnormal vital
SELECT 
  5 AS quartile,
  COUNT(*) AS count,
  AVG(instability_score) AS mean_score,
  AVG(icu_los) AS mean_icu_los,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(tachycardia_episodes) AS mean_tachycardia_episodes,
  AVG(hypotension_episodes) AS mean_hypotension_episodes,
  AVG(tachypnea_episodes) AS mean_tachypnea_episodes
FROM quartiles
WHERE pct_rank >= 0.9;
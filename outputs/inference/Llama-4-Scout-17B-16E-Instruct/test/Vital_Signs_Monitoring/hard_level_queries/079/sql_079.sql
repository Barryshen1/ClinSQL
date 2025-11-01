WITH 
-- Identify HFNC itemid
hfnc_itemid AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_icu.d_items` 
  WHERE label LIKE '%High Flow Nasal Cannula%'
),

-- Patients receiving HFNC in the first 48h
hfnc_patients AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    MAX(CASE WHEN cv.itemid IN (SELECT itemid FROM hfnc_itemid) AND cv.charttime BETWEEN ie.intime AND TIMESTAMP_ADD(ie.intime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS received_hfnc
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` cv 
  ON ie.stay_id = cv.stay_id
  GROUP BY 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id, 
    ie.intime
  HAVING 
    MAX(CASE WHEN cv.itemid IN (SELECT itemid FROM hfnc_itemid) AND cv.charttime BETWEEN ie.intime AND TIMESTAMP_ADD(ie.intime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) = 1
),

-- Calculate composite instability score (Placeholder, actual calculation may vary)
instability_scores AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    -- Placeholder for actual score calculation
    AVG(cv.valuenum) AS instability_score
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` cv
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ie 
  ON cv.stay_id = ie.stay_id
  WHERE 
    cv.itemid IN (...)  -- Specific itemids for instability score components
  GROUP BY 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id
),

-- Filter target population
target_population AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    p.gender,
    a.hadm_id,
    is.stay_id,
    is.instability_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
  ON p.subject_id = a.subject_id
  JOIN 
    hfnc_patients h 
  ON a.hadm_id = h.hadm_id
  JOIN 
    instability_scores is 
  ON a.hadm_id = is.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 81 AND 91
),

-- Calculate ICU LOS and hospital mortality for top decile
top_decile AS (
  SELECT 
    tp.instability_score,
    tp.hadm_id,
    tp.stay_id,
    tp.subject_id
  FROM (
    SELECT 
      instability_score,
      hadm_id,
      stay_id,
      subject_id,
      ROW_NUMBER() OVER (ORDER BY instability_score DESC) as row_num,
      COUNT(*) OVER () as total_rows
    FROM target_population
  ) tp
  WHERE row_num <= (total_rows * 0.1)
),

icu_los AS (
  SELECT 
    ie.stay_id,
    AVG(DATEDIFF(a.dischtime, ie.intime)) / 24 AS avg_icu_los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ie 
  ON a.hadm_id = ie.hadm_id
  GROUP BY 
    ie.stay_id
),

mortality AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN a.deathtime IS NOT NULL THEN a.hadm_id END) / COUNT(DISTINCT a.hadm_id) * 100 AS top_decile_mortality
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
  JOIN 
    top_decile td 
  ON a.hadm_id = td.hadm_id
)

-- Final calculations
SELECT 
  PERCENTILE_CONT(0.85) WITHIN GROUP (ORDER BY instability_score) AS percentile_85,
  (SELECT AVG(avg_icu_los_days) FROM icu_los) AS avg_icu_los_days,
  (SELECT top_decile_mortality FROM mortality) AS top_decile_mortality
FROM target_population;
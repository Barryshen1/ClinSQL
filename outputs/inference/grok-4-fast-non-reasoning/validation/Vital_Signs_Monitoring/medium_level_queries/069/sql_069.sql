WITH eligible_stays AS (
  -- Select female ICU stays for ages 41-51
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51
    AND i.los >= 1  -- At least 1 day in ICU
),

rr_data AS (
  -- Get RR measurements in first 48h
  SELECT 
    es.stay_id,
    ce.charttime,
    ce.valuenum
  FROM 
    eligible_stays es
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON es.subject_id = ce.subject_id
    AND es.hadm_id = ce.hadm_id
    AND es.stay_id = ce.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE 
    di.label = 'Respiratory rate'  -- Exact match for RR
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= es.intime
    AND ce.charttime < TIMESTAMP_ADD(es.intime, INTERVAL 48 HOUR)
),

stay_rr_avg AS (
  -- Compute per-stay average RR
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_rr
  FROM 
    rr_data
  GROUP BY 
    stay_id
),

rr_categories AS (
  -- Categorize averages
  SELECT 
    stay_id,
    avg_rr,
    CASE 
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr >= 12 AND avg_rr <= 20 THEN '12-20'
      WHEN avg_rr >= 21 AND avg_rr <= 29 THEN '21-29'
      WHEN avg_rr >= 30 THEN '>=30'
    END AS rr_category
  FROM 
    stay_rr_avg
  WHERE 
    avg_rr IS NOT NULL  -- Only stays with RR data
),

stroke_stays AS (
  -- Identify stays with stroke diagnosis (principal, ICD-10 I6*)
  SELECT DISTINCT
    es.stay_id,
    es.hadm_id
  FROM 
    eligible_stays es
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON es.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code
    AND d.icd_version = icd.icd_version
  WHERE 
    d.seq_num = 1  -- Principal diagnosis
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'I6%'  -- Cerebrovascular diseases (strokes)
    AND icd.long_title LIKE '%stroke%'  -- Refine to stroke-specific
)

SELECT 
  rc.rr_category,
  COUNT(DISTINCT rc.stay_id) AS num_stays,
  COUNT(DISTINCT ss.stay_id) AS num_stays_with_stroke,
  ROUND((COUNT(DISTINCT ss.stay_id) * 100.0 / COUNT(DISTINCT rc.stay_id)), 2) AS stroke_rate_percent
FROM 
  rr_categories rc
LEFT JOIN 
  stroke_stays ss
  ON rc.stay_id = ss.stay_id
GROUP BY 
  rc.rr_category
ORDER BY 
  CASE rc.rr_category
    WHEN '<12' THEN 1
    WHEN '12-20' THEN 2
    WHEN '21-29' THEN 3
    WHEN '>=30' THEN 4
  END;
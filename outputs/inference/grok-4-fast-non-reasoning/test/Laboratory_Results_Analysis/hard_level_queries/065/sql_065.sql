WITH gi_codes AS (
  -- Common ICD-10 codes for lower GI bleed (primary diagnosis)
  SELECT CAST(icd_code AS STRING) AS icd_code FROM UNNEST([
    'K922', 'K625', 'I8501', 'I8511', 'K921', 'K9201', 'K9202', 'K9209', 
    'I9821', 'I8591', 'K5730', 'K5731', 'K5732', 'K5733'
  ]) AS icd_code
),
cohort AS (
  -- Female, 65-75, primary lower GI bleed admission
  SELECT DISTINCT 
    p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id 
    AND d.seq_num = 1 
    AND d.icd_version = '10'
    AND d.icd_code IS NOT NULL
  INNER JOIN gi_codes g ON CAST(d.icd_code AS STRING) = g.icd_code
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 65 AND 75
    AND EXTRACT(YEAR FROM a.admittime) >= 2008  -- MIMIC-IV range
  QUALIFY rn = 1  -- First admission per patient
),
critical_lab_itemids AS (
  -- Itemids for key labs (from d_labitems; hardcoded common ones for GI bleed instability)
  SELECT itemid FROM UNNEST([
    50811,  -- Hgb
    51265,  -- Platelets
    51006,  -- BUN
    50912,  -- Creatinine
    51237,  -- INR
    51274   -- PT
  ]) AS itemid
),
critical_labs AS (
  -- Critical lab events within 72h (count deranged values)
  SELECT 
    c.hadm_id,
    SUM(CASE 
      WHEN l.itemid = 50811 AND l.valuenum < 8 THEN 1  -- Hgb <8 g/dL
      WHEN l.itemid = 51265 AND l.valuenum < 50 THEN 1  -- Plt <50k
      WHEN l.itemid = 51006 AND l.valuenum > 40 THEN 1  -- BUN >40
      WHEN l.itemid = 50912 AND l.valuenum > 2 THEN 1  -- Cr >2
      WHEN l.itemid = 51237 AND l.valuenum > 2 THEN 1  -- INR >2
      WHEN l.itemid = 51274 AND l.valuenum > 18 THEN 1  -- PT >18 sec
      ELSE 0 
    END) AS instability_score
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON c.hadm_id = l.hadm_id
    AND l.itemid IN (SELECT itemid FROM critical_lab_itemids)
  WHERE l.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 3 DAY)
    AND l.charttime >= c.admittime
    AND l.valuenum IS NOT NULL
    AND (l.flag IS NULL OR l.flag != 'cancelled')
  GROUP BY c.hadm_id
),
general_cohort AS (
  -- General female 65-75 admissions (excluding GI bleed)
  SELECT DISTINCT 
    p.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id 
    AND d.seq_num = 1 AND d.icd_version = '10'
  LEFT JOIN gi_codes g ON CAST(d.icd_code AS STRING) = g.icd_code
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 65 AND 75
    AND EXTRACT(YEAR FROM a.admittime) >= 2008
    AND g.icd_code IS NULL  -- Exclude GI bleed
),
general_critical_labs AS (
  -- Critical lab events for general cohort within 72h
  SELECT 
    gc.hadm_id,
    SUM(CASE 
      WHEN l.itemid = 50811 AND l.valuenum < 8 THEN 1
      WHEN l.itemid = 51265 AND l.valuenum < 50 THEN 1
      WHEN l.itemid = 51006 AND l.valuenum > 40 THEN 1
      WHEN l.itemid = 50912 AND l.valuenum > 2 THEN 1
      WHEN l.itemid = 51237 AND l.valuenum > 2 THEN 1
      WHEN l.itemid = 51274 AND l.valuenum > 18 THEN 1
      ELSE 0 
    END) AS instability_score
  FROM general_cohort gc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON gc.hadm_id = l.hadm_id
    AND l.itemid IN (SELECT itemid FROM critical_lab_itemids)
  WHERE l.charttime <= TIMESTAMP_ADD(gc.admittime, INTERVAL 3 DAY)
    AND l.charttime >= gc.admittime
    AND l.valuenum IS NOT NULL
    AND (l.flag IS NULL OR l.flag != 'cancelled')
  GROUP BY gc.hadm_id
),
cohort_summary AS (
  SELECT 
    COUNT(DISTINCT c.hadm_id) AS cohort_size,
    AVG(COALESCE(cl.instability_score, 0)) AS avg_critical_freq_cohort,
    PERCENTILE_CONT(cl.instability_score, 0.25) OVER (ORDER BY cl.instability_score) AS p25_instability_score,
    AVG(DATEDIFF(dischtime, admittime)) AS avg_los_days,
    SUM(hospital_expire_flag) * 1.0 / COUNT(*) AS mortality_rate
  FROM cohort c
  LEFT JOIN critical_labs cl ON c.hadm_id = cl.hadm_id
),
general_summary AS (
  SELECT 
    COUNT(DISTINCT gc.hadm_id) AS general_size,
    AVG(COALESCE(gcl.instability_score, 0)) AS avg_critical_freq_general
  FROM general_cohort gc
  LEFT JOIN general_critical_labs gcl ON gc.hadm_id = gcl.hadm_id
)

SELECT 
  cs.cohort_size,
  ROUND(cs.p25_instability_score, 2) AS p25_instability_score,
  ROUND(cs.avg_critical_freq_cohort, 2) AS cohort_critical_freq,
  ROUND(gs.avg_critical_freq_general, 2) AS general_critical_freq,
  ROUND(cs.avg_los_days, 2) AS avg_los_days,
  ROUND(cs.mortality_rate * 100, 2) AS mortality_pct
FROM cohort_summary cs
CROSS JOIN general_summary gs;
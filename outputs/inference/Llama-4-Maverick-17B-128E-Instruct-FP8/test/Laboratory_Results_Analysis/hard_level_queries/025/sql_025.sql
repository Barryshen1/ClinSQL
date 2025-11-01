WITH 
-- Step 1: Identify patients with hemorrhagic stroke
hemorrhagic_stroke_patients AS (
  SELECT DISTINCT h.subject_id, h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON h.icd_code = d.icd_code AND h.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Hemorrhagic stroke%' AND h.icd_version = 10
),

-- Step 2: Filter by age and gender
cohort AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN hemorrhagic_stroke_patients hsp ON p.subject_id = hsp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON hsp.hadm_id = a.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 48 AND 58
),

-- Step 3: Calculate lab-instability score
lab_instability AS (
  SELECT c.hadm_id, COUNT(DISTINCT le.itemid) AS critical_labs
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON c.hadm_id = le.hadm_id
  WHERE le.charttime BETWEEN c.admittime AND (c.admittime + INTERVAL 3 DAY)
  AND ((le.valuenum < le.ref_range_lower) OR (le.valuenum > le.ref_range_upper))
  GROUP BY c.hadm_id
),

-- Step 4: Calculate 90th percentile of lab-instability score
percentile_90 AS (
  SELECT APPROX_QUANTILES(critical_labs, 100)[OFFSET(90)] AS p90
  FROM lab_instability
),

-- Step 5: Determine outcomes for patients >= P90
outcomes AS (
  SELECT 
    c.hadm_id,
    CASE WHEN c.deathtime IS NOT NULL THEN 1 ELSE 0 END AS mortality,
    DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24 AS los,
    li.critical_labs
  FROM cohort c
  JOIN lab_instability li ON c.hadm_id = li.hadm_id
  WHERE li.critical_labs >= (SELECT p90 FROM percentile_90)
)

-- Final query
SELECT 
  COUNT(*) AS num_patients,
  AVG(mortality) * 100 AS mortality_percent,
  AVG(los) AS mean_los,
  AVG(critical_labs) AS avg_critical_labs
FROM outcomes;
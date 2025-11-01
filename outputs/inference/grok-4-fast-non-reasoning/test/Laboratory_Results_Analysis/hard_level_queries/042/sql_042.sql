WITH ich_cohort AS (
  -- Base cohort: males 73-83 with primary ICH admission
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code 
    AND CAST(d.icd_version AS STRING) = icd.icd_version 
    AND icd.icd_version = 'ICD-9-CM'
    AND LOWER(icd.long_title) LIKE '%intracerebral hemorrhage%'
    AND LOWER(icd.long_title) NOT LIKE '%traumatic%'
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
),

lab_abnormals AS (
  -- Abnormal labs within 48h, by category
  SELECT 
    l.hadm_id,
    li.category
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON l.itemid = li.itemid
  INNER JOIN 
    ich_cohort ic
    ON l.hadm_id = ic.hadm_id
  WHERE 
    l.charttime BETWEEN ic.admittime AND DATE_ADD(ic.admittime, INTERVAL 48 HOUR)
    AND li.category IN ('Routine', 'Blood Gas', 'Urine', 'Hematology', 'Chemistry', 'Coagulation')
    AND l.valuenum IS NOT NULL
    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
    AND l.ref_range_lower IS NOT NULL 
    AND l.ref_range_upper IS NOT NULL
  GROUP BY 
    l.hadm_id, li.category
),

all_inpatients AS (
  -- All male inpatients 73-83 (no ICH filter)
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
),

lab_abnormals_all AS (
  -- Abnormal labs within 48h, by category (for all inpatients)
  SELECT 
    l.hadm_id,
    li.category
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON l.itemid = li.itemid
  INNER JOIN 
    all_inpatients ai
    ON l.hadm_id = ai.hadm_id
  WHERE 
    l.charttime BETWEEN ai.admittime AND DATE_ADD(ai.admittime, INTERVAL 48 HOUR)
    AND li.category IN ('Routine', 'Blood Gas', 'Urine', 'Hematology', 'Chemistry', 'Coagulation')
    AND l.valuenum IS NOT NULL
    AND (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
    AND l.ref_range_lower IS NOT NULL 
    AND l.ref_range_upper IS NOT NULL
  GROUP BY 
    l.hadm_id, li.category
),

ich_scores AS (
  -- Instability score per admission (distinct abnormal categories; 0 if no labs)
  SELECT 
    ic.hadm_id,
    COALESCE(la.instability_score, 0) AS score,
    ic.admittime,
    ic.dischtime,
    ic.hospital_expire_flag
  FROM 
    ich_cohort ic
  LEFT JOIN 
    (SELECT hadm_id, COUNT(DISTINCT category) AS instability_score 
     FROM lab_abnormals GROUP BY hadm_id) la
    ON ic.hadm_id = la.hadm_id
),

all_scores AS (
  -- Same scoring logic for all inpatients
  SELECT 
    ai.hadm_id,
    COALESCE(la.instability_score, 0) AS score,
    ai.admittime,
    ai.dischtime,
    ai.hospital_expire_flag
  FROM 
    all_inpatients ai
  LEFT JOIN 
    (SELECT hadm_id, COUNT(DISTINCT category) AS instability_score 
     FROM lab_abnormals_all GROUP BY hadm_id) la
    ON ai.hadm_id = la.hadm_id
),

quartiles AS (
  -- Stratify into quartiles
  SELECT 
    hadm_id,
    score,
    NTILE(4) OVER (ORDER BY score) AS quartile,
    admittime,
    dischtime,
    hospital_expire_flag
  FROM 
    ich_scores
),

ich_summary AS (
  -- Aggregates per quartile for ICH cohort
  SELECT 
    quartile,
    COUNT(*) AS count,
    AVG(DATE_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM 
    quartiles
  GROUP BY 
    quartile
),

all_quartiles AS (
  SELECT 
    hadm_id,
    score,
    NTILE(4) OVER (ORDER BY score) AS quartile,
    admittime,
    dischtime,
    hospital_expire_flag
  FROM 
    all_scores
),

all_summary AS (
  -- Aggregates for all inpatients (overall, no quartile)
  SELECT 
    'All Inpatients' AS group_label,
    COUNT(*) AS count,
    AVG(DATE_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM 
    all_scores
)

SELECT 
  'ICH Quartile ' || quartile AS group_label,
  count,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(mortality_rate, 4) AS mortality_rate
FROM 
  ich_summary
UNION ALL
SELECT 
  group_label,
  count,
  ROUND(mean_los_days, 2),
  ROUND(mortality_rate, 4)
FROM 
  all_summary
ORDER BY 
  group_label;
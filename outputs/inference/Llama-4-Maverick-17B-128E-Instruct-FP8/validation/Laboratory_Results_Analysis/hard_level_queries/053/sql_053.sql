WITH 
-- Step 1: Filter patients based on age, gender, and diagnosis
eligible_patients AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age, a.admittime, a.dischtime, a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 68 AND 78
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
    WHERE icd.long_title LIKE '%Gastrointestinal hemorrhage%'
  )
),

-- Step 2: Calculate lab-instability score for eligible patients
lab_instability AS (
  SELECT le.hadm_id, 
         STDDEV(le.valuenum) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
  WHERE le.hadm_id IN (SELECT hadm_id FROM eligible_patients)
  AND dl.label IN ('Creatinine', 'Potassium', 'Platelet Count', 'Hemoglobin', 'White Blood Cell Count')
  AND le.charttime BETWEEN (SELECT MIN(admittime) FROM eligible_patients) AND TIMESTAMP_ADD((SELECT MIN(admittime) FROM eligible_patients), INTERVAL 72 HOUR)
  GROUP BY le.hadm_id
),

-- Step 3: Identify top-tier patients based on lab-instability score
top_tier_patients AS (
  SELECT hadm_id, instability_score,
         PERCENT_RANK() OVER (ORDER BY instability_score DESC) AS percentile_rank
  FROM lab_instability
),

-- Step 4: Calculate required metrics for top-tier patients
top_tier_metrics AS (
  SELECT 
    COUNT(CASE WHEN ep.deathtime IS NOT NULL THEN 1 END) AS mortality_count,
    AVG(DATETIME_DIFF(ep.dischtime, ep.admittime, HOUR)) AS avg_los_hours,
    COUNT(*) AS total_count
  FROM eligible_patients ep
  JOIN top_tier_patients tp ON ep.hadm_id = tp.hadm_id
  WHERE tp.percentile_rank <= 0.1  -- Top 10%
),

-- Step 5: Compare critical rates for certain lab values
critical_lab_rates AS (
  SELECT 
    dl.label,
    COUNT(CASE WHEN le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper THEN 1 END) AS critical_count,
    COUNT(le.valuenum) AS total_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
  WHERE le.hadm_id IN (SELECT hadm_id FROM eligible_patients)
  AND dl.label IN ('Creatinine', 'Potassium', 'Platelet Count', 'Hemoglobin', 'White Blood Cell Count')
  GROUP BY dl.label
),

-- Step 6: Compare critical rates for top-tier patients
top_tier_critical_lab_rates AS (
  SELECT 
    dl.label,
    COUNT(CASE WHEN le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper THEN 1 END) AS critical_count,
    COUNT(le.valuenum) AS total_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
  WHERE le.hadm_id IN (SELECT hadm_id FROM top_tier_patients WHERE percentile_rank <= 0.1)
  AND dl.label IN ('Creatinine', 'Potassium', 'Platelet Count', 'Hemoglobin', 'White Blood Cell Count')
  GROUP BY dl.label
)

-- Final query to report required metrics
SELECT 
  APPROX_QUANTILES(li.instability_score, 100)[OFFSET(90)] AS percentile_90_instability_score,
  ttm.mortality_count / ttm.total_count AS mortality_rate_top_tier,
  ttm.avg_los_hours,
  clr.label,
  ttclr.critical_count / ttclr.total_count AS critical_rate_top_tier,
  clr.critical_count / clr.total_count AS critical_rate_all
FROM (SELECT instability_score FROM lab_instability) li,
     top_tier_metrics ttm
JOIN critical_lab_rates clr ON TRUE
LEFT JOIN top_tier_critical_lab_rates ttclr ON clr.label = ttclr.label;
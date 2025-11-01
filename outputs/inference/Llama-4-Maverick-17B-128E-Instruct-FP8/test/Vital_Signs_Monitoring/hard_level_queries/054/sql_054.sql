WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT p.subject_id, p.anchor_year, p.anchor_age, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 82 AND 92
  AND dicd.long_title LIKE '%Respiratory Failure%'
),

-- Step 2: Filter ICU stays and relevant data
icu_data AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, 
         SUM(CASE WHEN c.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label = 'Mean Arterial Pressure') AND c.valuenum < 65 THEN 1 ELSE 0 END) AS map_burden,
         SUM(CASE WHEN c.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label = 'Heart Rate') AND c.valuenum > 100 THEN 1 ELSE 0 END) AS hr_burden
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN cohort ON i.subject_id = cohort.subject_id AND i.hadm_id = cohort.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON i.stay_id = c.stay_id
  WHERE c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY i.subject_id, i.hadm_id, i.stay_id, i.intime
),

-- Step 3 & 4: Calculate composite instability score and statistics
instability_score AS (
  SELECT stay_id, (map_burden + hr_burden) AS composite_score
  FROM icu_data
),

stats AS (
  SELECT 
    APPROX_QUANTILES(composite_score, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(composite_score, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(composite_score, 100)[OFFSET(75)] AS p75
  FROM instability_score
),

-- Step 5: Compare average burdens, ICU LOS, and mortality
comparisons AS (
  SELECT 
    AVG(i.map_burden + i.hr_burden) AS avg_composite_burden,
    AVG(ic.los) AS avg_icu_los,
    SUM(CASE WHEN p.dod IS NOT NULL AND p.dod <= ic.outtime THEN 1 ELSE 0 END) / COUNT(*) AS mortality
  FROM icu_data i
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic ON i.stay_id = ic.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
)

-- Final Query
SELECT 
  s.p25, s.median, s.p75, (s.p75 - s.p25) AS iqr,
  c.avg_composite_burden, c.avg_icu_los, c.mortality
FROM stats s
CROSS JOIN comparisons c;
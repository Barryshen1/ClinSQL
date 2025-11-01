WITH cohort AS (
  -- Filter female patients aged 55-65 with pneumonia (ICD-10 J18.9 as 'J189', seq_num <=2 for primary/secondary)
  SELECT DISTINCT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    p.gender,
    p.anchor_age,
    CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON i.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND d.icd_code = 'J189'  -- Pneumonia, unspecified organism (ICD-10 J18.9)
    AND d.icd_version = 10
    AND d.seq_num <= 2
    AND i.first_careunit != 'Discharge'  -- Valid ICU stay
),

scores AS (
  -- Compute instability score: Average normalized vital deviations in first 24h (simple proxy)
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.anchor_age,
    c.mortality,
    -- First ICU stay per admission
    ROW_NUMBER() OVER (PARTITION BY c.subject_id, c.hadm_id ORDER BY c.intime) AS rn,
    -- Simulate score: AVG((valuenum - normal_low) / (normal_high - normal_low)) for key vitals
    AVG(
      CASE 
        WHEN di.label = 'Heart Rate' THEN (ce.valuenum - 60) / (100 - 60)
        WHEN di.label = 'Systolic Blood Pressure' THEN (ce.valuenum - 90) / (140 - 90)
        WHEN di.label = 'Respiratory Rate' THEN (ce.valuenum - 12) / (20 - 12)
        WHEN di.label = 'Temperature Celsius' THEN (ce.valuenum - 36) / (38 - 36)
        ELSE NULL
      END
    ) * 10 AS instability_score  -- Scale to ~0-100 range for demo
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = c.subject_id
    AND ce.hadm_id = c.hadm_id
    AND ce.stay_id = c.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= c.intime 
    AND ce.charttime <= c.intime + INTERVAL 24 HOUR
    AND di.label IN ('Heart Rate', 'Systolic Blood Pressure', 'Respiratory Rate', 'Temperature Celsius')
    AND ce.valuenum IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id, c.stay_id, c.intime, c.anchor_age, c.mortality
  HAVING COUNT(*) > 0  -- Ensure vitals exist
),

percentile_cte AS (
  -- Percentile for score ≈60
  SELECT 
    subject_id,
    stay_id,
    instability_score,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile
  FROM scores
  WHERE rn = 1  -- First stay only
),

decile_cte AS (
  -- Most unstable decile (top 10%, highest score)
  SELECT 
    s.stay_id,
    NTILE(10) OVER (ORDER BY s.instability_score DESC) AS instability_decile,
    i.los AS icu_los,
    s.mortality,
    s.instability_score
  FROM scores s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON s.stay_id = i.stay_id
  WHERE s.rn = 1  -- First stay only
)

-- Part 1: Percentile for score 60 (average over matches; use ABS for float tolerance)
SELECT 
  'Percentile for score 60' AS metric,
  ROUND(AVG(percentile) * 100, 2) AS percentile_value
FROM percentile_cte 
WHERE ABS(instability_score - 60) < 1  -- Tolerance for computed floats

UNION ALL

-- Part 2: LOS and mortality for most unstable decile (decile 1)
SELECT 
  'Most unstable decile stats' AS metric,
  ROUND(AVG(icu_los), 2) AS avg_icu_los_days,
  ROUND(AVG(mortality) * 100, 2) AS mortality_rate_percent
FROM decile_cte 
WHERE instability_decile = 1;
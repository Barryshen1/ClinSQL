WITH 
-- Filter patients of interest
patients_of_interest AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    p.gender, 
    a.hadm_id, 
    a.admittime, 
    a.deathtime,
    a.hospital_expire_flag,
    a.discharge_location
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 85 AND 95
    AND a.discharge_location LIKE '%ICU%'
    AND a.admission_type = 'Acute Respiratory Failure'
),

-- Get ICU stay information
icu_stays AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id, 
    intime, 
    outtime, 
    los
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Assume a simple instability score calculation for demonstration
instability_scores AS (
  SELECT 
    ce.subject_id, 
    ce.hadm_id, 
    ce.stay_id,
    -- Example calculation: sum of absolute deviations from normal ranges
    SUM(
      ABS(ce.valuenum - 
          CASE 
            WHEN d.label = 'Heart Rate' THEN 72 
            WHEN d.label = 'Systolic Blood Pressure' THEN 120 
            WHEN d.label = 'Respiratory Rate' THEN 18 
          END
        )
    ) AS instability_score
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` d 
      ON ce.itemid = d.itemid
  WHERE 
    ce.charttime BETWEEN (SELECT intime FROM icu_stays WHERE subject_id = ce.subject_id AND hadm_id = ce.hadm_id)
    AND (SELECT outtime FROM icu_stays WHERE subject_id = ce.subject_id AND hadm_id = ce.hadm_id)
    AND d.category IN ('Vital Signs')
  GROUP BY 
    ce.subject_id, 
    ce.hadm_id, 
    ce.stay_id
)

-- Calculate percentile rank and statistics for the most unstable quartile
SELECT 
  APPROX_QUANTILES(instability_score, 100)[OFFSET(50)] AS percentile_50,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS quartile_3_score,
  AVG(icu_stays.los) AS avg_icu_los,
  SUM(CASE WHEN poi.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality
FROM 
  instability_scores
  JOIN patients_of_interest poi ON instability_scores.hadm_id = poi.hadm_id
  JOIN icu_stays ON instability_scores.stay_id = icu_stays.stay_id
WHERE 
  instability_score IS NOT NULL;
WITH icd_codes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.long_title LIKE '%intracranial hemorrhage%'
    OR d.long_title LIKE '%intracerebral hemorrhage%'
    OR d.long_title LIKE '%subarachnoid hemorrhage%'
),
patient_cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag AS mortality
  FROM `physionet-data.mimiciv_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN icd_codes ic
    ON i.hadm_id = ic.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 47 AND 57
),
vital_signs AS (
  SELECT 
    pc.subject_id,
    pc.hadm_id,
    pc.stay_id,
    di.label,
    ce.charttime,
    ce.valuenum
  FROM patient_cohort pc
  JOIN `physionet-data.mimiciv_icu.chartevents` ce
    ON pc.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.charttime BETWEEN pc.intime AND DATETIME_ADD(pc.intime, INTERVAL 72 HOUR)
    AND ce.valuenum IS NOT NULL
    AND di.label IN (
      'Heart Rate', 
      'Non Invasive Blood Pressure systolic',
      'Non Invasive Blood Pressure diastolic',
      'Respiratory Rate',
      'SpO2'
    )
),
vital_stddev AS (
  SELECT 
    stay_id,
    STDDEV(CASE WHEN label = 'Heart Rate' THEN valuenum END) AS hr_std,
    STDDEV(CASE WHEN label = 'Non Invasive Blood Pressure systolic' THEN valuenum END) AS sbp_std,
    STDDEV(CASE WHEN label = 'Non Invasive Blood Pressure diastolic' THEN valuenum END) AS dbp_std,
    STDDEV(CASE WHEN label = 'Respiratory Rate' THEN valuenum END) AS rr_std,
    STDDEV(CASE WHEN label = 'SpO2' THEN valuenum END) AS spo2_std
  FROM vital_signs
  GROUP BY stay_id
),
instability_scores AS (
  SELECT 
    vs.stay_id,
    pc.los,
    pc.mortality,
    -- Create composite instability score (0-100 scale)
    -- Normalize each vital's std dev to 0-100 range using approximate clinical ranges
    (COALESCE(hr_std, 0)/20 * 25 + 
     COALESCE(sbp_std, 0)/30 * 25 + 
     COALESCE(dbp_std, 0)/20 * 25 + 
     COALESCE(rr_std, 0)/8 * 15 + 
     COALESCE((40-spo2_std), 0)/10 * 10) AS instability_score,
    PERCENT_RANK() OVER (ORDER BY 
      (COALESCE(hr_std, 0)/20 * 25 + 
       COALESCE(sbp_std, 0)/30 * 25 + 
       COALESCE(dbp_std, 0)/20 * 25 + 
       COALESCE(rr_std, 0)/8 * 15 + 
       COALESCE((40-spo2_std), 0)/10 * 10)
    ) * 100 AS percentile_rank
  FROM vital_stddev vs
  JOIN patient_cohort pc ON vs.stay_id = pc.stay_id
),
top_decile AS (
  SELECT 
    stay_id,
    los,
    mortality,
    instability_score,
    percentile_rank
  FROM instability_scores
  WHERE percentile_rank >= 90
)
SELECT 
  (SELECT percentile_rank 
   FROM instability_scores 
   WHERE instability_score >= 75 
   ORDER BY instability_score 
   LIMIT 1) AS percentile_for_75,
  (SELECT AVG(los) FROM top_decile) AS avg_los_top_decile,
  (SELECT AVG(mortality) FROM top_decile) AS mortality_rate_top_decile
LIMIT 1;
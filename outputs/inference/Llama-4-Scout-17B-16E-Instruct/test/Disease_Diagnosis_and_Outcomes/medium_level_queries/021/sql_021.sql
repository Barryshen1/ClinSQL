WITH 
  -- Calculate Charlson Comorbidity Index (simplified, actual implementation may vary)
  charlson_index AS (
    SELECT 
      subject_id, 
      hadm_id,
      -- Simplified example, real implementation requires detailed ICD mapping
      COUNT(DISTINCT icd_code) AS charlson_score
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY 
      subject_id, 
      hadm_id
  ),

  -- Identify postoperative complications
  complications AS (
    SELECT 
      subject_id, 
      hadm_id,
      TRUE AS has_complication
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_code LIKE '998%'  -- Example for postoperative complications
  ),

  -- Prepare patient data
  patients_data AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.gender,
      p.anchor_age,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag,
      COALESCE(ic.stay_id, NULL) AS stay_id,
      cc.charlson_score,
      c.has_complication
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    LEFT JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic ON a.hadm_id = ic.hadm_id
    LEFT JOIN 
      charlson_index cc ON a.subject_id = cc.subject_id AND a.hadm_id = cc.hadm_id
    LEFT JOIN 
      complications c ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
    WHERE 
      p.gender = 'M' AND
      p.anchor_age BETWEEN 60 AND 70
  ),

  -- Calculate in-hospital mortality and other metrics
  patient_metrics AS (
    SELECT 
      has_complication,
      stay_id IS NOT NULL AS is_icu,
      CASE 
        WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
        WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
        ELSE '>=8'
      END AS los_category,
      CASE 
        WHEN charlson_score <= 3 THEN '<=3'
        WHEN charlson_score BETWEEN 4 AND 5 THEN '4-5'
        ELSE '>5'
      END AS charlson_category,
      a.hospital_expire_flag,
      a.admittime,
      a.deathtime
    FROM 
      patients_data a
  )

SELECT 
  has_complication,
  is_icu,
  los_category,
  charlson_category,
  hospital_expire_flag,
  COUNT(*) AS N,
  APPROX_QUANTILES(TIMESTAMP_DIFF(deathtime, admittime, DAY), 1000)[500] AS median_time_to_death
FROM 
  patient_metrics
WHERE 
  deathtime IS NOT NULL
GROUP BY 
  has_complication,
  is_icu,
  los_category,
  charlson_category,
  hospital_expire_flag
ORDER BY 
  has_complication,
  is_icu,
  los_category,
  charlson_category;
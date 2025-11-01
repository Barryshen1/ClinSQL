WITH 
  -- Calculate medication complexity score (e.g., number of unique medications within 24 hours)
  medication_complexity AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      COUNT(DISTINCT p.drug) AS complexity_score
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON 
      a.hadm_id = p.hadm_id
    WHERE 
      p.starttime < a.admittime + INTERVAL 1 DAY
    GROUP BY 
      a.subject_id, a.hadm_id
  ),

  -- Patient demographics and admission details
  patient_data AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.anchor_age,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      CASE 
        WHEN a.dischtime IS NULL THEN TIMESTAMP(CURRENT_TIMESTAMP)
        ELSE TIMESTAMP(a.dischtime)
      END AS discharge_time
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
  ),

  -- LOS calculation
  los_data AS (
    SELECT 
      subject_id,
      hadm_id,
      DATE_DIFF(TIMESTAMP(discharge_time), TIMESTAMP(admittime), DAY) AS los
    FROM 
      patient_data
  ),

  -- Combine complexity, patient data, and LOS
  combined_data AS (
    SELECT 
      mc.subject_id,
      mc.hadm_id,
      mc.complexity_score,
      pd.anchor_age,
      pd.dischtime,
      pd.admittime,
      pd.hospital_expire_flag,
      ld.los
    FROM 
      medication_complexity mc
    JOIN 
      patient_data pd
    ON 
      mc.subject_id = pd.subject_id AND mc.hadm_id = pd.hadm_id
    JOIN 
      los_data ld
    ON 
      mc.subject_id = ld.subject_id AND mc.hadm_id = ld.hadm_id
  ),

  -- Identify readmissions within 30 days
  readmissions AS (
    SELECT 
      a1.subject_id,
      COUNT(DISTINCT a2.hadm_id) > 0 AS readmitted
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a1
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON 
      a1.subject_id = a2.subject_id
    WHERE 
      a2.admittime BETWEEN a1.dischtime AND a1.dischtime + INTERVAL 30 DAY
    GROUP BY 
      a1.subject_id
  )

-- Final calculation and quintile stratification
SELECT 
  NTILE(5) OVER (ORDER BY cd.complexity_score) AS quintile,
  COUNT(DISTINCT cd.subject_id) AS num_patients,
  AVG(cd.complexity_score) AS mean_complexity_score,
  AVG(cd.los) AS avg_los,
  SUM(CASE WHEN cd.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT cd.subject_id) AS in_hospital_mortality,
  COALESCE(AVG(IF(r.readmitted, 1, 0)), 0) AS thirty_day_readmission_rate
FROM 
  combined_data cd
  LEFT JOIN readmissions r ON cd.subject_id = r.subject_id
WHERE 
  cd.anchor_age BETWEEN 61 AND 71 AND cd.dischtime IS NOT NULL
GROUP BY 
  quintile
ORDER BY 
  quintile;
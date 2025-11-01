WITH 
  ed_admissions AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.admission_location,
      a.hospital_expire_flag,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON 
      a.subject_id = p.subject_id
    WHERE 
      a.admission_location = 'ED' 
      AND p.gender = 'M'
      AND p.anchor_age BETWEEN 67 AND 77
  ),
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
  final_data AS (
    SELECT 
      ed.subject_id,
      ed.hadm_id,
      ed.dischtime,
      ed.deathtime,
      ed.hospital_expire_flag,
      ic.los,
      CASE 
        WHEN ed.deathtime IS NOT NULL OR ed.hospital_expire_flag = 1 THEN 'Died'
        ELSE 'Alive'
      END AS discharge_status
    FROM 
      ed_admissions ed
    INNER JOIN 
      icu_stays ic 
    ON 
      ed.hadm_id = ic.hadm_id
  ),
  ranked_data AS (
    SELECT 
      discharge_status,
      los,
      PERCENT_RANK() OVER (PARTITION BY discharge_status ORDER BY los) AS percentile_rank_los
    FROM 
      final_data
  )

-- Calculate proportions 
SELECT 
  discharge_status,
  COUNT(*) AS total_patients,
  SAFE_DIVIDE(SUM(CASE WHEN los >= 7 THEN 1 ELSE 0 END), COUNT(*)) AS prop_los_7_days,
  SAFE_DIVIDE(SUM(CASE WHEN los >= 14 THEN 1 ELSE 0 END), COUNT(*)) AS prop_los_14_days,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  AVG(CASE WHEN los >= 10 THEN percentile_rank_los ELSE NULL END) AS avg_percentile_rank_10
FROM 
  ranked_data
GROUP BY 
  discharge_status;
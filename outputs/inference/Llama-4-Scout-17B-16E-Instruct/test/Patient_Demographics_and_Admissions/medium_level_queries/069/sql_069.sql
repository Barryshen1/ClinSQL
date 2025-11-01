WITH 
  patient_stays AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.anchor_age,
      p.gender,
      a.admission_type,
      a.hospital_expire_flag,
      DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 59 AND 69
      AND a.admission_type = 'emergent'
  )

SELECT 
  hospital_expire_flag,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN los >= 7 THEN 1 ELSE 0 END) AS patients_los_7_days,
  SUM(CASE WHEN los >= 7 THEN 1 ELSE 0 END) / COUNT(*) AS proportion_los_7_days,
  APPROX_QUANTILES(los, 100) AS los_percentiles
FROM 
  patient_stays
GROUP BY 
  hospital_expire_flag;
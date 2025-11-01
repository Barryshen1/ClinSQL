WITH 
  patient_stays_alive AS (
    SELECT 
      TIMESTAMPDIFF(DAY, admittime, dischtime) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions`
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients`
    ON 
      admissions.subject_id = patients.subject_id
    WHERE 
      patients.gender = 'M'
      AND admissions.admission_type != 'elective'
      AND patients.anchor_age BETWEEN 57 AND 67
      AND hospital_expire_flag = 0
  )

SELECT 
  COUNTIF(los <= 5) / COUNT(*) AS percentile_rank_5day
FROM 
  patient_stays_alive;
WITH 
  eligible_patients AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      TIMESTAMPDIFF(DAY, a.admittime, a.dischtime) AS los_days,
      CASE 
        WHEN a.hospital_expire_flag = 0 THEN 'Discharged Alive'
        ELSE 'In-Hospital Mortality'
      END AS discharge_status
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 44 AND 54
      AND a.admission_type = 'Elective'
  )

SELECT 
  discharge_status,
  COUNT(*) AS n,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS p25_los,
  APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS median_los,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75_los,
  APPROX_QUANTILES(los_days, 10)[OFFSET(9)] AS p90_los
FROM 
  eligible_patients
GROUP BY 
  discharge_status;
WITH 
  -- Identify AMI admissions for females aged 44-54
  eligible_admissions AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      icu.stay_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` icu 
      ON a.hadm_id = icu.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 44 AND 54
      AND dd.long_title LIKE '%Acute myocardial infarction%'
      AND icu.intime < a.admittime + INTERVAL 3 DAY
  ),
  
  -- Calculate procedure burden during first ICU stay
  procedure_burden AS (
    SELECT 
      stay_id,
      COUNT(DISTINCT itemid) AS procedure_count
    FROM 
      `physionet-data.mimiciv_3_1_icu.procedureevents`
    GROUP BY 
      stay_id
  ),
  
  -- Merge procedure burden with admission data
  burden_admissions AS (
    SELECT 
      ea.*,
      COALESCE(pb.procedure_count, 0) AS procedure_count
    FROM 
      eligible_admissions ea
    LEFT JOIN 
      procedure_burden pb 
      ON ea.stay_id = pb.stay_id
  )

SELECT 
  quartile,
  COUNT(*) AS n,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY)) AS mean_hospital_los,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
FROM (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM 
    burden_admissions
) AS subquery
GROUP BY 
  quartile
ORDER BY 
  quartile;
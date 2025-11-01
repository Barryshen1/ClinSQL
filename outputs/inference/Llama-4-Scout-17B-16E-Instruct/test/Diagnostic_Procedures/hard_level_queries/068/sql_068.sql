WITH 
  -- Identify asthma exacerbation ICD codes
  asthma_exacerbation AS (
    SELECT 
      icd_code
    FROM 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE 
      long_title LIKE '%Asthma exacerbation%'
  ),

  -- Filter patients and admissions
  eligible_patients AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      p.anchor_age, 
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 77 AND 87
  ),

  -- Identify admissions with asthma exacerbation
  asthma_admissions AS (
    SELECT 
      ea.subject_id, 
      ea.hadm_id
    FROM 
      eligible_patients ea
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON 
      ea.hadm_id = di.hadm_id
    JOIN 
      asthma_exacerbation ae
    ON 
      di.icd_code = ae.icd_code
  ),

  -- ICU stays for eligible patients
  icu_stays AS (
    SELECT 
      isubject.hadm_id, 
      isubject.stay_id, 
      isubject.intime
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` isubject
    JOIN 
      asthma_admissions aa
    ON 
      isubject.hadm_id = aa.hadm_id
  ),

  -- Procedures within the first 72 hours of ICU stay
  procedures_72hrs AS (
    SELECT 
      stay.hadm_id, 
      COUNT(pe.stay_id) AS procedure_count
    FROM 
      icu_stays stay
    JOIN 
      `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON 
      stay.stay_id = pe.stay_id
      AND pe.starttime BETWEEN stay.intime AND TIMESTAMP_ADD(stay.intime, INTERVAL 72 HOUR)
    GROUP BY 
      stay.hadm_id
  ),

  -- Assign patients to quartiles
  patient_quartiles AS (
    SELECT 
      hadm_id, 
      procedure_count,
      NTILE(4) OVER (ORDER BY procedure_count) AS quartile
    FROM 
      procedures_72hrs
  ),

  -- Hospital LOS and mortality for each quartile
  los_mortality AS (
    SELECT 
      pq.quartile,
      AVG(TIMESTAMP_DIFF(ea.dischtime, ea.admittime, DAY)) AS mean_hospital_los,
      SUM(CASE WHEN ea.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(ea.hadm_id) AS hospital_mortality,
      AVG(pq.procedure_count) AS mean_procedure_count
    FROM 
      patient_quartiles pq
    JOIN 
      eligible_patients ea
    ON 
      pq.hadm_id = ea.hadm_id
    GROUP BY 
      pq.quartile
  )

SELECT 
  quartile,
  mean_hospital_los,
  hospital_mortality,
  mean_procedure_count
FROM 
  los_mortality
ORDER BY 
  quartile;
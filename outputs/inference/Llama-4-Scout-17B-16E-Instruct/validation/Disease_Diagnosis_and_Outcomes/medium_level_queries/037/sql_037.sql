WITH 
  -- Identify sepsis patients and their severity
  sepsis_patients AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      CASE 
        WHEN di.icd_code IN ('995.91', '998.0') THEN 'septic_shock'
        WHEN di.icd_code IN ('R65.20') THEN 'sepsis_no_shock'
        WHEN di.icd_code IN ('R65.21') THEN 'septic_shock'
        ELSE 'sepsis_no_shock'
      END AS sepsis_severity
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
      a.admission_type NOT IN ('elective') 
      AND p.gender = 'M'
      AND p.anchor_age BETWEEN 52 AND 62
      AND di.icd_code IN ('995.91', '998.0', 'R65.20', 'R65.21')
  ),
  
  -- Determine in-hospital mortality
  mortality AS (
    SELECT 
      subject_id,
      hadm_id,
      hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions`
  ),
  
  comorbidity AS (
    SELECT 
      subject_id,
      hadm_id,
      COUNT(DISTINCT icd_code) AS comorbidity_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY 
      subject_id, hadm_id
  ),
  
  patient_los AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
  )

SELECT 
  sp.sepsis_severity,
  CASE 
    WHEN pl.los BETWEEN 1 AND 3 THEN '1-3'
    WHEN pl.los BETWEEN 4 AND 7 THEN '4-7'
    ELSE '>=8'
  END AS los_category,
  a.admission_type,
  COUNT(DISTINCT CASE WHEN m.hospital_expire_flag = 1 THEN m.subject_id END) AS deaths,
  COUNT(DISTINCT m.subject_id) AS total_patients,
  AVG(c.comorbidity_count) AS mean_comorbidity_count
FROM 
  sepsis_patients sp
JOIN 
  patient_los pl ON sp.subject_id = pl.subject_id AND sp.hadm_id = pl.hadm_id
JOIN 
  mortality m ON sp.subject_id = m.subject_id AND sp.hadm_id = m.hadm_id
JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` a ON sp.subject_id = a.subject_id AND sp.hadm_id = a.hadm_id
JOIN 
  comorbidity c ON sp.subject_id = c.subject_id AND sp.hadm_id = c.hadm_id
GROUP BY 
  sp.sepsis_severity,
  los_category,
  a.admission_type
ORDER BY 
  sp.sepsis_severity,
  los_category,
  a.admission_type;
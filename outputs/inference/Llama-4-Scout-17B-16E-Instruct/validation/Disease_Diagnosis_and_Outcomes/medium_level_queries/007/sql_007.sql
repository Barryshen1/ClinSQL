WITH 
  -- Identify heart failure diagnoses
  heart_failure_diagnoses AS (
    SELECT 
      di.subject_id, 
      di.hadm_id, 
      ddd.long_title
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddd 
      ON di.icd_code = ddd.icd_code AND di.icd_version = ddd.icd_version
    WHERE 
      ddd.long_title LIKE '%Heart failure%'
  ),
  
  -- Patient demographics and heart failure status
  patient_info AS (
    SELECT 
      p.subject_id, 
      p.gender, 
      p.anchor_age, 
      CASE 
        WHEN p.gender = 'F' AND p.anchor_age BETWEEN 51 AND 61 THEN 1 
        ELSE 0 
      END AS eligible
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
  ),
  
  -- ICU stay information
  icu_stays AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),
  
  -- Comorbidity burden
  comorbidity_burden AS (
    SELECT 
      subject_id, 
      hadm_id, 
      COUNT(DISTINCT icd_code) AS comorbidity_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY 
      subject_id, 
      hadm_id
  ),
  
  -- Hospital outcomes
  hospital_outcomes AS (
    SELECT 
      a.hadm_id, 
      a.hospital_expire_flag, 
      a.admittime, 
      a.dischtime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
  )

SELECT 
  -- Determine ICU admission
  CASE 
    WHEN i.stay_id IS NOT NULL THEN 'ICU'
    ELSE 'No ICU'
  END AS icu_admission,
  
  -- Determine LOS category
  CASE 
    WHEN TIMESTAMP_DIFF(ho.dischtime, ho.admittime, DAY) < 8 THEN '< 8 days'
    ELSE '≥ 8 days'
  END AS los_category,
  
  -- Determine comorbidity burden category
  CASE 
    WHEN cb.comorbidity_count <= 2 THEN 'Low'
    WHEN cb.comorbidity_count BETWEEN 3 AND 5 THEN 'Medium'
    ELSE 'High'
  END AS comorbidity_category,
  
  -- In-hospital mortality
  ho.hospital_expire_flag,
  
  -- TO DO: implement prevalence calculations for MV, vasoactive, RRT
  
FROM 
  patient_info pi
JOIN 
  heart_failure_diagnoses hfd 
  ON pi.subject_id = hfd.subject_id
JOIN 
  hospital_outcomes ho 
  ON hfd.hadm_id = ho.hadm_id
LEFT JOIN 
  icu_stays i 
  ON hfd.hadm_id = i.hadm_id
JOIN 
  comorbidity_burden cb 
  ON hfd.hadm_id = cb.hadm_id

WHERE 
  pi.eligible = 1;
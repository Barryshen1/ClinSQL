WITH 
  -- Filter patients and identify postoperative complications
  patients_filtered AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      a.hadm_id,
      a.hospital_expire_flag,
      CASE 
        WHEN a.admission_type = 'elective' THEN 0
        ELSE 1
      END AS postoperative_complication
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
    WHERE 
      p.gender = 'M' AND 
      p.anchor_age BETWEEN 82 AND 92
  ),

  -- Identify ICU patients and calculate LOS
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

  -- Comorbidity count
  comorbidities AS (
    SELECT 
      subject_id,
      hadm_id,
      COUNT(DISTINCT icd_code) AS comorbidity_count
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY 
      subject_id, hadm_id
  ),

  -- Final patient data
  patient_data AS (
    SELECT 
      pf.subject_id,
      pf.hadm_id,
      pf.postoperative_complication,
      COALESCE(ic.stay_id, NULL) AS icu_stay_id,
      CASE 
        WHEN ic.los IS NULL THEN 'non-ICU'
        ELSE 'ICU'
      END AS care_unit,
      CASE 
        WHEN ic.los IS NULL THEN NULL
        ELSE ic.los
      END AS icu_los,
      cm.comorbidity_count,
      pf.hospital_expire_flag
    FROM 
      patients_filtered pf
    LEFT JOIN 
      icu_stays ic ON pf.hadm_id = ic.hadm_id
    JOIN 
      comorbidities cm ON pf.hadm_id = cm.hadm_id AND pf.subject_id = cm.subject_id
  )

-- Group and calculate outcomes
SELECT 
  care_unit,
  CASE 
    WHEN icu_los IS NULL OR icu_los <= 5 THEN 'LOS ≤5'
    ELSE 'LOS >5'
  END AS los_category,
  CASE 
    WHEN comorbidity_count BETWEEN 0 AND 1 THEN '0-1'
    WHEN comorbidity_count = 2 THEN '2'
    ELSE '≥3'
  END AS comorbidity_bin,
  COUNT(DISTINCT subject_id) AS N,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT subject_id) * 100 AS in_hospital_mortality_pct,
  AVG(comorbidity_count) AS avg_comorbidity_count
FROM 
  patient_data
WHERE 
  postoperative_complication = 1
GROUP BY 
  care_unit,
  los_category,
  comorbidity_bin
ORDER BY 
  care_unit,
  los_category,
  comorbidity_bin;
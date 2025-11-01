WITH patients_filtered AS (
  SELECT subject_id, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M'
    AND anchor_age BETWEEN 73 AND 83
),
pneumonia_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE LOWER(long_title) LIKE '%pneumonia%'
    AND SUBSTR(icd_code, 1, 2) = 'J1'
    AND icd_version = 10
),
admissions_with_pneumonia AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_filtered pf ON a.subject_id = pf.subject_id
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    WHERE di.hadm_id = a.hadm_id
      AND di.icd_version = 10
      AND di.icd_code IN (SELECT icd_code FROM pneumonia_codes)
  )
),
comorbidity_definitions AS (
  SELECT 'congestive_heart_failure' AS condition, 'I50' AS icd_prefix, 10 AS icd_version
  UNION ALL SELECT 'cardiac_arrhythmias', 'I48', 10
  UNION ALL SELECT 'valvular_disease', 'I05', 10
  UNION ALL SELECT 'pulmonary_circulation_disorder', 'I27', 10
  UNION ALL SELECT 'peripheral_vascular_disorder', 'I73', 10
  UNION ALL SELECT 'hypertension', 'I10', 10
  UNION ALL SELECT 'paralysis', 'G81', 10
  UNION ALL SELECT 'other_neurological', 'G25', 10
  UNION ALL SELECT 'chronic_pulmonary_disease', 'J44', 10
  UNION ALL SELECT 'diabetes_uncomplicated', 'E11', 10
  UNION ALL SELECT 'diabetes_complicated', 'E13', 10
  UNION ALL SELECT 'hypothyroidism', 'E03', 10
  UNION ALL SELECT 'renal_failure', 'N18', 10
  UNION ALL SELECT 'liver_disease', 'I86', 10
  UNION ALL SELECT 'peptic_ulcer_disease', 'K27', 10
  UNION ALL SELECT 'aids', 'B24', 10
  UNION ALL SELECT 'lymphoma', 'C83', 10
  UNION ALL SELECT 'metastatic_cancer', 'C79', 10
  UNION ALL SELECT 'solid_tumor', 'C78', 10
  UNION ALL SELECT 'rheumatoid_arthritis', 'M05', 10
  UNION ALL SELECT 'coagulopathy', 'D68', 10
  UNION ALL SELECT 'obesity', 'E66', 10
  UNION ALL SELECT 'weight_loss', 'R63', 10
  UNION ALL SELECT 'fluid_electrolyte', 'E87', 10
  UNION ALL SELECT 'blood_loss_anemia', 'D50', 10
  UNION ALL SELECT 'deficiency_anemias', 'D51', 10
  UNION ALL SELECT 'alcohol_abuse', 'F10', 10
  UNION ALL SELECT 'drug_abuse', 'F11', 10
  UNION ALL SELECT 'psychoses', 'F20', 10
  UNION ALL SELECT 'depression', 'F32', 10
),
patient_comorbidities AS (
  SELECT 
    di.subject_id,
    COUNT(DISTINCT cd.condition) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN comorbidity_definitions cd
    ON di.icd_code LIKE CONCAT(cd.icd_prefix, '%') AND di.icd_version = cd.icd_version
  INNER JOIN admissions_with_pneumonia a ON di.hadm_id = a.hadm_id
  GROUP BY di.subject_id
),
comorbidity_threshold AS (
  SELECT
    APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(75)] AS p75_comorbidity
  FROM patient_comorbidities
),
cohort AS (
  SELECT a.*
  FROM admissions_with_pneumonia a
  INNER JOIN patient_comorbidities pc ON a.subject_id = pc.subject_id
  CROSS JOIN comorbidity_threshold
  WHERE pc.comorbidity_count >= comorbidity_threshold.p75_comorbidity
),
icu_stays AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
),
ventilation_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) LIKE '%ventilat%'
     OR LOWER(label) LIKE '%cpap%'
     OR LOWER(label) LIKE '%bipap%'
     OR LOWER(label) = 'ventilation'
),
dialysis_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) LIKE '%dialysis%'
     OR LOWER(label) LIKE '%cvvh%'
     OR LOWER(label) LIKE '%crrt%'
),
procedures_vent_dial AS (
  SELECT DISTINCT stay_id
  FROM `physionet-data.mimiciv_3_1_icu`.procedureevents
  WHERE (itemid IN (SELECT itemid FROM ventilation_items)
         OR itemid IN (SELECT itemid FROM dialysis_items))
    AND statusdescription = 'Started'
),
complications AS (
  SELECT 
    c.hadm_id,
    CASE 
      WHEN i.hadm_id IS NOT NULL THEN 1
      WHEN p.stay_id IS NOT NULL THEN 1
      ELSE 0 
    END AS had_major_complication
  FROM cohort c
  LEFT JOIN icu_stays i ON c.hadm_id = i.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu ON c.hadm_id = icu.hadm_id
  LEFT JOIN procedures_vent_dial p ON icu.stay_id = p.stay_id
),
cohort_summary AS (
  SELECT
    AVG(CAST(hospital_expire_flag = 1 AS FLOAT64)) AS mortality_rate,
    AVG(CAST(had_major_complication AS FLOAT64)) AS complication_rate,
    APPROX_QUANTILES(
      CASE WHEN deathtime IS NOT NULL 
           THEN DATETIME_DIFF(deathtime, admittime, DAY) 
           ELSE NULL END, 
      100)[OFFSET(50)] AS median_survival_days
  FROM cohort c
  LEFT JOIN complications comp ON c.hadm_id = comp.hadm_id
)
SELECT
  mortality_rate * 100 AS in_hospital_mortality_pct,
  complication_rate * 100 AS major_complication_pct,
  median_survival_days
FROM cohort_summary;
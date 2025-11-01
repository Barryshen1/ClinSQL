WITH 
patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 44 AND 54
),
hf_patients AS (
  SELECT DISTINCT hadm_id, subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE diag.long_title LIKE '%Heart failure%'
),
charlson_index AS (
  SELECT hadm_id, COUNT(DISTINCT d.icd_code) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE diag.long_title IN ('Myocardial infarction', 'Congestive heart failure', 'Peripheral vascular disease', 
                             'Cerebrovascular disease', 'Dementia', 'Chronic pulmonary disease', 
                             'Rheumatic disease', 'Peptic ulcer disease', 'Mild liver disease', 
                             'Diabetes without chronic complication', 'Diabetes with chronic complication', 
                             'Hemiplegia or paraplegia', 'Renal disease', 'Any malignancy', 
                             'Moderate or severe liver disease', 'Metastatic solid tumor', 'AIDS/HIV')
  GROUP BY hadm_id
),
icu_stays AS (
  SELECT hadm_id, 
         CASE WHEN stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_admission,
         DATETIME_DIFF(outtime, intime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
vent_vaso_rrt AS (
  SELECT hadm_id,
         MAX(CASE WHEN di.label LIKE '%Vent%' THEN 1 ELSE 0 END) AS mech_vent,
         MAX(CASE WHEN di.label LIKE '%Norepinephrine%' OR di.label LIKE '%Vasopressin%' THEN 1 ELSE 0 END) AS vasopressor,
         MAX(CASE WHEN di.label LIKE '%CRRT%' OR di.label LIKE '%Hemodialysis%' THEN 1 ELSE 0 END) AS rrt
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
  GROUP BY hadm_id
)
SELECT 
  icu.icu_admission,
  CASE WHEN icu.los <= 7 THEN 'LOS <= 7' ELSE 'LOS > 7' END AS los_category,
  CASE 
    WHEN ci.charlson_score BETWEEN 0 AND 1 THEN 'Charlson 0-1'
    WHEN ci.charlson_score = 2 THEN 'Charlson 2'
    ELSE 'Charlson >= 3'
  END AS charlson_category,
  COUNT(*) AS total_patients,
  SUM(a.hospital_expire_flag) AS in_hospital_mortality,
  AVG(a.hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
  AVG(vv.mech_vent) * 100 AS mech_vent_percent,
  AVG(vv.vasopressor) * 100 AS vasopressor_percent,
  AVG(vv.rrt) * 100 AS rrt_percent
FROM patients_filtered p
JOIN hf_patients hf ON p.subject_id = hf.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON hf.hadm_id = a.hadm_id
LEFT JOIN icu_stays icu ON a.hadm_id = icu.hadm_id
JOIN charlson_index ci ON a.hadm_id = ci.hadm_id
LEFT JOIN vent_vaso_rrt vv ON a.hadm_id = vv.hadm_id
WHERE icu.hadm_id IS NOT NULL  -- To ensure we are only counting patients with ICU data
GROUP BY icu.icu_admission, los_category, charlson_category
UNION ALL
SELECT 
  0 AS icu_admission,
  CASE WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) <= 7 THEN 'LOS <= 7' ELSE 'LOS > 7' END AS los_category,
  CASE 
    WHEN ci.charlson_score BETWEEN 0 AND 1 THEN 'Charlson 0-1'
    WHEN ci.charlson_score = 2 THEN 'Charlson 2'
    ELSE 'Charlson >= 3'
  END AS charlson_category,
  COUNT(*) AS total_patients,
  SUM(a.hospital_expire_flag) AS in_hospital_mortality,
  AVG(a.hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
  AVG(vv.mech_vent) * 100 AS mech_vent_percent,
  AVG(vv.vasopressor) * 100 AS vasopressor_percent,
  AVG(vv.rrt) * 100 AS rrt_percent
FROM patients_filtered p
JOIN hf_patients hf ON p.subject_id = hf.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON hf.hadm_id = a.hadm_id
JOIN charlson_index ci ON a.hadm_id = ci.hadm_id
LEFT JOIN vent_vaso_rrt vv ON a.hadm_id = vv.hadm_id
LEFT JOIN icu_stays icu ON a.hadm_id = icu.hadm_id
WHERE icu.hadm_id IS NULL  -- To count patients without ICU data
GROUP BY los_category, charlson_category;
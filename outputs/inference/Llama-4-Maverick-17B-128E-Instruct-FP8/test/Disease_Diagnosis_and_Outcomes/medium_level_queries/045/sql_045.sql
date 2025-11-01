WITH patient_cohort AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 79 AND 89
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
    WHERE diag.subject_id = a.subject_id AND diag.hadm_id = a.hadm_id
    AND (LOWER(d_diag.long_title) LIKE '%pneumonia%' OR d_diag.icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE icd_version = 10 AND long_title LIKE '%Aspiration pneumonia%'))
  )
),
icu_data AS (
  SELECT pc.subject_id, pc.hadm_id, icu.stay_id, icu.intime, icu.outtime,
         DATETIME_DIFF(icu.outtime, icu.intime, DAY) AS los
  FROM patient_cohort pc
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON pc.hadm_id = icu.hadm_id
),
interventions AS (
  SELECT icu.hadm_id,
         MAX(CASE WHEN di.label IN ('Invasive Ventilation', 'Mechanical Ventilation') AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 1 DAY) THEN 1 ELSE 0 END) AS mech_vent_day1,
         MAX(CASE WHEN di.label IN ('Vasopressor', 'Norepinephrine') AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 1 DAY) THEN 1 ELSE 0 END) AS vasopressor_day1,
         MAX(CASE WHEN di.label IN ('Hemofiltration', 'Dialysis') AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 1 DAY) THEN 1 ELSE 0 END) AS rrt_day1
  FROM icu_data icu
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON icu.stay_id = ce.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  GROUP BY icu.hadm_id
)
SELECT 
  CASE WHEN icu.los <= 7 THEN 'LOS <= 7' ELSE 'LOS > 7' END AS los_category,
  COUNT(DISTINCT icu.hadm_id) AS total_patients,
  SUM(pc.hospital_expire_flag) AS in_hospital_mortality,
  AVG(i.mech_vent_day1) AS mech_vent_day1_prevalence,
  AVG(i.vasopressor_day1) AS vasopressor_day1_prevalence,
  AVG(i.rrt_day1) AS rrt_day1_prevalence
FROM icu_data icu
JOIN patient_cohort pc ON icu.hadm_id = pc.hadm_id
LEFT JOIN interventions i ON icu.hadm_id = i.hadm_id
GROUP BY los_category
ORDER BY los_category;
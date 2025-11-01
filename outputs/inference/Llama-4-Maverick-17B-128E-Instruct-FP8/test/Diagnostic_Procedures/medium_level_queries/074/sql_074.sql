WITH patient_selection AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los,
         icu.stay_id IS NOT NULL AS had_icu_stay,
         DATETIME_DIFF(icu.outtime, icu.intime, DAY) AS icu_los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 40 AND 50
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
imaging_procedures AS (
  SELECT pe.hadm_id, COUNT(*) AS num_imaging_procedures
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE di.category LIKE '%Imaging%' 
  GROUP BY pe.hadm_id
)
SELECT 
  CASE 
    WHEN ps.had_icu_stay THEN 'ICU'
    ELSE 'No ICU'
  END AS icu_status,
  CASE 
    WHEN ps.icu_los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN ps.icu_los BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE 'No ICU'
  END AS icu_los_category,
  AVG(ip.num_imaging_procedures) AS mean_imaging_procedures,
  MIN(ip.num_imaging_procedures) AS min_imaging_procedures,
  MAX(ip.num_imaging_procedures) AS max_imaging_procedures
FROM patient_selection ps
LEFT JOIN imaging_procedures ip ON ps.hadm_id = ip.hadm_id
GROUP BY icu_status, icu_los_category
ORDER BY icu_status, icu_los_category;
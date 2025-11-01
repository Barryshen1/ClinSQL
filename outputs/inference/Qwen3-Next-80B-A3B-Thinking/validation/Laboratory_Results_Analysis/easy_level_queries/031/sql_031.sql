SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY labevents.valuenum) AS percentile_75
FROM `physionet-data.mimiciv_3_1_hosp.patients` AS patients
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
  ON patients.subject_id = admissions.subject_id
JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
  ON admissions.hadm_id = icustays.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS labevents
  ON admissions.hadm_id = labevents.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d_labitems
  ON labevents.itemid = d_labitems.itemid
WHERE patients.gender = 'M'
  AND d_labitems.label = 'Potassium'
  AND DATE(labevents.charttime) = DATE(admissions.dischtime);
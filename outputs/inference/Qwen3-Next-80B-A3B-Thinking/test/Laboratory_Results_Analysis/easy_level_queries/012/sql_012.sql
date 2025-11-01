SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY platelet_valuenum) AS percentile_75
FROM (
  SELECT labevents.valuenum AS platelet_valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` admissions
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON admissions.subject_id = patients.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diagnoses_icd
    ON admissions.hadm_id = diagnoses_icd.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` labevents
    ON admissions.hadm_id = labevents.hadm_id
    AND labevents.itemid = 51265
    AND DATE(labevents.charttime) = DATE(admissions.dischtime)
  WHERE patients.gender = 'F'
    AND (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year) = 87
    AND (
      (diagnoses_icd.icd_version = 9 AND diagnoses_icd.icd_code IN ('430', '431', '432'))
      OR (diagnoses_icd.icd_version = 10 AND diagnoses_icd.icd_code IN ('I60', 'I61', 'I62'))
    )
) subquery;
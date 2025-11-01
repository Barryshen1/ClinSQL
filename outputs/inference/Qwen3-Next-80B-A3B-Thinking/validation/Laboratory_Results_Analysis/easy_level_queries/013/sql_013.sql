SELECT MAX(peak_creatinine) AS max_peak_creatinine
FROM (
  SELECT MAX(labevents.valuenum) AS peak_creatinine
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
    ON patients.subject_id = admissions.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diagnoses_icd
    ON admissions.hadm_id = diagnoses_icd.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_icd_diagnoses
    ON diagnoses_icd.icd_code = d_icd_diagnoses.icd_code
    AND diagnoses_icd.icd_version = d_icd_diagnoses.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS labevents
    ON admissions.hadm_id = labevents.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d_labitems
    ON labevents.itemid = d_labitems.itemid
  WHERE patients.gender = 'F'
    AND LOWER(d_icd_diagnoses.long_title) LIKE '%copd%'
    AND LOWER(d_labitems.label) LIKE '%creatinine%'
    AND labevents.valueuom = 'mg/dL'
    AND labevents.charttime BETWEEN admissions.admittime AND admissions.dischtime
    AND labevents.valuenum IS NOT NULL
  GROUP BY admissions.hadm_id
) AS peaks;
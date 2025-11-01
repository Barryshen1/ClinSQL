SELECT
  COUNT(DISTINCT adm.hadm_id) AS number_of_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  ON adm.hadm_id = dx.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
  ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
WHERE
  -- Patient criteria: Female, Age 79-89
  pat.gender = 'F'
  AND ( (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 79 AND 89 )
  -- Admission criteria: From ED, Medicare insurance
  AND adm.admission_location = 'EMERGENCY ROOM'
  AND adm.insurance = 'Medicare'
  -- Diagnosis criteria: Principal diagnosis is pneumonia
  AND dx.seq_num = 1
  AND LOWER(d_dx.long_title) LIKE '%pneumonia%';
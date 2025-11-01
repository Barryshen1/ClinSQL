SELECT
  COUNT(DISTINCT adm.hadm_id) AS num_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON adm.subject_id = pat.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  ON adm.hadm_id = diag.hadm_id
  AND adm.subject_id = diag.subject_id
  AND diag.seq_num = 1  -- Principal diagnosis
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON diag.icd_code = d.icd_code
  AND diag.icd_version = d.icd_version
WHERE
  pat.gender = 'M'
  AND adm.admission_location = 'EMERGENCY ROOM'
  AND adm.insurance = 'Medicare'
  AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year))
      BETWEEN 43 AND 53  -- Age 43-53 at admission
  AND LOWER(d.long_title) LIKE '%diabetic ketoacidosis%';  -- DKA diagnosis;
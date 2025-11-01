SELECT
  COUNT(DISTINCT adm.hadm_id) AS number_of_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON adm.subject_id = p.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dia
  ON adm.hadm_id = dia.hadm_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS did
  ON dia.icd_code = did.icd_code
  AND dia.icd_version = did.icd_version
WHERE
  p.gender = 'M'
  AND adm.insurance = 'Medicare'
  AND adm.admission_location = 'EMERGENCY ROOM'
  AND ((EXTRACT(
      YEAR
    FROM
      adm.admittime
    ) - p.anchor_year) + p.anchor_age) BETWEEN 43 AND 53
  AND dia.seq_num = 1
  AND LOWER(did.long_title) LIKE '%diabetic ketoacidosis%';
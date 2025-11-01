SELECT
  COUNT(DISTINCT adm.hadm_id) AS number_of_index_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  ON adm.hadm_id = dx.hadm_id
WHERE
  -- Patient demographic and insurance criteria
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 70 AND 80
  AND adm.insurance = 'Medicare'

  -- Admission criteria
  AND adm.admission_location = 'EMERGENCY ROOM'

  -- Diagnosis criteria: Principal diagnosis of acute pancreatitis
  AND dx.seq_num = 1
  AND (
    (dx.icd_version = 9 AND dx.icd_code = '577.0')
    OR (dx.icd_version = 10 AND STARTS_WITH(dx.icd_code, 'K85'))
  );
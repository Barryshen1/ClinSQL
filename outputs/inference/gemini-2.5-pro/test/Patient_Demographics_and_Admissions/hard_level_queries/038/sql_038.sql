SELECT
  COUNT(DISTINCT adm.hadm_id) AS number_of_admissions
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  ON pat.subject_id = adm.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  ON adm.hadm_id = dx.hadm_id
WHERE
  -- 1. Filter for patient demographics
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 90 AND 100
  -- 2. Filter for admission details
  AND adm.insurance = 'Medicare'
  AND adm.admission_type = 'TRANSFER FROM OTHER HOSPITAL'
  -- 3. Filter for the principal diagnosis of end-stage renal disease
  AND dx.seq_num = 1
  AND dx.icd_code IN ('585.6', 'N18.6');
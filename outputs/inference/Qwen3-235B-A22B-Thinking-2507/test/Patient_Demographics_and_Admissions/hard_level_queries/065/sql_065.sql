SELECT COUNT(*) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
WHERE
  pat.gender = 'M'
  AND adm.insurance = 'Medicare'
  AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
  AND adm.dischtime IS NOT NULL
  AND (
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)
  ) BETWEEN 72 AND 82
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d_icd
    WHERE
      d_icd.hadm_id = adm.hadm_id
      AND d_icd.seq_num = 1
      AND (
        (d_icd.icd_version = 9 AND d_icd.icd_code = '4111')
        OR (d_icd.icd_version = 10 AND d_icd.icd_code = 'I20.0')
      )
  );
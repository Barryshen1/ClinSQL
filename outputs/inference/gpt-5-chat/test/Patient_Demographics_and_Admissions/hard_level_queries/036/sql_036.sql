SELECT COUNT(*) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON adm.subject_id = pat.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  ON adm.hadm_id = dx.hadm_id
WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 72 AND 82
  AND adm.insurance = 'Medicare'
  AND adm.admission_type = 'EMERGENCY'
  AND adm.hospital_expire_flag = 0
  AND dx.seq_num = 1
  AND (
        (dx.icd_version = 9 AND dx.icd_code LIKE '5770%')
        OR (dx.icd_version = 10 AND dx.icd_code LIKE 'K85%')
      )
;
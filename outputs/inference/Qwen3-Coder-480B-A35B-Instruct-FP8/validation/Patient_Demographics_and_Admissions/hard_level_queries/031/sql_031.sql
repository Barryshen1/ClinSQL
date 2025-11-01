SELECT COUNT(*) AS total_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  ON adm.hadm_id = dx.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
  ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
WHERE
  pat.gender = 'F'
  AND adm.insurance = 'Medicare'
  AND adm.admission_location = 'EMERGENCY ROOM'
  AND dx.seq_num = 1
  AND ddx.icd_code IN ('780.2', 'R55')
  AND (
    EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age BETWEEN 62 AND 72
  );
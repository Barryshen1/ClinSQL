SELECT COUNT(DISTINCT a.hadm_id) AS total_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
  ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
  ON a.subject_id = d.subject_id
  AND a.hadm_id = d.hadm_id
  AND d.seq_num = 1
WHERE p.gender = 'F'
  AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 36 AND 46
  AND a.admission_type = 'transfer'
  AND a.insurance = 'Medicare'
  AND (
    (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432'))
    OR
    (d.icd_version = 10 AND d.icd_code IN ('I60', 'I61', 'I62'))
  );
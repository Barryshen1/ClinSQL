SELECT COUNT(*) AS admission_count
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.hadm_id = d.hadm_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 90 AND 100
  AND a.insurance = 'Medicare'
  AND a.admission_type = 'transfer'
  AND d.seq_num = 1
  AND (
    (d.icd_code = '585.6' AND d.icd_version = 9)
    OR (d.icd_code = 'N18.6' AND d.icd_version = 10)
  );
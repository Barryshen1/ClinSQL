SELECT COUNT(DISTINCT a.hadm_id) AS total_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id AND di.seq_num = 1  -- Principal diagnosis
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 63 AND 73
  AND a.admission_type = 'transfer'
  AND di.icd_code IN (
    SELECT icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE long_title LIKE '%Atrial fibrillation%'
  );
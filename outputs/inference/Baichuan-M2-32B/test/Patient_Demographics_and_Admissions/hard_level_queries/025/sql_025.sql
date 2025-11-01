SELECT COUNT(DISTINCT a.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON a.subject_id = d.subject_id
    AND a.hadm_id = d.hadm_id
    AND d.seq_num = 1  -- principal diagnosis
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_id
    ON d.icd_code = d_id.icd_code
    AND d.icd_version = d_id.icd_version
WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 65 AND 75
    AND a.insurance = 'Medicare'
    AND a.admission_type = 'Transfer from another hospital'
    AND LOWER(d_id.long_title) LIKE '%heart failure%';
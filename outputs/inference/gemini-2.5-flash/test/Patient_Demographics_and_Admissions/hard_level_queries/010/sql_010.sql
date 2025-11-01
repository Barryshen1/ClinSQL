SELECT
    COUNT(DISTINCT adm.hadm_id) AS num_admissions_meeting_criteria
FROM
    `physionet-data.mimiciv_3_1_hosp`.admissions AS adm
JOIN
    `physionet-data.mimiciv_3_1_hosp`.patients AS pat
    ON adm.subject_id = pat.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd AS dicd
    ON adm.subject_id = dicd.subject_id AND adm.hadm_id = dicd.hadm_id
WHERE
    pat.gender = 'M' -- Male patients
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 43 AND 53 -- Age at admission 43-53
    AND adm.insurance = 'Medicare' -- Medicare patients
    AND adm.admission_location = 'EMERGENCY ROOM' -- Admitted from ED
    AND dicd.seq_num = 1 -- Principal diagnosis
    AND (
        (dicd.icd_version = 9 AND dicd.icd_code LIKE '2501%') -- ICD-9 codes for Diabetic Ketoacidosis (e.g., 250.10, 250.11)
        OR
        (dicd.icd_version = 10 AND LEFT(dicd.icd_code, 4) IN ('E101', 'E111', 'E131')) -- ICD-10 codes for Diabetic Ketoacidosis (e.g., E10.10, E11.11)
    );
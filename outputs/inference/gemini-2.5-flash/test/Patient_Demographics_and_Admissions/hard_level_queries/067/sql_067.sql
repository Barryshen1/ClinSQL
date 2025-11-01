SELECT
    COUNT(DISTINCT adm.hadm_id) AS number_of_completed_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
WHERE
    pat.gender = 'F' -- Female patients
    AND adm.insurance = 'Medicare' -- Medicare patients
    AND adm.admission_location = 'EMERGENCY ROOM' -- Admitted from the ED
    AND adm.dischtime IS NOT NULL -- Completed admission
    AND diag.seq_num = 1 -- Principal diagnosis
    AND (
           diag.icd_code LIKE 'K56%' -- ICD-10 codes for intestinal obstruction (e.g., K56.0-K56.7)
        OR diag.icd_code LIKE '560%'  -- ICD-9 codes for intestinal obstruction (e.g., 560.x)
        OR diag.icd_code LIKE 'K91.3%' -- ICD-10 codes for postprocedural intestinal obstruction (e.g., K91.30, K91.39)
    )
    AND (
        pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 43 AND 53
    ) -- Age at admission between 43 and 53
;
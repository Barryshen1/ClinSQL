WITH heart_failure_admissions AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        pat.gender,
        pat.anchor_age,
        pat.anchor_year,
        -- Compute age at admission
        EXTRACT(YEAR FROM adm.admittime) - (pat.anchor_year - pat.anchor_age) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE 
        diag.icd_code LIKE 'I50%'   -- Heart failure codes
        AND diag.seq_num = 1         -- Primary diagnosis
        AND pat.gender = 'F'
)
SELECT 
    AVG(DATE_DIFF(dischtime, admittime, DAY)) AS avg_length_of_stay
FROM heart_failure_admissions
WHERE age_at_admission BETWEEN 61 AND 71;
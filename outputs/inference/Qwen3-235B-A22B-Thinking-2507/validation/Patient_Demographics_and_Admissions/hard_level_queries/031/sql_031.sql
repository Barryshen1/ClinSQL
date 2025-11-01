WITH base_cohort AS (
    SELECT 
        adm.hadm_id,
        adm.subject_id,
        adm.admittime,
        (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON adm.hadm_id = diag.hadm_id
    WHERE 
        pat.gender = 'F'
        AND adm.insurance = 'Medicare'
        AND adm.admission_location = 'EMERGENCY ROOM'
        AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 62 AND 72
        AND diag.seq_num = 1
        AND (
            (diag.icd_version = 9 AND diag.icd_code = '7802')
            OR 
            (diag.icd_version = 10 AND diag.icd_code = 'R55')
        )
),
first_admissions AS (
    SELECT 
        subject_id,
        hadm_id,
        admittime,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM base_cohort
)
SELECT COUNT(*) AS total_index_admissions
FROM first_admissions
WHERE rn = 1;
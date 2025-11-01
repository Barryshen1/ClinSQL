WITH cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        pat.anchor_age,
        pat.anchor_year,
        (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
    WHERE adm.admission_location = 'EMERGENCY ROOM'
        AND adm.insurance = 'Medicare'
        AND pat.gender = 'F'
        AND diag.icd_code = 'K85'
        AND diag.icd_version = 10
        AND diag.seq_num = 1
        AND adm.hospital_expire_flag = 0
),
index_admissions AS (
    SELECT 
        subject_id,
        hadm_id,
        age_at_admission,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank
    FROM cohort
    WHERE age_at_admission BETWEEN 72 AND 82
)
SELECT 
    COUNT(hadm_id) AS total_admissions
FROM index_admissions
WHERE admission_rank = 1;
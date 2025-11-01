WITH cohort AS (
    SELECT 
        p.subject_id,
        p.gender,
        DATE_DIFF(DATE(a.admittime), DATE_ADD(DATE(p.anchor_year, 1, 1), INTERVAL - p.anchor_age YEAR), YEAR) AS age_at_admission,
        a.hadm_id,
        a.admittime,
        a.insurance,
        a.admission_type,
        a.admission_location,
        d.icd_code,
        d.icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
    WHERE 
        p.gender = 'F'
        AND d.seq_num = 1
        AND a.insurance = 'Medicare'
        AND a.admission_type = 'TRANSFER'
        AND a.admission_location LIKE '%HOSPITAL%'
        AND (
            (d.icd_version = 10 AND d.icd_code LIKE 'I50%') OR
            (d.icd_version = 9 AND d.icd_code LIKE '428%')
        )
),
index_admissions AS (
    SELECT 
        subject_id,
        hadm_id,
        admittime,
        age_at_admission,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM cohort
    WHERE age_at_admission BETWEEN 65 AND 75
)
SELECT 
    COUNT(*) AS count_index_admissions
FROM index_admissions
WHERE rn = 1;
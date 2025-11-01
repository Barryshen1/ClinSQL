WITH hf_patients AS (
    -- Men aged 90-100 with heart failure diagnosis
    SELECT DISTINCT p.subject_id, p.anchor_age, d.hadm_id, d.seq_num
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON p.subject_id = d.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 90 AND 100
        AND (
            (d.icd_version = 10 AND d.icd_code LIKE 'I50%') 
            OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
        )
),

los_groups AS (
    -- Get admissions with LOS between 1 and 7 days, and group them
    SELECT 
        hadm_id,
        CASE 
            WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
            WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
        END AS los_group
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    WHERE DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 7
),

-- Count MRI/CT from procedures_icd
icd_procedures AS (
    SELECT 
        hadm_id,
        COUNT(*) AS count_procedures
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
        ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE LOWER(d.long_title) LIKE '%mri%' OR LOWER(d.long_title) LIKE '%ct%'
    GROUP BY hadm_id
),

-- Count MRI/CT from hcpcsevents
hcpcs_procedures AS (
    SELECT 
        hadm_id,
        COUNT(*) AS count_procedures
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
        ON h.hcpcs_cd = d.code
    WHERE LOWER(d.short_description) LIKE '%mri%' OR LOWER(d.short_description) LIKE '%ct%'
        OR LOWER(d.long_description) LIKE '%mri%' OR LOWER(d.long_description) LIKE '%ct%'
    GROUP BY hadm_id
),

-- Combine ICD and HCPCS procedure counts per admission
all_procedures AS (
    SELECT 
        hadm_id,
        COALESCE(SUM(count_procedures), 0) AS total_procedures
    FROM (
        SELECT hadm_id, count_procedures FROM icd_procedures
        UNION ALL
        SELECT hadm_id, count_procedures FROM hcpcs_procedures
    )
    GROUP BY hadm_id
),

-- For each HF admission, determine if primary or secondary and join with LOS group and procedures
cohort AS (
    SELECT 
        hf.subject_id,
        hf.hadm_id,
        hf.anchor_age,
        CASE WHEN hf.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS hf_type,
        lg.los_group,
        COALESCE(ap.total_procedures, 0) AS procedure_count
    FROM hf_patients hf
    INNER JOIN los_groups lg
        ON hf.hadm_id = lg.hadm_id
    LEFT JOIN all_procedures ap
        ON hf.hadm_id = ap.hadm_id
)

-- Final aggregation: count admissions and avg procedures per admission by HF type and LOS group
SELECT 
    hf_type,
    los_group,
    COUNT(DISTINCT hadm_id) AS admission_count,
    AVG(procedure_count) AS mean_procedures_per_admission
FROM cohort
GROUP BY hf_type, los_group
ORDER BY hf_type, los_group;
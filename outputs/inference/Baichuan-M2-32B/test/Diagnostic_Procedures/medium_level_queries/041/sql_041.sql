WITH pancreatitis_codes AS (
    SELECT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE long_title LIKE '%acute pancreatitis%'
),
admissions_with_age AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        p.gender,
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 51 AND 61
),
admissions_with_pancreatitis AS (
    SELECT 
        awa.*,
        d_min.min_seq_num
    FROM admissions_with_age awa
    JOIN (
        SELECT 
            d.hadm_id, 
            MIN(d.seq_num) AS min_seq_num
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN pancreatitis_codes pc 
            ON d.icd_code = pc.icd_code AND d.icd_version = pc.icd_version
        GROUP BY d.hadm_id
    ) d_min ON awa.hadm_id = d_min.hadm_id
),
admissions_with_los AS (
    SELECT 
        *,
        TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
        CASE 
            WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
            ELSE 'Other'
        END AS los_category
    FROM admissions_with_pancreatitis
),
ct_counts AS (
    SELECT 
        hadm_id, 
        COUNT(*) AS ct_count
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    WHERE h.hcpcs_cd BETWEEN '70450' AND '75995'   -- string comparison of 5-digit codes
    GROUP BY hadm_id
)
SELECT 
    los_category,
    CASE 
        WHEN min_seq_num = 1 THEN 'primary'
        ELSE 'secondary'
    END AS diagnosis_type,
    COUNT(DISTINCT hadm_id) AS admission_count,
    COUNT(DISTINCT subject_id) AS patient_count,
    AVG(COALESCE(ct.ct_count, 0)) AS mean_ct_per_admission
FROM admissions_with_los awl
LEFT JOIN ct_counts ct ON awl.hadm_id = ct.hadm_id
WHERE los_category IN ('1-3 days', '4-7 days')   -- exclude 'Other'
GROUP BY los_category, diagnosis_type
ORDER BY los_category, diagnosis_type;
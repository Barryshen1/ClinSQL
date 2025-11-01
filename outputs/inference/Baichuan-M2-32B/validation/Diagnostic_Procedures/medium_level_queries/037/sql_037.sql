WITH eligible_patients AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        (p.anchor_year - p.anchor_age) AS birth_year,
        EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 43 AND 53
        AND a.dischtime IS NOT NULL
),
ami_diagnoses AS (
    SELECT 
        d.subject_id,
        d.hadm_id,
        d.seq_num,
        CASE 
            WHEN d.icd_code LIKE 'I21.%' OR d.icd_code = 'I22.0' THEN 1
            ELSE 0 
        END AS is_ami
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.icd_version = 10
),
ami_flags AS (
    SELECT 
        e.subject_id,
        e.hadm_id,
        MAX(CASE WHEN a.seq_num = 1 AND a.is_ami = 1 THEN 1 ELSE 0 END) AS primary_ami,
        MAX(CASE WHEN a.seq_num > 1 AND a.is_ami = 1 THEN 1 ELSE 0 END) AS has_secondary_ami
    FROM eligible_patients e
    LEFT JOIN ami_diagnoses a 
        ON e.subject_id = a.subject_id AND e.hadm_id = a.hadm_id
    GROUP BY e.subject_id, e.hadm_id
),
ami_groups AS (
    SELECT 
        subject_id,
        hadm_id,
        CASE 
            WHEN primary_ami = 1 THEN 'primary_ami'
            WHEN primary_ami = 0 AND has_secondary_ami = 1 THEN 'secondary_ami'
            ELSE NULL 
        END AS ami_group
    FROM ami_flags
),
admissions_with_los AS (
    SELECT 
        e.subject_id,
        e.hadm_id,
        a.ami_group,
        DATEDIFF(e.dischtime, e.admittime) AS los_days,
        CASE 
            WHEN DATEDIFF(e.dischtime, e.admittime) BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN DATEDIFF(e.dischtime, e.admittime) BETWEEN 4 AND 7 THEN '4-7 days'
            ELSE NULL 
        END AS los_group
    FROM eligible_patients e
    INNER JOIN ami_groups a 
        ON e.subject_id = a.subject_id AND e.hadm_id = a.hadm_id
    WHERE a.ami_group IS NOT NULL
),
radiography_counts AS (
    SELECT 
        h.subject_id,
        h.hadm_id,
        COUNT(*) AS radiography_ct_count
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
        ON h.hcpcs_cd = d.code
    WHERE 
        d.long_description LIKE '%radiography%' OR 
        d.long_description LIKE '%x-ray%' OR 
        d.long_description LIKE '%ct%' OR 
        d.long_description LIKE '%computed tomography%'
    GROUP BY h.subject_id, h.hadm_id
),
final_data AS (
    SELECT 
        a.ami_group,
        a.los_group,
        COALESCE(r.radiography_ct_count, 0) AS radiography_ct_count
    FROM admissions_with_los a
    LEFT JOIN radiography_counts r 
        ON a.subject_id = r.subject_id AND a.hadm_id = r.hadm_id
    WHERE a.los_group IS NOT NULL
)
SELECT 
    ami_group,
    los_group,
    APPROX_QUANTILES(radiography_ct_count, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(radiography_ct_count, 100)[OFFSET(25)] AS q1,
    APPROX_QUANTILES(radiography_ct_count, 100)[OFFSET(75)] AS q3,
    APPROX_QUANTILES(radiography_ct_count, 100)[OFFSET(75)] - APPROX_QUANTILES(radiography_ct_count, 100)[OFFSET(25)] AS iqr
FROM final_data
GROUP BY ami_group, los_group
ORDER BY ami_group, los_group;
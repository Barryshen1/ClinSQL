WITH cohort AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 41 AND 51
),

procedures_ecg_icd AS (
    SELECT 
        proc.subject_id, 
        CONCAT('ICD_', proc.icd_code, '_', proc.icd_version) AS proc_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
        ON proc.icd_code = d.icd_code AND proc.icd_version = d.icd_version
    INNER JOIN cohort c ON proc.subject_id = c.subject_id
    WHERE 
        LOWER(d.long_title) LIKE '%ecg%' 
        OR LOWER(d.long_title) LIKE '%electrocardiogram%' 
        OR LOWER(d.long_title) LIKE '%telemetry%'
),

procedures_ecg_hcpcs AS (
    SELECT 
        h.subject_id, 
        CONCAT('HCPCS_', h.hcpcs_cd) AS proc_id
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
        ON h.hcpcs_cd = d.code
    INNER JOIN cohort c ON h.subject_id = c.subject_id
    WHERE 
        LOWER(d.long_description) LIKE '%ecg%' 
        OR LOWER(d.long_description) LIKE '%electrocardiogram%' 
        OR LOWER(d.long_description) LIKE '%telemetry%'
        OR LOWER(d.short_description) LIKE '%ecg%' 
        OR LOWER(d.short_description) LIKE '%electrocardiogram%' 
        OR LOWER(d.short_description) LIKE '%telemetry%'
),

all_procedures AS (
    SELECT subject_id, proc_id FROM procedures_ecg_icd
    UNION DISTINCT 
    SELECT subject_id, proc_id FROM procedures_ecg_hcpcs
),

patient_counts AS (
    SELECT 
        c.subject_id,
        COUNT(DISTINCT a.proc_id) AS num_procedures
    FROM cohort c
    LEFT JOIN all_procedures a ON c.subject_id = a.subject_id
    GROUP BY c.subject_id
)

SELECT 
    APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS percentile_75
FROM patient_counts;
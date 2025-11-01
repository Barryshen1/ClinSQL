WITH patient_admissions AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        -- Compute LOS in days
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 45 AND 55
      AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
hf_diagnoses AS (
    SELECT 
        d.hadm_id,
        d.seq_num,
        CASE 
            WHEN (d.icd_version = 10 AND d.icd_code LIKE 'I50%') OR (d.icd_version = 9 AND d.icd_code LIKE '428%') 
            THEN 1 
            ELSE 0 
        END AS is_hf
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    -- We don't need d_icd_diagnoses for filtering by code pattern, so we remove the join
),
primary_diagnosis AS (
    SELECT 
        hadm_id,
        MAX(CASE WHEN seq_num = 1 THEN is_hf END) AS is_hf_primary
    FROM hf_diagnoses
    GROUP BY hadm_id
),
secondary_diagnosis AS (
    SELECT 
        hadm_id,
        MAX(CASE WHEN seq_num > 1 THEN is_hf END) AS has_hf_secondary
    FROM hf_diagnoses
    GROUP BY hadm_id
),
admission_hf_group AS (
    SELECT 
        p.hadm_id,
        CASE 
            WHEN p.is_hf_primary = 1 THEN 'Primary'
            WHEN s.has_hf_secondary = 1 THEN 'Secondary'
            ELSE 'Other' 
        END AS hf_group
    FROM primary_diagnosis p
    LEFT JOIN secondary_diagnosis s ON p.hadm_id = s.hadm_id
),
hf_admissions AS (
    SELECT 
        a.hadm_id,
        a.los_days,
        g.hf_group
    FROM patient_admissions a
    JOIN admission_hf_group g ON a.hadm_id = g.hadm_id
    WHERE g.hf_group IN ('Primary', 'Secondary')
),
ct_mri_counts AS (
    SELECT 
        h.hadm_id,
        COUNT(*) AS ct_mri_count
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
        ON h.hcpcs_cd = d.code
    WHERE LOWER(d.long_description) LIKE '%ct%' 
       OR LOWER(d.long_description) LIKE '%mri%'
    GROUP BY h.hadm_id
),
final_admissions AS (
    SELECT 
        h.hf_group,
        h.los_days,
        -- Create LOS group: 1-3 or 4-7
        CASE 
            WHEN h.los_days BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN h.los_days BETWEEN 4 AND 7 THEN '4-7 days'
        END AS los_group,
        COALESCE(c.ct_mri_count, 0) AS ct_mri_count
    FROM hf_admissions h
    LEFT JOIN ct_mri_counts c ON h.hadm_id = c.hadm_id
)
SELECT 
    hf_group,
    los_group,
    AVG(ct_mri_count) AS mean_ct_mri,
    MIN(ct_mri_count) AS min_ct_mri,
    MAX(ct_mri_count) AS max_ct_mri
FROM final_admissions
GROUP BY hf_group, los_group
ORDER BY hf_group, los_group;
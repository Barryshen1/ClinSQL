WITH eligible_admissions AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        CASE 
            WHEN MAX(i.stay_id) IS NOT NULL THEN 1 
            ELSE 0 
        END AS icu_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
        ON a.hadm_id = i.hadm_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 40 AND 50
        AND a.dischtime IS NOT NULL
        AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
        AND (dd.long_title LIKE '%ischemic stroke%' OR dd.long_title LIKE '%cerebral infarction%')
    GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime, TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)
),
imaging_counts AS (
    SELECT 
        e.hadm_id,
        COUNT(h.hcpcs_cd) AS imaging_count
    FROM eligible_admissions e
    LEFT JOIN (
        SELECT h.hadm_id, h.hcpcs_cd
        FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh 
            ON h.hcpcs_cd = dh.code
        WHERE dh.category = 'Radiology'
    ) h ON e.hadm_id = CAST(h.hadm_id AS INT64)  -- Cast to INT64 to match eligible_admissions.hadm_id
    GROUP BY e.hadm_id
)
SELECT 
    e.icu_flag,
    CASE 
        WHEN e.los_days BETWEEN 1 AND 4 THEN '1-4 days'
        WHEN e.los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    AVG(i.imaging_count) AS mean_imaging,
    MIN(i.imaging_count) AS min_imaging,
    MAX(i.imaging_count) AS max_imaging
FROM eligible_admissions e
LEFT JOIN imaging_counts i ON e.hadm_id = i.hadm_id
GROUP BY e.icu_flag, los_group
ORDER BY e.icu_flag, los_group;
WITH index_admissions AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        -- Check for death during index admission
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 83 AND 93
        AND a.admission_location LIKE '%EMERGENCY ROOM%'
        AND d.seq_num = 1
        AND d.icd_version = 10
        AND d.icd_code LIKE 'G45%'
    -- Ensure we get the first admission per patient that meets criteria
    QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),
readmissions AS (
    SELECT 
        i.subject_id,
        i.hadm_id AS index_hadm_id,
        i.dischtime,
        MAX(CASE WHEN a.admittime <= DATETIME_ADD(i.dischtime, INTERVAL 30 DAY) 
                 AND a.admittime > i.dischtime 
                 THEN 1 ELSE 0 END) AS readmitted_30d
    FROM index_admissions i
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON i.subject_id = a.subject_id
        AND a.admittime > i.dischtime
    GROUP BY i.subject_id, i.hadm_id, i.dischtime
)
SELECT 
    COUNT(*) AS total_index_admissions,
    SUM(r.readmitted_30d) AS readmitted_count,
    ROUND(100.0 * SUM(r.readmitted_30d) / COUNT(*), 2) AS readmission_rate_percent,
    -- Median LOS for readmitted vs non-readmitted
    APPROX_QUANTILES(CASE WHEN r.readmitted_30d = 1 THEN i.los_days END, 100)[OFFSET(50)] AS median_los_readmitted,
    APPROX_QUANTILES(CASE WHEN r.readmitted_30d = 0 THEN i.los_days END, 100)[OFFSET(50)] AS median_los_non_readmitted,
    -- Percentage of index stays >10 days
    ROUND(100.0 * SUM(CASE WHEN i.los_days > 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_los_gt_10_days
FROM index_admissions i
INNER JOIN readmissions r
    ON i.hadm_id = r.index_hadm_id
WHERE i.hospital_expire_flag = 0  -- Exclude index admissions with in-hospital death;
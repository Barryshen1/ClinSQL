WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id AS index_hadm, 
        adm.admittime, 
        adm.dischtime,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 61 AND 71
        AND adm.insurance = 'Medicare'
        AND adm.admission_location LIKE '%SNF%'
        AND diag.seq_num = 1  -- principal diagnosis
        AND (
            (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%') OR
            (diag.icd_version = 9 AND diag.icd_code LIKE '584%')
        )
        AND adm.hospital_expire_flag = 0  -- exclude deaths during index admission
),

readmissions AS (
    SELECT 
        c.subject_id,
        c.index_hadm,
        c.admittime,
        c.dischtime,
        c.los_days,
        MAX(CASE WHEN readm.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS readmitted_30d
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` readm
        ON c.subject_id = readm.subject_id
        AND readm.admittime > c.dischtime
        AND readm.admittime <= DATE_ADD(c.dischtime, INTERVAL 30 DAY)
        AND readm.admission_type != 'NEWBORN'  -- ensure valid readmission
    GROUP BY c.subject_id, c.index_hadm, c.admittime, c.dischtime, c.los_days
)

SELECT
    COUNT(*) AS total_index_admissions,
    SUM(readmitted_30d) AS readmitted_count,
    ROUND(100.0 * SUM(readmitted_30d) / COUNT(*), 2) AS readmission_rate_percent,
    -- Median LOS for readmitted vs non-readmitted
    APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN los_days END, 100)[OFFSET(50)] AS median_los_readmitted,
    APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN los_days END, 100)[OFFSET(50)] AS median_los_non_readmitted,
    -- Percentage of index stays with LOS > 6 days
    ROUND(100.0 * SUM(CASE WHEN los_days > 6 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_los_gt_6_days
FROM readmissions;
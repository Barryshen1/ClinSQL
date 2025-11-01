WITH eligible_admissions AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
        p.gender,
        p.anchor_age,
        a.insurance,
        a.admission_type,
        d.icd_code,
        d.icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 83 AND 93
        AND a.insurance LIKE '%Medicare%'
        AND a.admission_type = 'Emergency'
        AND d.seq_num = 1
        AND d.icd_version = 10
        AND d.icd_code LIKE 'G45%'
),
index_admissions AS (
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        los,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_seq
    FROM eligible_admissions
),
first_index_admissions AS (
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        los
    FROM index_admissions
    WHERE admission_seq = 1
),
readmission_check AS (
    SELECT
        fia.subject_id,
        fia.hadm_id,
        fia.admittime,
        fia.dischtime,
        fia.los,
        EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
            WHERE 
                a2.subject_id = fia.subject_id
                AND a2.admittime > fia.dischtime
                AND a2.admittime <= DATE_ADD(fia.dischtime, INTERVAL 30 DAY)
                AND a2.hadm_id != fia.hadm_id
        ) AS readmitted
    FROM first_index_admissions fia
),
aggregated_data AS (
    SELECT
        readmitted,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median_los,
        COUNT(*) AS total_admissions,
        COUNTIF(los > 10) AS stays_over_10_days
    FROM readmission_check
    GROUP BY readmitted
),
readmission_rate AS (
    SELECT
        (SELECT total_admissions FROM aggregated_data WHERE readmitted = TRUE) * 1.0 /
        (SELECT total_admissions FROM aggregated_data) AS readmission_rate,
        (SELECT stays_over_10_days FROM aggregated_data WHERE readmitted = TRUE) * 100.0 /
        (SELECT total_admissions FROM aggregated_data WHERE readmitted = TRUE) AS pct_over_10_readmitted,
        (SELECT stays_over_10_days FROM aggregated_data WHERE readmitted = FALSE) * 100.0 /
        (SELECT total_admissions FROM aggregated_data WHERE readmitted = FALSE) AS pct_over_10_non_readmitted,
        (SELECT median_los FROM aggregated_data WHERE readmitted = TRUE) AS median_los_readmitted,
        (SELECT median_los FROM aggregated_data WHERE readmitted = FALSE) AS median_los_non_readmitted
)
SELECT
    readmission_rate,
    median_los_readmitted,
    median_los_non_readmitted,
    pct_over_10_readmitted,
    pct_over_10_non_readmitted
FROM readmission_rate;
WITH index_admissions AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
        AND d.seq_num = 1
    WHERE
        p.gender = 'F'
        AND a.insurance = 'Medicare'
        AND p.anchor_age BETWEEN 76 AND 86
        AND a.admission_location = 'TRANSFER FROM OTHER HOSPITAL'
        AND (
            (d.icd_version = '9' AND d.icd_code LIKE '410%')
            OR (d.icd_version = '10' AND d.icd_code LIKE 'I21%')
        )
),
readmission_flag AS (
    SELECT
        ia.*,
        CASE WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
            WHERE a2.subject_id = ia.subject_id
                AND a2.hadm_id != ia.hadm_id
                AND a2.admittime >= ia.dischtime
                AND a2.admittime <= ia.dischtime + INTERVAL 30 DAY
        ) THEN 1 ELSE 0 END AS readmitted_30d,
        DATE_DIFF(ia.dischtime, ia.admittime, DAY) AS los
    FROM index_admissions ia
)
SELECT
    SUM(readmitted_30d) / COUNT(*) AS readmission_rate,
    PERCENTILE_CONT(los, 0.5) FILTER (readmitted_30d = 1) AS median_los_readmitted,
    PERCENTILE_CONT(los, 0.5) FILTER (readmitted_30d = 0) AS median_los_not_readmitted,
    SUM(CASE WHEN los > 4 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percent_los_gt4
FROM readmission_flag;
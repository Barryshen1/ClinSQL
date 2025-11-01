WITH eligible_patients AS (
    SELECT
        subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
        gender = 'M'
        AND anchor_age BETWEEN 67 AND 77
),
admissions_with_los AS (
    SELECT
        a.hadm_id,
        a.subject_id,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        CASE
            WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
            WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
            ELSE NULL
        END AS los_group
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
        eligible_patients p ON a.subject_id = p.subject_id
    WHERE
        a.dischtime IS NOT NULL
        AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
hf_diagnoses AS (
    SELECT
        d.hadm_id,
        d.subject_id,
        MIN(d.seq_num) AS min_seq_num,
        CASE
            WHEN MIN(d.seq_num) = 1 THEN 'primary'
            ELSE 'secondary'
        END AS hf_type
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
    WHERE
        (dd.icd_version = 9 AND dd.icd_code LIKE '428%')
        OR (dd.icd_version = 10 AND dd.icd_code LIKE 'I50%')
    GROUP BY
        d.hadm_id, d.subject_id
),
imaging_counts AS (
    SELECT
        h.hadm_id,
        COUNT(*) AS imaging_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh ON h.hcpcs_cd = dh.code
    WHERE
        dh.long_description LIKE '%imaging%'
        OR dh.long_description LIKE '%x-ray%'
        OR dh.long_description LIKE '%radiograph%'
        OR dh.long_description LIKE '%CT%'
        OR dh.long_description LIKE '%MRI%'
        OR dh.long_description LIKE '%ultrasound%'
        OR dh.long_description LIKE '%echo%'
        OR dh.long_description LIKE '%scan%'
        OR dh.long_description LIKE '%angiogram%'
        OR dh.long_description LIKE '%PET%'
    GROUP BY
        h.hadm_id
),
combined_data AS (
    SELECT
        a.hadm_id,
        a.los_group,
        h.hf_type,
        COALESCE(i.imaging_count, 0) AS imaging_count
    FROM
        admissions_with_los a
    INNER JOIN
        hf_diagnoses h ON a.hadm_id = h.hadm_id
    LEFT JOIN
        imaging_counts i ON a.hadm_id = i.hadm_id
)
SELECT
    los_group,
    hf_type,
    APPROX_QUANTILES(imaging_count, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(imaging_count, 100)[OFFSET(50)] AS p50,
    APPROX_QUANTILES(imaging_count, 100)[OFFSET(75)] AS p75
FROM
    combined_data
GROUP BY
    los_group, hf_type
ORDER BY
    los_group, hf_type;
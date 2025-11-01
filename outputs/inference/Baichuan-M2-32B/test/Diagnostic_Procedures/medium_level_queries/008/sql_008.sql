WITH admissions_with_los AS (
    SELECT
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        p.gender,
        p.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 58 AND 68
        AND a.admittime IS NOT NULL
        AND a.dischtime IS NOT NULL
        AND a.dischtime > a.admittime
        AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
procedures_count AS (
    SELECT
        awl.hadm_id,
        COUNT(pr.seq_num) AS procedure_count
    FROM
        admissions_with_los awl
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
        ON awl.hadm_id = pr.hadm_id
        AND pr.icd_code IN ('38.21', '38.22')  -- Radiography and CT scan
        AND pr.icd_version = 9
    GROUP BY
        awl.hadm_id
)
SELECT
    CASE
        WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
        WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    COUNT(DISTINCT awl.subject_id) AS patient_count,
    COUNT(awl.hadm_id) AS admission_count,
    AVG(pc.procedure_count) AS mean_radiography_ct_procedures
FROM
    admissions_with_los awl
LEFT JOIN
    procedures_count pc
    ON awl.hadm_id = pc.hadm_id
GROUP BY
    los_group
ORDER BY
    los_group;
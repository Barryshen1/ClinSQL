WITH base_admissions AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        a.discharge_location,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
        CASE
            WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
            WHEN a.discharge_location LIKE '%Hospice%' THEN 'Hospice'
            WHEN a.discharge_location LIKE '%Home%' OR a.discharge_location = 'Home Health Care' THEN 'Home'
            ELSE 'Other'
        END AS discharge_disposition,
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 49 AND 59
),
last_services AS (
    SELECT
        subject_id,
        hadm_id,
        curr_service
    FROM (
        SELECT
            s.subject_id,
            s.hadm_id,
            s.curr_service,
            ROW_NUMBER() OVER (PARTITION BY s.subject_id, s.hadm_id ORDER BY s.transfertime DESC) AS rn
        FROM
            `physionet-data.mimiciv_3_1_hosp.services` s
        INNER JOIN
            base_admissions b
            ON s.subject_id = b.subject_id AND s.hadm_id = b.hadm_id
        WHERE
            s.transfertime <= b.dischtime
    )
    WHERE
        rn = 1
)
SELECT
    b.discharge_disposition,
    COUNT(*) AS total_admissions,
    SUM(CASE WHEN b.los >= 7 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS prop_ge7,
    SUM(CASE WHEN b.los >= 14 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS prop_ge14,
    APPROX_QUANTILES(b.los, 100)[OFFSET(74)] AS p75_los
FROM
    base_admissions b
INNER JOIN
    last_services ls
    ON b.subject_id = ls.subject_id AND b.hadm_id = ls.hadm_id
WHERE
    ls.curr_service = 'Medicine'
GROUP BY
    b.discharge_disposition
ORDER BY
    b.discharge_disposition;
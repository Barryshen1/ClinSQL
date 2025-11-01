WITH eligible_patients AS (
    SELECT
        subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE
        gender = 'M'
        AND anchor_age BETWEEN 40 AND 50
),
admissions_with_ami AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        DATEDIFF(a.dischtime, a.admittime) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    WHERE
        EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
                ON d.icd_code = dd.icd_code
                AND d.icd_version = dd.icd_version
            WHERE
                d.hadm_id = a.hadm_id
                AND dd.icd_version = 10
                AND dd.long_title LIKE 'I21%'
        )
        AND NOT EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
                ON d.icd_code = dd.icd_code
                AND d.icd_version = dd.icd_version
            WHERE
                d.hadm_id = a.hadm_id
                AND (dd.long_title LIKE '%shock%' OR dd.long_title LIKE '%respiratory failure%')
        )
        AND a.subject_id IN (SELECT subject_id FROM eligible_patients)
),
day1_icu_status AS (
    SELECT
        a.hadm_id,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_icu.icustays` i
                WHERE
                    i.hadm_id = a.hadm_id
                    AND DATE(i.intime) = DATE(a.admittime)
            ) THEN 'Yes'
            ELSE 'No'
        END AS day1_icu
    FROM
        admissions_with_ami a
),
los_groups AS (
    SELECT
        *,
        CASE
            WHEN los_days <= 5 THEN 'LOS <=5'
            ELSE 'LOS >5'
        END AS los_category
    FROM
        admissions_with_ami
),
final_data AS (
    SELECT
        g.los_category,
        d.day1_icu,
        AVG(g.hospital_expire_flag) * 100 AS mortality_rate,
        APPROX_QUANTILES(g.los_days, 100)[OFFSET(50)] AS median_los
    FROM
        los_groups g
    JOIN
        day1_icu_status d
        ON g.hadm_id = d.hadm_id
    GROUP BY
        g.los_category,
        d.day1_icu
)
SELECT
    los_category,
    day1_icu,
    mortality_rate,
    median_los
FROM
    final_data
ORDER BY
    los_category,
    day1_icu;
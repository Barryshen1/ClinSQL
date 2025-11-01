WITH cohort AS (
    SELECT DISTINCT p.subject_id, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 60 AND 70
        AND a.hadm_id IN (
            SELECT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE (
                (di.icd_version = 10 AND di.icd_code LIKE 'T81%')
                OR (di.icd_version = 9 AND di.icd_code LIKE '998%')
            )
        )
),

los_data AS (
    SELECT a.hadm_id,
        DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los,
        CASE
            WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 1 AND 3 THEN '1-3'
            WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 4 AND 7 THEN '4-7'
            ELSE '>=8'
        END AS los_bucket,
        a.hospital_expire_flag,
        a.deathtime,
        a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),

icu_flag AS (
    SELECT hadm_id,
        CASE WHEN COUNT(stay_id) > 0 THEN 'ICU' ELSE 'non-ICU' END AS icu_status
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY hadm_id
)

SELECT
    icu.icu_status,
    los.los_bucket,
    CASE
        WHEN c.charlson_comorbidity_index <= 3 THEN '<=3'
        WHEN c.charlson_comorbidity_index BETWEEN 4 AND 5 THEN '4-5'
        ELSE '>5'
    END AS charlson_bucket,
    COUNT(*) AS n,
    ROUND(100 * SUM(los.hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
    APPROX_QUANTILES(
        CASE WHEN los.hospital_expire_flag = 1 
             THEN DATETIME_DIFF(los.deathtime, los.admittime, HOUR) 
             ELSE NULL 
        END,
        2
    )[OFFSET(1)] AS median_time_to_death_hours
FROM cohort co
INNER JOIN los_data los ON co.hadm_id = los.hadm_id
LEFT JOIN `physionet-data.mimiciv_derived.charlson` c ON co.hadm_id = c.hadm_id
LEFT JOIN icu_flag icu ON co.hadm_id = icu.hadm_id
GROUP BY icu.icu_status, los.los_bucket, charlson_bucket
ORDER BY icu.icu_status, los.los_bucket, charlson_bucket;
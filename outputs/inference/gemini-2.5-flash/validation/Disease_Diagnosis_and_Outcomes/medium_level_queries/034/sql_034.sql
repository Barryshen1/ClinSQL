WITH admissions_with_hf AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.deathtime,
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Calculate time_to_death_days only for in-hospital deaths (non-survivors)
        CASE
            WHEN adm.hospital_expire_flag = 1 THEN DATE_DIFF(adm.deathtime, adm.admittime, DAY)
            ELSE NULL -- For survivors, time_to_death_days is not applicable
        END AS time_to_death_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 70 AND 80
        AND (
            (diag.icd_version = 9 AND diag.icd_code LIKE '428%') -- ICD-9 codes for Heart Failure (e.g., 428.0 for CHF)
            OR
            (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%') -- ICD-10 codes for Heart Failure
        )
    GROUP BY
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.deathtime,
        adm.hospital_expire_flag
)
SELECT
    CASE
        WHEN los_days IS NULL THEN 'Unknown LOS' 
        WHEN los_days < 8 THEN '< 8 days'
        ELSE '>= 8 days'
    END AS los_group,
    COUNT(DISTINCT hadm_id) AS admission_count,
    ROUND(
        SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(DISTINCT hadm_id), 0)
        , 2
    ) AS mortality_rate_percent,
    -- APPROX_QUANTILES ignores NULLs, so it correctly computes median for non-survivors only
    APPROX_QUANTILES(time_to_death_days, 2)[OFFSET(1)] AS median_time_to_death_days
FROM
    admissions_with_hf
GROUP BY
    los_group
ORDER BY
    los_group;
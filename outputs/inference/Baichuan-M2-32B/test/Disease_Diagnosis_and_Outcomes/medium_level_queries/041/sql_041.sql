WITH cohort AS (
    SELECT 
        admissions.subject_id,
        admissions.hadm_id,
        admissions.admittime,
        admissions.dischtime,
        admissions.deathtime,
        admissions.hospital_expire_flag,
        TIMESTAMP_DIFF(admissions.dischtime, admissions.admittime, DAY) AS los
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` 
        ON admissions.subject_id = patients.subject_id
    WHERE patients.gender = 'F'
        AND patients.anchor_age BETWEEN 50 AND 60
        AND EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year + patients.anchor_age BETWEEN 50 AND 60
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE diagnoses_icd.subject_id = admissions.subject_id 
                AND diagnoses_icd.hadm_id = admissions.hadm_id
                AND diagnoses_icd.icd_version = 10
                AND diagnoses_icd.icd_code LIKE 'A40%'
                AND diagnoses_icd.icd_code NOT LIKE 'A41%'
        )
),
mortality_rates AS (
    SELECT 
        CASE WHEN los <= 7 THEN 'short' ELSE 'long' END AS los_group,
        COUNT(*) AS total_admissions,
        SUM(hospital_expire_flag) AS deaths,
        (SUM(hospital_expire_flag) * 100.0 / COUNT(*)) AS mortality_rate
    FROM cohort
    GROUP BY los_group
),
short_group AS (
    SELECT mortality_rate AS mortality_rate_short
    FROM mortality_rates
    WHERE los_group = 'short'
),
long_group AS (
    SELECT mortality_rate AS mortality_rate_long
    FROM mortality_rates
    WHERE los_group = 'long'
),
median_death_time AS (
    SELECT 
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TIMESTAMP_DIFF(deathtime, admittime, HOUR)) AS median_time_to_death
    FROM cohort
    WHERE hospital_expire_flag = 1
        AND deathtime IS NOT NULL
)
SELECT 
    short_group.mortality_rate_short,
    long_group.mortality_rate_long,
    (long_group.mortality_rate_long - short_group.mortality_rate_short) AS absolute_difference,
    ((long_group.mortality_rate_long - short_group.mortality_rate_short) / NULLIF(short_group.mortality_rate_short, 0)) * 100 AS relative_difference,
    median_death_time.median_time_to_death
FROM short_group, long_group, median_death_time;
WITH
-- CTE to identify hospital admissions with a sepsis diagnosis using specific ICD codes
sepsis_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_code IN ('99591', '99592') AND icd_version = 9)
        OR
        (icd_code LIKE 'A41%' AND icd_version = 10)
),

-- CTE to identify hospital admissions with a septic shock diagnosis for exclusion
septic_shock_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_code = '78552' AND icd_version = 9)
        OR
        (icd_code = 'R6521' AND icd_version = 10)
),

-- CTE to define the main cohort based on demographics and diagnoses, and calculate primary metrics
cohort AS (
    SELECT
        adm.hadm_id,
        adm.hospital_expire_flag,
        -- Calculate hospital length of stay in days
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS hospital_los_days,
        -- Calculate time from admission to death in hours for those who died
        DATETIME_DIFF(adm.deathtime, adm.admittime, HOUR) AS time_to_death_hours
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON pat.subject_id = adm.subject_id
    WHERE
        -- 1. Filter for female patients
        pat.gender = 'F'
        -- 2. Filter for age between 50 and 60
        AND pat.anchor_age BETWEEN 50 AND 60
        -- 3. Include admissions with sepsis
        AND adm.hadm_id IN (SELECT hadm_id FROM sepsis_admissions)
        -- 4. Exclude admissions with septic shock
        AND adm.hadm_id NOT IN (SELECT hadm_id FROM septic_shock_admissions)
),

-- CTE to group by LOS category and calculate aggregated statistics
los_stats AS (
    SELECT
        CASE
            WHEN hospital_los_days <= 7 THEN 'LOS <= 7 days'
            ELSE 'LOS > 7 days'
        END AS los_group,
        -- Calculate mortality rate as a percentage
        AVG(hospital_expire_flag) * 100 AS mortality_pct,
        -- Calculate median time to death in hours, only for patients who died
        APPROX_QUANTILES(
            CASE WHEN hospital_expire_flag = 1 THEN time_to_death_hours END, 2
        )[OFFSET(1)] AS median_time_to_death_hours
    FROM cohort
    GROUP BY los_group
)

-- Final SELECT to pivot results into a single row and calculate differences
SELECT
    le7.mortality_pct AS mortality_pct_los_le7,
    gt7.mortality_pct AS mortality_pct_los_gt7,
    (gt7.mortality_pct - le7.mortality_pct) AS absolute_mortality_difference_pct,
    (gt7.mortality_pct / NULLIF(le7.mortality_pct, 0)) AS relative_risk,
    le7.median_time_to_death_hours AS median_time_to_death_los_le7_hours,
    gt7.median_time_to_death_hours AS median_time_to_death_los_gt7_hours
FROM
    los_stats AS le7
CROSS JOIN
    los_stats AS gt7
WHERE
    le7.los_group = 'LOS <= 7 days' AND gt7.los_group = 'LOS > 7 days';
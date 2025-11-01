WITH adm_patients_base AS (
    -- Step 1: Filter admissions for female patients aged 50-60 and calculate LOS and time-to-death
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.deathtime,
        ad.hospital_expire_flag,
        TIMESTAMP_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        -- Calculate time to death only for those who died in hospital
        CASE
            WHEN ad.hospital_expire_flag = 1 AND ad.deathtime IS NOT NULL AND ad.admittime IS NOT NULL
            THEN TIMESTAMP_DIFF(ad.deathtime, ad.admittime, DAY)
            ELSE NULL
        END AS time_to_death_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 50 AND 60
),
sepsis_admissions AS (
    -- Step 2: Identify admissions with sepsis diagnosis (ICD-10 A40 or A41)
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10
      AND (LEFT(icd_code, 3) = 'A40' OR LEFT(icd_code, 3) = 'A41')
),
septic_shock_admissions AS (
    -- Step 3: Identify admissions with septic shock diagnosis (ICD-10 R6521)
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10
      AND icd_code = 'R6521' -- R65.21 "Severe sepsis with septic shock"
),
final_cohort AS (
    -- Step 4: Combine all filters for the final cohort (sepsis, no septic shock) and categorize LOS
    SELECT
        apb.*,
        CASE
            WHEN apb.los_days <= 7 THEN '<=7 days'
            ELSE '>7 days'
        END AS los_group
    FROM
        adm_patients_base apb
    INNER JOIN
        sepsis_admissions sa
        ON apb.hadm_id = sa.hadm_id
    LEFT JOIN
        septic_shock_admissions ssa
        ON apb.hadm_id = ssa.hadm_id
    WHERE
        ssa.hadm_id IS NULL -- Exclude admissions with septic shock
        AND apb.los_days IS NOT NULL -- Ensure LOS is calculated for categorization
),
median_time_to_death_per_los_group AS (
    -- Calculate median time to death for each LOS group separately
    SELECT
        los_group,
        PERCENTILE_CONT(time_to_death_days, 0.5) OVER (PARTITION BY los_group) AS median_value
    FROM
        final_cohort
    WHERE
        hospital_expire_flag = 1
        AND time_to_death_days IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY los_group ORDER BY los_group) = 1 -- Select one median value per group
),
mortality_summary_by_los AS (
    -- Step 5 & 6: Calculate mortality statistics and join median time to death
    SELECT
        fc.los_group,
        COUNT(fc.hadm_id) AS total_admissions,
        SUM(CASE WHEN fc.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS num_deaths,
        (SUM(CASE WHEN fc.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0) / COUNT(fc.hadm_id) AS mortality_percent,
        ANY_VALUE(mtd.median_value) AS median_time_to_death_days -- Use ANY_VALUE as median_value is constant per los_group
    FROM
        final_cohort fc
    LEFT JOIN
        median_time_to_death_per_los_group mtd
        ON fc.los_group = mtd.los_group
    GROUP BY
        fc.los_group
)
-- Step 7: Calculate absolute and relative differences
SELECT
    m_le7.los_group AS los_group_le7,
    m_le7.total_admissions AS total_admissions_le7,
    m_le7.num_deaths AS num_deaths_le7,
    m_le7.mortality_percent AS mortality_percent_le7,
    m_le7.median_time_to_death_days AS median_time_to_death_le7,
    m_gt7.los_group AS los_group_gt7,
    m_gt7.total_admissions AS total_admissions_gt7,
    m_gt7.num_deaths AS num_deaths_gt7,
    m_gt7.mortality_percent AS mortality_percent_gt7,
    m_gt7.median_time_to_death_days AS median_time_to_death_gt7,
    (IFNULL(m_gt7.mortality_percent, 0) - IFNULL(m_le7.mortality_percent, 0)) AS absolute_difference_percent,
    (CASE WHEN IFNULL(m_le7.mortality_percent, 0) != 0
          THEN ((IFNULL(m_gt7.mortality_percent, 0) - IFNULL(m_le7.mortality_percent, 0)) / m_le7.mortality_percent) * 100
          ELSE NULL -- Avoid division by zero
     END) AS relative_difference_percentage
FROM
    mortality_summary_by_los m_le7
CROSS JOIN
    mortality_summary_by_los m_gt7
WHERE
    m_le7.los_group = '<=7 days'
    AND m_gt7.los_group = '>7 days';
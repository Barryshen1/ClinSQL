WITH base_admissions AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.deathtime,
        a.hospital_expire_flag,
        a.admission_type,
        p.gender,
        p.anchor_age,
        -- Calculate LOS in days
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 66 AND 76
        -- Filter for AMI using diagnoses_icd
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = a.hadm_id
                AND d.icd_code LIKE 'I21%'
                AND d.icd_version = 10
        )
        -- Exclude shock using diagnoses_icd
        AND NOT EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = a.hadm_id
                AND d.icd_code IN (
                    'R57', 'R65.82', 'R65.89', 'R96.83', 'I46.9', 'R57.0', 'R57.1', 'R57.2', 'R57.3', 'R57.4', 'R57.5', 'R57.6', 'R57.7', 'R57.8', 'R57.9'
                )
                AND d.icd_version = 10
        )
        -- Exclude respiratory failure using diagnoses_icd
        AND NOT EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = a.hadm_id
                AND d.icd_code IN (
                    'J98.9', 'J95.8', 'J96.9', 'R06.81', 'R06.82', 'R06.83', 'R06.89', 'J98.8', 'J98.0', 'J98.1', 'J98.2', 'J98.3', 'J98.4', 'J98.5', 'J98.6', 'J98.7'
                )
                AND d.icd_version = 10
        )
),
los_groups AS (
    SELECT
        *,
        CASE
            WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
            WHEN los_days >= 8 THEN '>=8 days'
            ELSE 'Unknown'
        END AS los_category
    FROM base_admissions
),
mortality_data AS (
    SELECT
        *,
        -- Calculate time-to-death in days for deceased patients
        CASE
            WHEN hospital_expire_flag = 1 THEN DATE_DIFF(deathtime, admittime, DAY)
            ELSE NULL
        END AS time_to_death
    FROM los_groups
),
admission_type_grouped AS (
    SELECT
        *,
        CASE
            WHEN admission_type IN ('EMERGENCY', 'URGENT') THEN 'Emergent'
            ELSE 'Non-emergent'
        END AS admission_type_group
    FROM mortality_data
),
grouped_data AS (
    SELECT
        los_category,
        admission_type_group,
        -- Count total patients per group
        COUNT(*) AS total_patients,
        -- Count deceased patients
        SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deceased_count,
        -- Collect time-to-death for deceased to compute median
        ARRAY_AGG(
            CASE WHEN hospital_expire_flag = 1 THEN time_to_death END
            IGNORE NULLS
        ) AS time_to_death_array
    FROM admission_type_grouped
    GROUP BY los_category, admission_type_group
)
SELECT
    los_category,
    admission_type_group,
    -- Calculate mortality rate
    (deceased_count * 100.0 / total_patients) AS mortality_rate_percent,
    -- Calculate median time-to-death using APPROX_QUANTILES
    APPROX_QUANTILES(time_to_death_array, 100)[OFFSET(50)] AS median_time_to_death_days
FROM grouped_data
GROUP BY los_category, admission_type_group, total_patients, deceased_count, time_to_death_array
ORDER BY los_category, admission_type_group;
WITH cohort_demographics AS (
    SELECT
        p.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        -- Calculate age at admission: anchor_age is at anchor_year
        p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year) AS age_at_admission,
        -- Calculate hospital length of stay in days
        DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_hospital
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON p.subject_id = ad.subject_id
    WHERE
        p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year)) BETWEEN 40 AND 50
),
-- CTE 2: Identify admissions with Acute Myocardial Infarction (AMI) diagnosis
ami_admissions AS (
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE
        (di.icd_version = 9 AND di.icd_code LIKE '410%') -- ICD-9 AMI codes (410.x)
        OR (di.icd_version = 10 AND di.icd_code LIKE 'I21%') -- ICD-10 AMI codes (I21.x)
),
-- CTE 3: Identify admissions with Shock or Respiratory Failure diagnoses for exclusion
exclusion_admissions AS (
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE
        (
            -- Shock ICD-9 codes
            (di.icd_version = 9 AND di.icd_code LIKE '7855%') -- e.g., 785.50-785.59 for Shock
            OR (di.icd_version = 9 AND di.icd_code = '99592')  -- Severe sepsis (often associated with shock)
            -- Shock ICD-10 codes
            OR (di.icd_version = 10 AND (di.icd_code LIKE 'R57%' OR di.icd_code LIKE 'T811%' OR di.icd_code = 'I951' OR di.icd_code = 'R6521'))
            -- R57.x (Shock, unspecified), T81.1x (Postprocedural shock), I95.1 (Cardiogenic shock), R65.21 (Septic shock)
        )
        OR
        (
            -- Respiratory Failure ICD-9 codes
            (di.icd_version = 9 AND di.icd_code IN ('51881', '51883', '51884')) -- Acute, Chronic, Acute on Chronic Respiratory Failure
            -- Respiratory Failure ICD-10 codes
            OR (di.icd_version = 10 AND di.icd_code LIKE 'J96%') -- J96.x (Respiratory failure)
        )
),
-- CTE 4: Filter cohort based on AMI presence and exclusion criteria (no shock or respiratory failure)
filtered_cohort AS (
    SELECT
        cd.subject_id,
        cd.hadm_id,
        cd.admittime,
        cd.dischtime,
        cd.hospital_expire_flag,
        cd.age_at_admission,
        cd.los_hospital
    FROM
        cohort_demographics cd
    INNER JOIN
        ami_admissions ami
        ON cd.hadm_id = ami.hadm_id -- Must have an AMI diagnosis
    LEFT JOIN
        exclusion_admissions excl
        ON cd.hadm_id = excl.hadm_id
    WHERE
        excl.hadm_id IS NULL -- Exclude admissions with shock or respiratory failure diagnoses
),
-- CTE 5: Determine Day-1 ICU Status for each admission in the filtered cohort
cohort_with_icu_status AS (
    SELECT
        fc.*,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
                WHERE
                    icu.hadm_id = fc.hadm_id
                    AND icu.intime BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 1 DAY)
            ) THEN 'ICU Day 1'
            ELSE 'No ICU Day 1'
        END AS day1_icu_status
    FROM
        filtered_cohort fc
)
-- Final aggregation to report mortality and median LOS by LOS bucket and Day-1 ICU status
SELECT
    CASE
        WHEN los_hospital <= 5 THEN 'LOS <= 5 days'
        ELSE 'LOS > 5 days'
    END AS los_bucket,
    day1_icu_status,
    COUNT(hadm_id) AS number_of_admissions,
    -- Calculate in-hospital mortality as a percentage
    ROUND(AVG(CAST(hospital_expire_flag AS BIGNUMERIC)) * 100, 2) AS in_hospital_mortality_percent,
    -- Calculate median hospital LOS for each group.
    -- Removed OVER(...) as PERCENTILE_CONT should act as a simple aggregate here,
    -- grouped by LOS_bucket and day1_icu_status.
    PERCENTILE_CONT(los_hospital, 0.5) AS median_los_days
FROM
    cohort_with_icu_status
GROUP BY
    los_bucket,
    day1_icu_status
ORDER BY
    los_bucket,
    day1_icu_status;
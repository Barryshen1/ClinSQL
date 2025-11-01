WITH AdmissionsWithDiagnosisFlags AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        ad.discharge_location,
        pat.gender,
        pat.anchor_age,
        -- Calculate LOS in whole calendar days (number of midnights crossed)
        DATE_DIFF(CAST(ad.dischtime AS DATE), CAST(ad.admittime AS DATE), DAY) AS los_days,
        -- Flag for Acute Myocardial Infarction
        MAX(CASE
            WHEN dicd.long_title LIKE '%myocardial infarction%' THEN 1
            ELSE 0
        END) AS has_ami,
        -- Flag for Shock (excluding non-medical contexts)
        MAX(CASE
            WHEN dicd.long_title LIKE '%shock%'
                 AND dicd.long_title NOT LIKE '%electric shock%'
                 AND dicd.long_title NOT LIKE '%shock wave%' THEN 1
            ELSE 0
        END) AS has_shock,
        -- Flag for Respiratory Failure
        MAX(CASE
            WHEN dicd.long_title LIKE '%respiratory failure%' THEN 1
            ELSE 0
        END) AS has_resp_failure
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON ad.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dic
        ON ad.subject_id = dic.subject_id AND ad.hadm_id = dic.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
        ON dic.icd_code = dicd.icd_code AND dic.icd_version = dicd.icd_version
    GROUP BY
        ad.subject_id, ad.hadm_id, ad.admittime, ad.dischtime, ad.hospital_expire_flag, ad.discharge_location, pat.gender, pat.anchor_age
),
-- Step 2: Filter the cohort based on the specified criteria and categorize LOS
CohortFiltered AS (
    SELECT
        hadm_id,
        hospital_expire_flag,
        los_days,
        discharge_location,
        -- Categorize LOS into required buckets
        CASE
            WHEN los_days >= 1 AND los_days <= 3 THEN '1-3 days'
            WHEN los_days >= 4 AND los_days <= 7 THEN '4-7 days'
            WHEN los_days >= 8 THEN '>=8 days'
            ELSE 'LOS < 1 day' -- For stays less than a full calendar day
        END AS los_category
    FROM
        AdmissionsWithDiagnosisFlags
    WHERE
        gender = 'M' -- Men
        AND anchor_age BETWEEN 69 AND 79 -- Age range 69-79
        AND has_ami = 1 -- With AMI diagnosis
        AND has_shock = 0 -- Without Shock diagnosis
        AND has_resp_failure = 0 -- Without Respiratory Failure diagnosis
        AND los_days >= 0 -- Ensure all valid LOS are considered before categorization
)
-- Step 3: Aggregate results by LOS category and discharge destination
SELECT
    los_category,
    discharge_location,
    COUNT(DISTINCT c.hadm_id) AS total_admissions,
    SUM(c.hospital_expire_flag) AS total_deaths,
    SAFE_DIVIDE(SUM(c.hospital_expire_flag), COUNT(DISTINCT c.hadm_id)) * 100 AS mortality_percentage,
    -- CORRECTED: Use APPROX_QUANTILES for approximate median in BigQuery
    APPROX_QUANTILES(c.los_days, 2)[OFFSET(1)] AS median_los_days -- [OFFSET(1)] gets the 50th percentile (median)
FROM
    CohortFiltered AS c
WHERE c.los_category != 'LOS < 1 day' -- Exclude admissions with LOS less than 1 day from final analysis, as the question focuses on 1-3, 4-7, >=8 days.
GROUP BY
    los_category, discharge_location
ORDER BY
    los_category, discharge_location;
WITH CohortAdmissions AS (
    -- Select eligible hospital admissions based on gender, age, and pneumonia diagnosis
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 39 AND 49
        -- Ensure the admission has at least one relevant pneumonia diagnosis
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE
                diag.subject_id = adm.subject_id
                AND diag.hadm_id = adm.hadm_id
                AND diag.icd_version = 10 -- MIMIC-IV uses ICD-10
                AND (
                    diag.icd_code LIKE 'J13%' OR diag.icd_code LIKE 'J14%' OR diag.icd_code LIKE 'J15%' OR 
                    diag.icd_code LIKE 'J16%' OR diag.icd_code LIKE 'J17%' OR diag.icd_code LIKE 'J18%' OR -- Common CAP codes
                    diag.icd_code LIKE 'J69%'                                                              -- Aspiration Pneumonia
                )
        )
),
AdmissionDetails AS (
    -- Calculate LOS, LOS bucket, and Day-1 ICU status for each admission in the cohort
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.hospital_expire_flag,
        DATE_DIFF(ca.dischtime, ca.admittime, DAY) AS los_days,
        CASE
            WHEN DATE_DIFF(ca.dischtime, ca.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN DATE_DIFF(ca.dischtime, ca.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
            WHEN DATE_DIFF(ca.dischtime, ca.admittime, DAY) >= 8 THEN '>=8 days'
            ELSE 'Excluded (LOS < 1 day)' -- Admissions with LOS=0 or negative are excluded per prompt's bins
        END AS los_bucket,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
                WHERE
                    icu.subject_id = ca.subject_id
                    AND icu.hadm_id = ca.hadm_id
                    AND icu.intime BETWEEN ca.admittime AND DATETIME_ADD(ca.admittime, INTERVAL 1 DAY)
            ) THEN 'ICU Day 1'
            ELSE 'No ICU Day 1'
        END AS day1_icu_status
    FROM
        CohortAdmissions ca
    WHERE DATE_DIFF(ca.dischtime, ca.admittime, DAY) >= 1 -- Filter for admissions with LOS of at least 1 day
),
ComorbidityCounts AS (
    -- Count distinct comorbidities for each admission, excluding the pneumonia diagnoses that qualified them
    SELECT
        ca.subject_id,
        ca.hadm_id,
        COUNT(DISTINCT diag.icd_code) AS comorbidity_count
    FROM
        CohortAdmissions ca
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON ca.subject_id = diag.subject_id AND ca.hadm_id = diag.hadm_id
    WHERE
        diag.icd_version = 10 -- Ensure ICD-10 codes
        AND NOT ( -- Exclude the pneumonia codes that define the cohort
            diag.icd_code LIKE 'J13%' OR diag.icd_code LIKE 'J14%' OR diag.icd_code LIKE 'J15%' OR 
            diag.icd_code LIKE 'J16%' OR diag.icd_code LIKE 'J17%' OR diag.icd_code LIKE 'J18%' OR 
            diag.icd_code LIKE 'J69%'
        )
    GROUP BY
        ca.subject_id,
        ca.hadm_id
),
AggregatedData AS (
    -- Aggregate mortality and comorbidity count by LOS bucket and Day-1 ICU status
    SELECT
        ad.los_bucket,
        ad.day1_icu_status,
        COUNT(DISTINCT ad.hadm_id) AS total_admissions,
        SUM(ad.hospital_expire_flag) AS total_deaths,
        SAFE_DIVIDE(SUM(ad.hospital_expire_flag), COUNT(DISTINCT ad.hadm_id)) * 100 AS mortality_percentage,
        AVG(COALESCE(cc.comorbidity_count, 0)) AS avg_comorbidity_count -- Use COALESCE to treat NULL comorbidity counts as 0
    FROM
        AdmissionDetails ad
    LEFT JOIN -- Use LEFT JOIN since an admission might have no other comorbidities
        ComorbidityCounts cc
        ON ad.subject_id = cc.subject_id AND ad.hadm_id = cc.hadm_id
    WHERE
        ad.los_bucket <> 'Excluded (LOS < 1 day)' -- Only include admissions within the specified LOS bins
    GROUP BY
        ad.los_bucket,
        ad.day1_icu_status
),
OverallCohortMortality AS (
    -- Calculate overall mortality for the entire cohort as a reference point
    SELECT
        SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(DISTINCT hadm_id)) * 100 AS overall_mortality_percentage
    FROM
        AdmissionDetails
    WHERE
        los_bucket <> 'Excluded (LOS < 1 day)' -- Consistent with aggregated data
)
-- Final result combining aggregated data with overall mortality and calculating differences
SELECT
    ad.los_bucket,
    ad.day1_icu_status,
    ad.total_admissions,
    ad.total_deaths,
    ROUND(ad.mortality_percentage, 2) AS mortality_percentage,
    ROUND(ad.avg_comorbidity_count, 2) AS avg_comorbidity_count,
    ROUND(ad.mortality_percentage - ocm.overall_mortality_percentage, 2) AS absolute_mortality_difference_from_cohort_avg,
    ROUND(SAFE_DIVIDE(ad.mortality_percentage - ocm.overall_mortality_percentage, ocm.overall_mortality_percentage) * 100, 2) AS relative_mortality_difference_from_cohort_avg_percent
FROM
    AggregatedData ad,
    OverallCohortMortality ocm -- Cross join to get the single overall mortality value
ORDER BY
    CASE
        WHEN ad.los_bucket = '1-3 days' THEN 1
        WHEN ad.los_bucket = '4-7 days' THEN 2
        WHEN ad.los_bucket = '>=8 days' THEN 3
        ELSE 4 -- Fallback for any unexpected cases, though filtered now
    END,
    ad.day1_icu_status;
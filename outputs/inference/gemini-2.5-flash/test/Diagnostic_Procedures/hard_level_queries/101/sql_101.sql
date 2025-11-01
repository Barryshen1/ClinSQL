WITH
-- 1. Identify the target cohort: Male ICU patients (88-98) with COPD exacerbation
TargetCohort AS (
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.los,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON icu.subject_id = adm.subject_id AND icu.hadm_id = adm.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON icu.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 88 AND 98
        -- Filter for COPD exacerbation diagnosis
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
            WHERE
                diag.subject_id = icu.subject_id
                AND diag.hadm_id = icu.hadm_id
                AND (
                    -- Common ICD-9 codes for COPD exacerbation
                    (diag.icd_version = 9 AND diag.icd_code IN ('49121', '4928', '496'))
                    -- Common ICD-10 code for COPD with acute exacerbation
                    OR (diag.icd_version = 10 AND diag.icd_code = 'J441')
                )
        )
),
-- 2. Count distinct procedures for the target cohort within the first 72 hours of ICU stay
--    This CTE includes all target cohort stays, even those with 0 procedures in the window.
TargetCohortProceduresCount AS (
    SELECT
        tc.stay_id,
        COUNT(DISTINCT proc.icd_code) AS distinct_procedures_72hr
    FROM
        TargetCohort AS tc
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
        ON tc.subject_id = proc.subject_id
        AND tc.hadm_id = proc.hadm_id
        -- Procedures within the first 72 hours of ICU intime.
        -- Given proc.chartdate is DATE, we use date comparison for approximation.
        -- This covers procedures on the same day as intime, plus the next two calendar days.
        AND DATE(proc.chartdate) >= DATE(tc.intime)
        AND DATE(proc.chartdate) < DATE_ADD(DATE(tc.intime), INTERVAL 3 DAY)
    GROUP BY
        tc.stay_id
),
-- 3. Intermediate CTE to combine TargetCohort data with procedure counts for ease of aggregation
TargetCohortFlattened AS (
    SELECT
        tc.stay_id,
        tc.los,
        tc.hospital_expire_flag,
        COALESCE(tcp.distinct_procedures_72hr, 0) AS distinct_procedures_72hr_value
    FROM
        TargetCohort AS tc
    LEFT JOIN
        TargetCohortProceduresCount AS tcp
        ON tc.stay_id = tcp.stay_id
),
-- 4. Identify the age-matched comparison group: All ICU patients (88-98)
ComparisonCohort AS (
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.los,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON icu.subject_id = adm.subject_id AND icu.hadm_id = adm.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON icu.subject_id = p.subject_id
    WHERE
        p.anchor_age BETWEEN 88 AND 98
)
-- Final selection of results
SELECT
    -- Target Cohort Results
    (SELECT APPROX_QUANTILES(tf.distinct_procedures_72hr_value, 100)[OFFSET(75)] FROM TargetCohortFlattened tf) AS target_p75_distinct_procedures_72hr,
    (SELECT AVG(tf.los) FROM TargetCohortFlattened tf) AS target_mean_icu_los,
    (SELECT SUM(tf.hospital_expire_flag) * 100.0 / COUNT(tf.stay_id) FROM TargetCohortFlattened tf) AS target_in_hospital_mortality_rate,
    -- Comparison Cohort Results
    AVG(cc.los) AS comparison_mean_icu_los,
    SUM(cc.hospital_expire_flag) * 100.0 / COUNT(DISTINCT cc.stay_id) AS comparison_in_hospital_mortality_rate
FROM
    ComparisonCohort AS cc
-- This last FROM clause is mainly to allow the independent subqueries to aggregate.
-- Since the subqueries are scalar, they don't depend on the rows of ComparisonCohort for their result,
-- but a FROM clause is always required in a SELECT statement.
-- The comparison cohort calculations are also aggregating across the entire cohort.
LIMIT 1; -- Ensures only one row of results is returned, as all are scalar aggregates.;
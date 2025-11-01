WITH acs_diagnoses AS (
    -- Step 1: Identify all hospital admissions with an ACS diagnosis (ICD-9 or ICD-10)
    SELECT DISTINCT
        hadm.subject_id,
        hadm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS hadm
    WHERE
        (
            hadm.icd_version = 9 AND (
                hadm.icd_code LIKE '410%' OR -- Acute myocardial infarction
                hadm.icd_code LIKE '411%' OR -- Other acute and subacute forms of ischemic heart disease (e.g., Unstable angina)
                hadm.icd_code LIKE '413%' OR -- Angina pectoris
                hadm.icd_code LIKE '414.0%'   -- Coronary atherosclerosis, usually implying acute context here
            )
        )
        OR
        (
            hadm.icd_version = 10 AND (
                hadm.icd_code LIKE 'I20%' OR -- Angina pectoris (I20.0 for unstable angina)
                hadm.icd_code LIKE 'I21%' OR -- Acute myocardial infarction
                hadm.icd_code LIKE 'I22%' OR -- Subsequent myocardial infarction
                hadm.icd_code LIKE 'I24%'    -- Other acute ischemic heart diseases
            )
        )
),
acs_cohort AS (
    -- Step 2: Define the target ACS Female Cohort (53-63 years old)
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    INNER JOIN acs_diagnoses AS acs_d
        ON ad.subject_id = acs_d.subject_id AND ad.hadm_id = acs_d.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 53 AND 63
),
acs_admission_abnormal_labs AS (
    -- Helper CTE: Identify distinct abnormal lab categories for each ACS admission within 72 hours
    SELECT
        ac.hadm_id,
        dli.category
    FROM acs_cohort AS ac
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON ac.subject_id = le.subject_id
        AND ac.hadm_id = le.hadm_id
        AND le.charttime BETWEEN ac.admittime AND DATETIME_ADD(ac.admittime, INTERVAL 72 HOUR)
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
        ON le.itemid = dli.itemid
    WHERE
        le.flag = 'abnormal'
),
acs_cohort_scores AS (
    -- Step 3: Calculate Lab Instability Score (count of distinct abnormal lab categories) for each ACS admission
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.admittime,
        ac.dischtime,
        ac.hospital_expire_flag,
        COUNT(DISTINCT anal.category) AS instability_score
    FROM acs_cohort AS ac
    LEFT JOIN acs_admission_abnormal_labs AS anal
        ON ac.hadm_id = anal.hadm_id
    GROUP BY
        ac.subject_id,
        ac.hadm_id,
        ac.admittime,
        ac.dischtime,
        ac.hospital_expire_flag
),
acs_cohort_quartiles AS (
    -- Step 4: Assign Quartiles based on instability score and calculate LOS for the ACS Cohort
    SELECT
        acs.subject_id,
        acs.hadm_id,
        acs.hospital_expire_flag,
        DATETIME_DIFF(acs.dischtime, acs.admittime, HOUR) / 24.0 AS los_days,
        acs.instability_score,
        NTILE(4) OVER (ORDER BY acs.instability_score, acs.hadm_id) AS quartile -- hadm_id for stable ordering in case of ties
    FROM acs_cohort_scores AS acs
),
acs_quartile_summary AS (
    -- Step 5: Report Mortality and Avg LOS per Quartile for the ACS Cohort
    SELECT
        quartile,
        COUNT(DISTINCT hadm_id) AS num_admissions,
        SUM(hospital_expire_flag) AS num_deaths,
        SAFE_DIVIDE(SUM(hospital_expire_flag) * 100.0, COUNT(hadm_id)) AS mortality_percent,
        AVG(los_days) AS avg_los_days,
        MIN(instability_score) AS min_instability_score,
        MAX(instability_score) AS max_instability_score
    FROM acs_cohort_quartiles
    GROUP BY quartile
    ORDER BY quartile
),
control_cohort AS (
    -- Step 6: Define Control Cohort (Non-ACS Females 53-63)
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    LEFT JOIN acs_diagnoses AS acs_d
        ON ad.subject_id = acs_d.subject_id AND ad.hadm_id = acs_d.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 53 AND 63
        AND acs_d.hadm_id IS NULL -- Exclude admissions that have ANY ACS diagnosis
),
control_admission_abnormal_labs AS (
    -- Helper CTE: Identify distinct abnormal lab categories for each Control admission within 72 hours
    SELECT
        cc.hadm_id,
        dli.category
    FROM control_cohort AS cc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON cc.subject_id = le.subject_id
        AND cc.hadm_id = le.hadm_id
        AND le.charttime BETWEEN cc.admittime AND DATETIME_ADD(cc.admittime, INTERVAL 72 HOUR)
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
        ON le.itemid = dli.itemid
    WHERE
        le.flag = 'abnormal'
),
control_cohort_scores AS (
    -- Step 7: Calculate Lab Instability Score for each Control admission
    SELECT
        cc.subject_id,
        cc.hadm_id,
        COUNT(DISTINCT cnal.category) AS control_instability_score
    FROM control_cohort AS cc
    LEFT JOIN control_admission_abnormal_labs AS cnal
        ON cc.hadm_id = cnal.hadm_id
    GROUP BY
        cc.subject_id,
        cc.hadm_id
)
-- Step 8: Final Select Statement combining results for both parts of the question.
-- Part 1: ACS Cohort Quartile Summary (Mortality, Avg LOS, Instability Score Range)
SELECT
    '1. ACS Cohort Quartile Summary' AS report_section,
    CAST(aqs.quartile AS STRING) AS group_identifier,
    'Quartile' AS group_type,
    aqs.num_admissions,
    aqs.num_deaths,
    aqs.mortality_percent,
    aqs.avg_los_days,
    aqs.min_instability_score,
    aqs.max_instability_score,
    CAST(NULL AS FLOAT64) AS average_instability_score_for_comparison -- Null for summary rows
FROM acs_quartile_summary AS aqs

UNION ALL

-- Part 2: Average Instability Score Comparison between ACS and Control groups
-- Overall Average Instability Score for ACS Cohort
SELECT
    '2. Average Instability Score Comparison' AS report_section,
    'Total Cohort' AS group_identifier,
    'ACS' AS group_type,
    (SELECT COUNT(DISTINCT hadm_id) FROM acs_cohort_scores) AS num_admissions,
    (SELECT SUM(hospital_expire_flag) FROM acs_cohort_scores) AS num_deaths,
    (SELECT SAFE_DIVIDE(SUM(hospital_expire_flag) * 100.0, COUNT(hadm_id)) FROM acs_cohort_scores) AS mortality_percent,
    (SELECT AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) FROM acs_cohort_scores) AS avg_los_days,
    (SELECT MIN(instability_score) FROM acs_cohort_scores) AS min_instability_score,
    (SELECT MAX(instability_score) FROM acs_cohort_scores) AS max_instability_score,
    (SELECT AVG(instability_score) FROM acs_cohort_scores) AS average_instability_score_for_comparison
FROM UNNEST([1]) t -- Fix: Replaced FROM DUAL with FROM UNNEST([1])

UNION ALL

-- Overall Average Instability Score for Control Cohort
SELECT
    '2. Average Instability Score Comparison' AS report_section,
    'Total Cohort' AS group_identifier,
    'Control' AS group_type,
    (SELECT COUNT(DISTINCT hadm_id) FROM control_cohort_scores) AS num_admissions,
    CAST(NULL AS INT64) AS num_deaths, -- Not applicable for control group in this context
    CAST(NULL AS FLOAT64) AS mortality_percent, -- Not applicable
    CAST(NULL AS FLOAT64) AS avg_los_days, -- Not applicable for LOS analysis in this comparison
    (SELECT MIN(control_instability_score) FROM control_cohort_scores) AS min_instability_score,
    (SELECT MAX(control_instability_score) FROM control_cohort_scores) AS max_instability_score,
    (SELECT AVG(control_instability_score) FROM control_cohort_scores) AS average_instability_score_for_comparison
FROM UNNEST([1]) t -- Fix: Replaced FROM DUAL with FROM UNNEST([1])

ORDER BY
    report_section,
    CASE WHEN group_type = 'Quartile' THEN CAST(group_identifier AS INT64) ELSE 99 END, -- Order quartiles numerically, non-quartiles last
    group_type DESC -- ACS Total then Control Total for comparison
;
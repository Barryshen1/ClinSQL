WITH
-- 1. Identify male inpatients aged 40-50 with hemorrhagic stroke
HemorrhagicStrokeAdmissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 40 AND 50
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE
                diag.hadm_id = adm.hadm_id
                AND (
                    (diag.icd_version = 9 AND diag.icd_code IN ('430', '431', '432')) OR
                    (diag.icd_version = 10 AND (diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%'))
                )
        )
),
-- 2. Get lab events within 72 hours for the hemorrhagic stroke cohort and identify abnormal labs
AdmLabs72Hr_HS AS (
    SELECT
        hsa.subject_id,
        hsa.hadm_id,
        hsa.admittime,
        hsa.dischtime,
        hsa.hospital_expire_flag,
        hsa.los_days,
        le.itemid,
        le.valuenum,
        le.ref_range_lower,
        le.ref_range_upper,
        (le.valuenum IS NOT NULL AND le.ref_range_lower IS NOT NULL AND le.ref_range_upper IS NOT NULL AND
         (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)) AS is_abnormal
    FROM
        HemorrhagicStrokeAdmissions hsa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON hsa.hadm_id = le.hadm_id
    WHERE
        le.charttime BETWEEN hsa.admittime AND DATETIME_ADD(hsa.admittime, INTERVAL 72 HOUR)
        AND le.valuenum IS NOT NULL -- Only consider labs with numeric values
),
-- 3. Calculate 72-hour lab instability score (count of unique abnormal labs) for HS cohort
InstabilityScore_HS AS (
    SELECT
        hadm_id,
        COUNT(DISTINCT CASE WHEN is_abnormal THEN itemid END) AS lab_instability_score,
        MAX(los_days) AS los_days,
        MAX(hospital_expire_flag) AS hospital_expire_flag
    FROM
        AdmLabs72Hr_HS
    GROUP BY
        hadm_id
),
-- 4. Stratify HS cohort into quartiles based on instability score
ScoredCohortWithQuartile_HS AS (
    SELECT
        hadm_id,
        lab_instability_score,
        los_days,
        hospital_expire_flag,
        NTILE(4) OVER (ORDER BY lab_instability_score) AS instability_quartile
    FROM
        InstabilityScore_HS
),
-- 5. Calculate LOS and mortality for HS cohort per quartile
CohortQuartileSummary_HS AS (
    SELECT
        'Hemorrhagic Stroke Cohort' AS cohort_type,
        CAST(instability_quartile AS STRING) AS group_identifier,
        COUNT(DISTINCT hadm_id) AS num_admissions,
        ROUND(AVG(los_days), 2) AS avg_los_days,
        ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_percent
    FROM
        ScoredCohortWithQuartile_HS
    GROUP BY
        instability_quartile
),
-- 6. Calculate per-lab abnormal rates for HS cohort per quartile
CohortPerLabAbnormalRatesByItem_HS AS (
    SELECT
        sq.instability_quartile,
        dli.label AS lab_name,
        SUM(CAST(alh.is_abnormal AS INT64)) AS abnormal_count,
        COUNT(alh.valuenum) AS total_count,
        SAFE_DIVIDE(SUM(CAST(alh.is_abnormal AS INT64)), COUNT(alh.valuenum)) AS abnormal_rate
    FROM
        AdmLabs72Hr_HS alh
    INNER JOIN
        ScoredCohortWithQuartile_HS sq
        ON alh.hadm_id = sq.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON alh.itemid = dli.itemid
    GROUP BY
        sq.instability_quartile,
        dli.label
),
-- Rank labs for HS cohort for top 5 (arbitrary choice for reporting)
RankedPerLabRates_HS AS (
    SELECT
        'Hemorrhagic Stroke Cohort' AS cohort_type,
        CAST(instability_quartile AS STRING) AS group_identifier,
        lab_name,
        abnormal_count,
        total_count,
        abnormal_rate,
        ROW_NUMBER() OVER (PARTITION BY instability_quartile ORDER BY abnormal_rate DESC, abnormal_count DESC, lab_name) AS rn
    FROM CohortPerLabAbnormalRatesByItem_HS
    WHERE total_count > 0 AND abnormal_count > 0 -- Only show labs with at least one abnormal measurement
),

-- PART 2: Control Group Analysis (Male, 40-50, NO hemorrhagic stroke)

-- 7. Identify male inpatients aged 40-50 WITHOUT hemorrhagic stroke (control group)
ControlAdmissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 40 AND 50
        AND NOT EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE
                diag.hadm_id = adm.hadm_id
                AND (
                    (diag.icd_version = 9 AND diag.icd_code IN ('430', '431', '432')) OR
                    (diag.icd_version = 10 AND (diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%'))
                )
        )
),
-- 8. Get lab events within 72 hours for the control group and identify abnormal labs
AdmLabs72Hr_Control AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        ca.hospital_expire_flag,
        ca.los_days,
        le.itemid,
        le.valuenum,
        le.ref_range_lower,
        le.ref_range_upper,
        (le.valuenum IS NOT NULL AND le.ref_range_lower IS NOT NULL AND le.ref_range_upper IS NOT NULL AND
         (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)) AS is_abnormal
    FROM
        ControlAdmissions ca
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ca.hadm_id = le.hadm_id
    WHERE
        le.charttime BETWEEN ca.admittime AND DATETIME_ADD(ca.admittime, INTERVAL 72 HOUR)
        AND le.valuenum IS NOT NULL -- Only consider labs with numeric values
),

-- 9. Calculate overall LOS and mortality for the Control group
ControlSummary AS (
    SELECT
        'Control Group (Non-HS)' AS cohort_type,
        'Overall' AS group_identifier,
        COUNT(DISTINCT hadm_id) AS num_admissions,
        ROUND(AVG(los_days), 2) AS avg_los_days,
        ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_percent
    FROM
        ControlAdmissions
),

-- 10. Calculate per-lab abnormal rates for the Control group
ControlPerLabAbnormalRatesByItem AS (
    SELECT
        dli.label AS lab_name,
        SUM(CAST(alc.is_abnormal AS INT64)) AS abnormal_count,
        COUNT(alc.valuenum) AS total_count,
        SAFE_DIVIDE(SUM(CAST(alc.is_abnormal AS INT64)), COUNT(alc.valuenum)) AS abnormal_rate
    FROM
        AdmLabs72Hr_Control alc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON alc.itemid = dli.itemid
    GROUP BY
        dli.label
),
-- Rank labs for Control group for top 5 (arbitrary choice for reporting)
RankedPerLabRates_Control AS (
    SELECT
        'Control Group (Non-HS)' AS cohort_type,
        'Overall' AS group_identifier,
        lab_name,
        abnormal_count,
        total_count,
        abnormal_rate,
        ROW_NUMBER() OVER (ORDER BY abnormal_rate DESC, abnormal_count DESC, lab_name) AS rn
    FROM ControlPerLabAbnormalRatesByItem
    WHERE total_count > 0 AND abnormal_count > 0 -- Only show labs with at least one abnormal measurement
)
-- Final Output: Combine summary statistics and top per-lab abnormal rates into a single result set
SELECT
    cohort_type,
    group_identifier,
    'Summary: General' AS report_item_type,
    num_admissions,
    avg_los_days,
    mortality_rate_percent,
    CAST(NULL AS STRING) AS lab_name,
    CAST(NULL AS INT64) AS abnormal_count,
    CAST(NULL AS INT64) AS total_count,
    CAST(NULL AS FLOAT64) AS abnormal_rate_percent
FROM
    CohortQuartileSummary_HS
UNION ALL
SELECT
    cohort_type,
    group_identifier,
    'Summary: General' AS report_item_type,
    num_admissions,
    avg_los_days,
    mortality_rate_percent,
    CAST(NULL AS STRING) AS lab_name,
    CAST(NULL AS INT64) AS abnormal_count,
    CAST(NULL AS INT64) AS total_count,
    CAST(NULL AS FLOAT64) AS abnormal_rate_percent
FROM
    ControlSummary
UNION ALL
SELECT
    cohort_type,
    group_identifier,
    'Per-Lab Rates: Top 5 Abnormal' AS report_item_type,
    CAST(NULL AS INT64) AS num_admissions,
    CAST(NULL AS FLOAT64) AS avg_los_days,
    CAST(NULL AS FLOAT64) AS mortality_rate_percent,
    lab_name,
    abnormal_count,
    total_count,
    ROUND(abnormal_rate*100, 2) AS abnormal_rate_percent -- Report as percentage for clarity
FROM
    RankedPerLabRates_HS
WHERE
    rn <= 5 -- Top 5 labs per quartile
UNION ALL
SELECT
    cohort_type,
    group_identifier,
    'Per-Lab Rates: Top 5 Abnormal' AS report_item_type,
    CAST(NULL AS INT64) AS num_admissions,
    CAST(NULL AS FLOAT64) AS avg_los_days,
    CAST(NULL AS FLOAT64) AS mortality_rate_percent,
    lab_name,
    abnormal_count,
    total_count,
    ROUND(abnormal_rate*100, 2) AS abnormal_rate_percent -- Report as percentage for clarity
FROM
    RankedPerLabRates_Control
WHERE
    rn <= 5 -- Top 5 labs for control group
ORDER BY
    cohort_type DESC,
    group_identifier,
    CASE report_item_type WHEN 'Summary: General' THEN 1 ELSE 2 END, -- Order Summary first
    abnormal_rate_percent DESC -- For labs, order by rate;
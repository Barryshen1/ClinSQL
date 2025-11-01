WITH patients_filtered AS (
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 50 AND 60
),
-- 2. Get all admissions for the filtered patient demographic
all_admissions_with_patient_info AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        p.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        patients_filtered p
        ON ad.subject_id = p.subject_id
),
-- 3. Identify Hyperosmolar Hyperglycemic State (HHS) admissions
-- Common ICD-9 codes for HHS/DM with hyperosmolarity/coma: 250.2x
-- Common ICD-10 codes for HHS/DM with hyperosmolarity/coma: E10.65, E11.65, E13.65 (diabetes with hyperosmolarity with coma)
hhs_admissions AS (
    SELECT DISTINCT
        aar.subject_id,
        aar.hadm_id,
        aar.admittime,
        aar.dischtime,
        aar.hospital_expire_flag,
        aar.anchor_age
    FROM
        all_admissions_with_patient_info aar
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON aar.subject_id = di.subject_id
        AND aar.hadm_id = di.hadm_id
    WHERE
        (di.icd_version = 9 AND di.icd_code LIKE '250.2%')
        OR
        (di.icd_version = 10 AND di.icd_code IN ('E10.65', 'E11.65', 'E13.65'))
),
-- 4. Define critical lab itemids based on a predefined list
critical_lab_itemids AS (
    SELECT itemid FROM UNNEST([
        50809, -- Glucose
        50931, -- Glucose
        50813, -- Sodium
        50983, -- Sodium
        50822, -- Potassium
        50971, -- Potassium
        50806, -- Chloride
        50902, -- Chloride
        50882, -- CO2 (Bicarbonate commonly represented by CO2 in labs)
        50803, -- Bicarbonate (direct)
        50884, -- BUN (Blood Urea Nitrogen)
        51006, -- Urea Nitrogen (BUN)
        50885, -- Creatinine
        50912  -- Creatinine
    ]) AS itemid
),
-- 5. Identify abnormal critical labs within the first 48 hours of admission
abnormal_critical_labs_48hr AS (
    SELECT
        le.subject_id,
        le.hadm_id,
        le.itemid
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN
        critical_lab_itemids cli
        ON le.itemid = cli.itemid
    INNER JOIN
        all_admissions_with_patient_info aar
        ON le.subject_id = aar.subject_id
        AND le.hadm_id = aar.hadm_id
    WHERE
        le.charttime BETWEEN aar.admittime AND TIMESTAMP_ADD(aar.admittime, INTERVAL 48 HOUR)
        AND le.valuenum IS NOT NULL
        AND le.ref_range_lower IS NOT NULL
        AND le.ref_range_upper IS NOT NULL
        AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
),
-- 6. Calculate the first-48-hour laboratory instability score for all relevant admissions
-- This is the count of distinct critical itemids with an abnormal value.
lab_instability_score AS (
    SELECT
        aar.subject_id,
        aar.hadm_id,
        aar.admittime,
        aar.dischtime,
        aar.hospital_expire_flag,
        -- Use COALESCE to ensure a score of 0 for admissions with no abnormal labs
        COALESCE(COUNT(DISTINCT acl.itemid), 0) AS instability_score
    FROM
        all_admissions_with_patient_info aar
    LEFT JOIN
        abnormal_critical_labs_48hr acl
        ON aar.subject_id = acl.subject_id
        AND aar.hadm_id = acl.hadm_id
    GROUP BY
        aar.subject_id,
        aar.hadm_id,
        aar.admittime,
        aar.dischtime,
        aar.hospital_expire_flag
),
-- 7. Isolate instability scores for the HHS cohort
hhs_instability_scores AS (
    SELECT
        lis.subject_id,
        lis.hadm_id,
        lis.admittime,
        lis.dischtime,
        lis.hospital_expire_flag,
        lis.instability_score
    FROM
        hhs_admissions ha
    INNER JOIN
        lab_instability_score lis
        ON ha.subject_id = lis.subject_id
        AND ha.hadm_id = lis.hadm_id
),
-- 8. Calculate the 75th percentile of the instability score for the HHS cohort
percentile_threshold AS (
    SELECT
        PERCENTILE_CONT(0.75) OVER() AS p75_score
    FROM
        hhs_instability_scores
    LIMIT 1 -- Ensures a single scalar value for the percentile
),
-- 9. Calculate metrics for the HHS high-instability cohort
hhs_high_instability_cohort_results AS (
    SELECT
        'HHS High Instability' AS cohort_group,
        COUNT(his.hadm_id) AS num_admissions,
        SUM(his.hospital_expire_flag) * 100.0 / COUNT(his.hadm_id) AS mortality_rate_percent,
        AVG(TIMESTAMP_DIFF(his.dischtime, his.admittime, HOUR) / 24.0) AS mean_los_days,
        AVG(his.instability_score) AS avg_critical_lab_score_48hr
    FROM
        hhs_instability_scores his, percentile_threshold pt
    WHERE
        his.instability_score >= pt.p75_score
),
-- 10. Calculate metrics for the general female 50-60 inpatient cohort (for comparison)
general_cohort_results AS (
    SELECT
        'General Female 50-60' AS cohort_group,
        COUNT(lis.hadm_id) AS num_admissions,
        SUM(lis.hospital_expire_flag) * 100.0 / COUNT(lis.hadm_id) AS mortality_rate_percent,
        AVG(TIMESTAMP_DIFF(lis.dischtime, lis.admittime, HOUR) / 24.0) AS mean_los_days,
        AVG(lis.instability_score) AS avg_critical_lab_score_48hr
    FROM
        lab_instability_score lis -- This CTE already contains all eligible female 50-60 admissions
)
-- 11. Combine and present the results
SELECT * FROM hhs_high_instability_cohort_results
UNION ALL
SELECT * FROM general_cohort_results;
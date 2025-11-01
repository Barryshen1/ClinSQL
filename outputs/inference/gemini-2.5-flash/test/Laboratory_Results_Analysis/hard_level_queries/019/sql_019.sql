with acute pancreatitis (AP cohort) and calculates their 72-hour lab instability score.
It then determines the 90th percentile of this score for the AP cohort.
For AP patients with scores >= P90, and for a 'general inpatient' comparison group, the query reports:
1. Hospital mortality rate.
2. Mean Length of Stay (LOS).
3. For each lab item, the proportion of admissions where that lab had a critical value within the first 72 hours.

A lab is considered 'critical' if its `valuenum` is outside the `ref_range_lower` or `ref_range_upper` from `labevents`.
The 'lab instability score' for an admission is the count of *distinct* `itemid`s that had at least one critical value within the 72-hour window from admission.
*/

WITH ap_diagnoses AS (
    -- Identify admissions with Acute Pancreatitis diagnoses
    SELECT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 10 AND icd_code LIKE 'K85%') -- ICD-10 for Acute Pancreatitis
        OR (icd_version = 9 AND icd_code = '5770')  -- ICD-9 for Acute Pancreatitis (MIMIC-IV ICD-9 codes are without decimals)
    GROUP BY
        hadm_id
),
filtered_admissions AS (
    -- Filter patients based on age and gender (male, 63-73)
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 63 AND 73
),
all_labevents_72h AS (
    -- Get lab events within the first 72 hours of admission for the filtered cohort
    SELECT
        fa.subject_id,
        fa.hadm_id,
        le.itemid,
        le.valuenum,
        le.ref_range_lower,
        le.ref_range_upper,
        dli.label,
        fa.admittime,
        fa.dischtime,
        fa.hospital_expire_flag
    FROM
        filtered_admissions fa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON fa.hadm_id = le.hadm_id AND fa.subject_id = le.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE
        le.charttime BETWEEN fa.admittime AND TIMESTAMP_ADD(fa.admittime, INTERVAL 72 HOUR)
        AND le.valuenum IS NOT NULL -- Only consider labs with a numerical value
),
critical_lab_events AS (
    -- Identify distinct critical lab events per admission
    SELECT DISTINCT
        subject_id,
        hadm_id,
        itemid,
        label,
        admittime,
        dischtime,
        hospital_expire_flag
    FROM
        all_labevents_72h
    WHERE
        valuenum IS NOT NULL
        AND ref_range_lower IS NOT NULL
        AND ref_range_upper IS NOT NULL
        AND (valuenum < ref_range_lower OR valuenum > ref_range_upper)
),
admissions_with_lab_scores AS (
    -- Calculate lab instability score for each admission in the filtered cohort
    SELECT
        fa.subject_id,
        fa.hadm_id,
        fa.admittime,
        fa.dischtime,
        fa.hospital_expire_flag,
        COUNT(DISTINCT cle.itemid) AS lab_instability_score
    FROM
        filtered_admissions fa
    LEFT JOIN -- Use LEFT JOIN to include admissions with no critical labs (score 0)
        critical_lab_events cle
        ON fa.hadm_id = cle.hadm_id AND fa.subject_id = cle.subject_id
    GROUP BY
        fa.subject_id,
        fa.hadm_id,
        fa.admittime,
        fa.dischtime,
        fa.hospital_expire_flag
),
ap_cohort_with_scores AS (
    -- Select the Acute Pancreatitis cohort with their lab instability scores
    SELECT
        aws.subject_id,
        aws.hadm_id,
        aws.admittime,
        aws.dischtime,
        aws.hospital_expire_flag,
        aws.lab_instability_score
    FROM
        admissions_with_lab_scores aws
    INNER JOIN
        ap_diagnoses apd
        ON aws.hadm_id = apd.hadm_id
),
p90_threshold AS (
    -- Calculate the 90th percentile of the lab instability score for the AP cohort
    SELECT
        PERCENTILE_CONT(0.9) OVER() AS p90_score -- PERCENTILE_CONT with OVER() works directly on ordered data
    FROM
        ap_cohort_with_scores
    ORDER BY
        lab_instability_score
    LIMIT 1 -- To get a single scalar value from the window function (only the first row after ordering)
),
high_instability_ap AS (
    -- Identify AP patients with lab instability score >= P90
    SELECT
        apc.*
    FROM
        ap_cohort_with_scores apc
    CROSS JOIN
        p90_threshold p90 -- Cross join to use the scalar p90_score
    WHERE
        apc.lab_instability_score >= p90.p90_score
),
general_inpatients AS (
    -- Define the general inpatients cohort (all male 63-73 admissions)
    SELECT
        aws.*
    FROM
        admissions_with_lab_scores aws
),
-- Critical labs for high instability AP cohort
critical_labs_high_instability_ap AS (
    SELECT DISTINCT
        hia.hadm_id,
        cle.itemid,
        cle.label
    FROM
        high_instability_ap hia
    INNER JOIN
        critical_lab_events cle
        ON hia.hadm_id = cle.hadm_id AND hia.subject_id = cle.subject_id
),
-- Critical labs for general inpatients
critical_labs_general_inp AS (
    SELECT DISTINCT
        gi.hadm_id,
        cle.itemid,
        cle.label
    FROM
        general_inpatients gi
    INNER JOIN
        critical_lab_events cle
        ON gi.hadm_id = cle.hadm_id AND gi.subject_id = cle.subject_id
),
ap_summary AS (
    -- Summary statistics for the high instability AP cohort
    SELECT
        'High-Instability AP' AS cohort_name,
        COUNT(DISTINCT hadm_id) AS total_admissions,
        SUM(hospital_expire_flag) AS total_deaths,
        AVG(hospital_expire_flag) AS mortality_rate,
        AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
        p90.p90_score AS lab_instability_p90_threshold
    FROM
        high_instability_ap
    CROSS JOIN p90_threshold p90
),
ap_lab_rates AS (
    -- Per-lab critical rates for high instability AP cohort
    SELECT
        cle.itemid,
        cle.label,
        SAFE_DIVIDE(COUNT(DISTINCT cle.hadm_id), (SELECT COUNT(DISTINCT hadm_id) FROM high_instability_ap)) AS critical_rate_per_lab
    FROM
        critical_labs_high_instability_ap cle
    GROUP BY
        cle.itemid,
        cle.label
),
general_summary AS (
    -- Summary statistics for the general inpatients cohort
    SELECT
        'General Inpatients' AS cohort_name,
        COUNT(DISTINCT hadm_id) AS total_admissions,
        SUM(hospital_expire_flag) AS total_deaths,
        AVG(hospital_expire_flag) AS mortality_rate,
        AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
        NULL AS lab_instability_p90_threshold -- N/A for general inpatients
    FROM
        general_inpatients
),
general_lab_rates AS (
    -- Per-lab critical rates for general inpatients cohort
    SELECT
        cle.itemid,
        cle.label,
        SAFE_DIVIDE(COUNT(DISTINCT cle.hadm_id), (SELECT COUNT(DISTINCT hadm_id) FROM general_inpatients)) AS critical_rate_per_lab
    FROM
        critical_labs_general_inp cle
    GROUP BY
        cle.itemid,
        cle.label
)
-- Combine results for high instability AP cohort
SELECT
    ap_s.cohort_name,
    ap_s.total_admissions,
    ap_s.total_deaths,
    ap_s.mortality_rate,
    ap_s.mean_los_days,
    ap_s.lab_instability_p90_threshold,
    ap_lr.label AS lab_item_name,
    ap_lr.critical_rate_per_lab
FROM
    ap_summary ap_s
CROSS JOIN
    ap_lab_rates ap_lr

UNION ALL

-- Combine results for general inpatient cohort
SELECT
    gen_s.cohort_name,
    gen_s.total_admissions,
    gen_s.total_deaths,
    gen_s.mortality_rate,
    gen_s.mean_los_days,
    gen_s.lab_instability_p90_threshold,
    gen_lr.label AS lab_item_name,
    gen_lr.critical_rate_per_lab
FROM
    general_summary gen_s
CROSS JOIN
    general_lab_rates gen_lr;
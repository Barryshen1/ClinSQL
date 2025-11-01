WITH cohort_admissions AS (
    -- Identify the target cohort: male inpatients age 70-80 with hemorrhagic stroke
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 70 AND 80
        AND (
            -- ICD-10 codes for hemorrhagic stroke
            (di.icd_version = 10 AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%'))
            OR
            -- ICD-9 codes for hemorrhagic stroke
            (di.icd_version = 9 AND (di.icd_code = '430' OR di.icd_code = '431'))
        )
    GROUP BY -- Ensure distinct admissions for the cohort, even if multiple stroke codes for one hadm_id
        pa.subject_id, ad.hadm_id, ad.admittime, ad.dischtime, ad.hospital_expire_flag
),
all_admissions_critical_lab_counts AS (
    -- Calculate critical lab events in the first 48 hours for all admissions
    -- This will be used for the general inpatient comparison rate
    SELECT
        ad.hadm_id,
        COUNT(DISTINCT le.labevent_id) AS critical_lab_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ad.hadm_id = le.hadm_id
    -- Removed join to d_labitems as it's not needed for reference ranges in this context
    WHERE
        -- Lab event within the first 48 hours of admission
        le.charttime BETWEEN ad.admittime AND DATETIME_ADD(ad.admittime, INTERVAL 48 HOUR)
        AND le.valuenum IS NOT NULL -- Ensure numeric value exists
        AND le.ref_range_lower IS NOT NULL -- Corrected: Use le.ref_range_lower
        AND le.ref_range_upper IS NOT NULL -- Corrected: Use le.ref_range_upper
        -- Value is outside the normal reference range (critical)
        AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
    GROUP BY
        ad.hadm_id
),
cohort_critical_lab_counts AS (
    -- Calculate critical lab events in the first 48 hours specifically for the hemorrhagic stroke cohort
    SELECT
        ca.hadm_id,
        COUNT(DISTINCT le.labevent_id) AS critical_lab_count
    FROM
        cohort_admissions ca
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ca.hadm_id = le.hadm_id
    -- Removed join to d_labitems as it's not needed for reference ranges in this context
    WHERE
        -- Lab event within the first 48 hours of admission
        le.charttime BETWEEN ca.admittime AND DATETIME_ADD(ca.admittime, INTERVAL 48 HOUR)
        AND le.valuenum IS NOT NULL -- Ensure numeric value exists
        AND le.ref_range_lower IS NOT NULL -- Corrected: Use le.ref_range_lower
        AND le.ref_range_upper IS NOT NULL -- Corrected: Use le.ref_range_upper
        -- Value is outside the normal reference range (critical)
        AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
    GROUP BY
        ca.hadm_id
),
cohort_critical_lab_scores AS (
    -- Join cohort admissions with their critical lab counts, providing 0 for admissions with no critical labs
    SELECT
        ca.hadm_id,
        IFNULL(ccc.critical_lab_count, 0) AS critical_lab_score_48hr
    FROM
        cohort_admissions ca
    LEFT JOIN
        cohort_critical_lab_counts ccc
        ON ca.hadm_id = ccc.hadm_id
),
general_critical_lab_rate AS (
    -- Calculate the general inpatient critical-lab event rate once
    SELECT
        SUM(IFNULL(alc.critical_lab_count, 0)) / COUNT(ad.hadm_id) AS total_average_critical_labs_per_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    LEFT JOIN
        all_admissions_critical_lab_counts alc
        ON ad.hadm_id = alc.hadm_id
)
SELECT
    'Hemorrhagic Stroke Cohort (Male, 70-80)' AS cohort_description,
    COUNT(DISTINCT ca.hadm_id) AS num_admissions_in_cohort,
    -- 25th percentile of the first-48-hour laboratory instability score for the cohort
    APPROX_QUANTILES(ccs.critical_lab_score_48hr, 100)[OFFSET(25)] AS p25_first_48hr_critical_lab_score,
    -- Mean first-48-hour laboratory instability score for the cohort (for comparison)
    AVG(ccs.critical_lab_score_48hr) AS mean_first_48hr_critical_lab_score_cohort,
    -- Mean Length of Stay for the cohort
    AVG(DATETIME_DIFF(ca.dischtime, ca.admittime, HOUR) / 24.0) AS mean_los_days_cohort,
    -- In-hospital mortality for the cohort
    AVG(CASE WHEN ca.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) * 100 AS in_hospital_mortality_percent_cohort, -- Use AVG with CASE for percentage
    -- General inpatient critical-lab event rate (count of critical labs per admission)
    (SELECT total_average_critical_labs_per_admission FROM general_critical_lab_rate) AS general_inpatient_critical_lab_event_rate_per_admission
FROM
    cohort_admissions ca
LEFT JOIN
    cohort_critical_lab_scores ccs
    ON ca.hadm_id = ccs.hadm_id;
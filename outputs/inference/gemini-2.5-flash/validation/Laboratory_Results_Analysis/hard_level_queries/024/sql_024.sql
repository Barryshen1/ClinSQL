WITH critical_lab_itemids AS (
    SELECT itemid FROM UNNEST([
        50931, -- Glucose
        50971, -- Potassium
        50983, -- Sodium
        50912, -- Creatinine
        50811, -- Hemoglobin
        51301, -- WBC
        51265, -- Platelet Count
        50820  -- pH (often from blood gas, but also found in labevents)
    ]) AS itemid
),

-- Step 1: Define the target cohort (Female, 53-63 years old, with post-cardiac arrest diagnosis)
cardiac_arrest_cohort AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON ad.hadm_id = di.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 53 AND 63
        AND (
            (di.icd_version = 10 AND (di.icd_code LIKE 'I46%' OR di.icd_code = 'R092')) -- ICD-10 for Cardiac Arrest (I46.x or R09.2)
            OR (di.icd_version = 9 AND di.icd_code = '4275') -- ICD-9 for Cardiac Arrest (427.5)
        )
    GROUP BY -- Group by hadm_id to get unique admissions for the cohort, as a patient can have multiple diagnoses
        ad.subject_id, ad.hadm_id, ad.admittime, ad.dischtime, ad.hospital_expire_flag
),

-- Step 2: Extract relevant lab events for critical labs within the first 48 hours for the cohort
cohort_lab_data_48hr AS (
    SELECT
        cac.hadm_id,
        le.itemid,
        le.valuenum
    FROM
        cardiac_arrest_cohort AS cac
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON cac.subject_id = le.subject_id AND cac.hadm_id = le.hadm_id
    INNER JOIN
        critical_lab_itemids AS cli
        ON le.itemid = cli.itemid
    WHERE
        le.charttime BETWEEN cac.admittime AND DATETIME_ADD(cac.admittime, INTERVAL 48 HOUR)
        AND le.valuenum IS NOT NULL
),

-- Step 3: Calculate instability score for each hadm_id based on a sum of (MAX - MIN) for each itemid
instability_scores AS (
    SELECT
        hadm_id,
        SUM(max_val - min_val) AS instability_score
    FROM (
        SELECT
            hadm_id,
            itemid,
            MAX(valuenum) AS max_val,
            MIN(valuenum) AS min_val
        FROM
            cohort_lab_data_48hr
        GROUP BY
            hadm_id, itemid
    ) AS item_instability
    GROUP BY
        hadm_id
),

-- Step 4: Combine cohort information with instability scores, handling admissions with no relevant labs
cohort_with_instability AS (
    SELECT
        cac.subject_id,
        cac.hadm_id,
        cac.admittime,
        cac.dischtime,
        cac.hospital_expire_flag,
        cac.los_days,
        COALESCE(ins.instability_score, 0) AS instability_score -- Assign 0 if no relevant labs in 48h
    FROM
        cardiac_arrest_cohort AS cac
    LEFT JOIN
        instability_scores AS ins
        ON cac.hadm_id = ins.hadm_id
),

-- Step 5: Calculate the 90th percentile of the instability score for the cohort
percentile_90_threshold AS (
    SELECT
        PERCENTILE_CONT(instability_score, 0.9) OVER() AS threshold
    FROM
        cohort_with_instability
    LIMIT 1 -- Ensures a single scalar value for the threshold
),

-- Step 6: Identify the high instability group (scores >= 90th percentile threshold)
high_instability_cohort AS (
    SELECT
        cai.*
    FROM
        cohort_with_instability AS cai,
        percentile_90_threshold AS p90
    WHERE
        cai.instability_score >= p90.threshold
),

-- Step 7: Calculate critical lab frequency metrics for the high instability group (across entire stay)
high_instability_lab_freq AS (
    SELECT
        hic.hadm_id,
        COUNT(DISTINCT le.itemid) AS distinct_critical_labs_measured,
        COUNT(CASE WHEN le.flag = 'abnormal' THEN 1 END) AS abnormal_critical_lab_results
    FROM
        high_instability_cohort AS hic
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON hic.subject_id = le.subject_id AND hic.hadm_id = le.hadm_id
    INNER JOIN
        critical_lab_itemids AS cli
        ON le.itemid = cli.itemid
    WHERE
        le.valuenum IS NOT NULL -- Only count lab events with valid numeric values
    GROUP BY
        hic.hadm_id
),

-- Step 8: Define the "all inpatients" group for comparison
-- Exclude specific admission types that are often not considered true inpatient admissions
all_inpatients AS (
    SELECT
        ad.subject_id,
        ad.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    WHERE
        ad.admission_type NOT IN ('EW EMER', 'OBSERVATION', 'PATIENT ED') -- Filter out types not typically full inpatient
        AND ad.hadm_id IS NOT NULL -- Ensure valid admission ID
        AND ad.admittime IS NOT NULL AND ad.dischtime IS NOT NULL -- Ensure valid stay times for analysis
),

-- Step 9: Calculate critical lab frequency metrics for all inpatients (across entire stay)
all_inpatients_lab_freq AS (
    SELECT
        ai.hadm_id,
        COUNT(DISTINCT le.itemid) AS distinct_critical_labs_measured,
        COUNT(CASE WHEN le.flag = 'abnormal' THEN 1 END) AS abnormal_critical_lab_results
    FROM
        all_inpatients AS ai
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON ai.subject_id = le.subject_id AND ai.hadm_id = le.hadm_id
    INNER JOIN
        critical_lab_itemids AS cli
        ON le.itemid = cli.itemid
    WHERE
        le.valuenum IS NOT NULL
    GROUP BY
        ai.hadm_id
)

-- Final result selection: Reporting requested metrics
SELECT
    (SELECT threshold FROM percentile_90_threshold) AS instability_score_90th_percentile_threshold,
    
    -- Metrics for the high instability cohort
    (SELECT COUNT(DISTINCT hadm_id) FROM high_instability_cohort) AS high_instability_patient_count,
    (SELECT AVG(hospital_expire_flag) FROM high_instability_cohort) AS high_instability_mortality_rate,
    (SELECT AVG(los_days) FROM high_instability_cohort) AS high_instability_mean_los_days,
    (SELECT AVG(COALESCE(distinct_critical_labs_measured, 0)) FROM high_instability_lab_freq) AS high_instability_avg_distinct_critical_labs_per_admission,
    (SELECT AVG(COALESCE(abnormal_critical_lab_results, 0)) FROM high_instability_lab_freq) AS high_instability_avg_abnormal_critical_labs_per_admission,
    
    -- Metrics for all inpatients (comparison group)
    (SELECT AVG(COALESCE(distinct_critical_labs_measured, 0)) FROM all_inpatients_lab_freq) AS all_inpatients_avg_distinct_critical_labs_per_admission,
    (SELECT AVG(COALESCE(abnormal_critical_lab_results, 0)) FROM all_inpatients_lab_freq) AS all_inpatients_avg_abnormal_critical_labs_per_admission;
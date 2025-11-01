WITH cohort_admissions AS (
    -- Step 1: Define the Cohort - Women aged 65-75 with Lower GI Bleeding
    SELECT DISTINCT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ad.subject_id = pa.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 65 AND 75
        AND (
            (di.icd_version = 9 AND (
                -- ICD-9 codes for lower GI bleeding
                STARTS_WITH(di.icd_code, '578') -- Blood in stool, GI hemorrhage unspecified
                OR STARTS_WITH(di.icd_code, '562.1') -- Diverticulosis/Diverticulitis of colon with hemorrhage
            ))
            OR
            (di.icd_version = 10 AND (
                -- ICD-10 codes for lower GI bleeding
                di.icd_code LIKE 'K921%' -- Melena
                OR di.icd_code LIKE 'K922%' -- Gastrointestinal hemorrhage, unspecified
                OR STARTS_WITH(di.icd_code, 'K57.') -- Diverticular disease of intestine with hemorrhage
                OR di.icd_code LIKE 'I864%' -- Anal and rectal varices, bleeding
                OR di.icd_code LIKE 'K625%' -- Hemorrhage of anus and rectum
                OR di.icd_code LIKE 'K627%' -- Hemorrhagic proctitis
            ))
        )
),
cohort_lab_abnormalities AS (
    -- Identify abnormal lab events for the cohort within the first 72 hours
    SELECT
        ca.hadm_id,
        le.labevent_id -- Count distinct labevents which are abnormal
    FROM
        cohort_admissions ca
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ca.subject_id = le.subject_id AND ca.hadm_id = le.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE
        le.charttime BETWEEN ca.admittime AND DATETIME_ADD(ca.admittime, INTERVAL 72 HOUR)
        AND le.valuenum IS NOT NULL -- Only consider numeric values for abnormality check
        AND (
            le.flag = 'abnormal' -- Flagged as abnormal by the lab system
            OR (
                le.ref_range_lower IS NOT NULL AND le.ref_range_upper IS NOT NULL
                AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
            ) -- Value outside reference range
        )
),
cohort_liss AS (
    -- Calculate Lab Instability Score (LISS) for each cohort admission
    SELECT
        hadm_id,
        COUNT(labevent_id) AS liss_score
    FROM
        cohort_lab_abnormalities
    GROUP BY
        hadm_id
),
general_lab_abnormalities AS (
    -- Identify abnormal lab events for ALL admissions within the first 72 hours as a baseline
    SELECT
        ad.hadm_id,
        le.labevent_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ad.subject_id = le.subject_id AND ad.hadm_id = le.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE
        le.charttime BETWEEN ad.admittime AND DATETIME_ADD(ad.admittime, INTERVAL 72 HOUR)
        AND le.valuenum IS NOT NULL
        AND (
            le.flag = 'abnormal'
            OR (
                le.ref_range_lower IS NOT NULL AND le.ref_range_upper IS NOT NULL
                AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
            )
        )
),
general_liss AS (
    -- Calculate LISS for each general admission
    SELECT
        hadm_id,
        COUNT(labevent_id) AS liss_score
    FROM
        general_lab_abnormalities
    GROUP BY
        hadm_id
),
cohort_summary AS (
    -- Aggregate all cohort-specific metrics into a single row
    SELECT
        COUNT(DISTINCT ca.hadm_id) AS cohort_size,
        -- Collect all LISS scores into an array for percentile calculation
        ARRAY_AGG(COALESCE(cl.liss_score, 0)) AS all_cohort_liss_scores,
        AVG(COALESCE(cl.liss_score, 0)) AS cohort_avg_critical_lab_events_per_admission,
        AVG(DATETIME_DIFF(ca.dischtime, ca.admittime, HOUR) / 24.0) AS cohort_avg_los_days, -- Changed to days for better readability
        (SUM(CASE WHEN ca.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(ca.hadm_id)) AS cohort_mortality_rate_percent
    FROM
        cohort_admissions ca
    LEFT JOIN
        cohort_liss cl
        ON ca.hadm_id = cl.hadm_id
),
general_summary AS (
    -- Aggregate general inpatient average LISS into a single row
    SELECT
        AVG(COALESCE(gl.liss_score, 0)) AS general_avg_critical_lab_events_per_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad -- All admissions as basis for 'general'
    LEFT JOIN
        general_liss gl
        ON ad.hadm_id = gl.hadm_id
)
-- Final Select to present all required metrics
SELECT
    'Cohort: Women 65-75, Lower GI Bleed within first 72h' AS cohort_description,
    cs.cohort_size,
    -- Calculate the 25th percentile LISS using UNNEST and PERCENTILE_CONT
    PERCENTILE_CONT(liss_score_unnested, 0.25) OVER () AS cohort_25th_percentile_liss_score_within_72h,
    cs.cohort_avg_critical_lab_events_per_admission AS cohort_avg_abnormal_labs_within_72h,
    gs.general_avg_critical_lab_events_per_admission AS general_avg_abnormal_labs_within_72h,
    cs.cohort_avg_los_days,
    cs.cohort_mortality_rate_percent
FROM
    cohort_summary cs,
    general_summary gs
CROSS JOIN
    UNNEST(cs.all_cohort_liss_scores) AS liss_score_unnested;
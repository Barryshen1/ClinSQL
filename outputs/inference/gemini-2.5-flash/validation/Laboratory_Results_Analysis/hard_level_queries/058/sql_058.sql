WITH acs_admissions AS (
    -- Step 1: Identify all admissions for the ACS cohort based on age, gender, and diagnosis
    SELECT
        DISTINCT adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 40 AND 50
        AND diag.icd_version = 10
        AND (
               diag.icd_code LIKE 'I20.0%' -- Unstable angina pectoris
            OR diag.icd_code LIKE 'I21%'   -- Acute myocardial infarction
            OR diag.icd_code LIKE 'I22%'   -- Subsequent myocardial infarction
            OR diag.icd_code LIKE 'I24%'   -- Other acute ischemic heart disease
        )
),
admissions_with_48h_abnormal_flags AS (
    -- Step 2: Get all admissions and flag abnormal lab values within the first 48 hours for any admission.
    -- This CTE includes all admissions from the 'admissions' table.
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        le.itemid,
        -- Flag if lab value is abnormal within the first 48 hours of admission
        CASE
            WHEN
                le.valuenum IS NOT NULL
                AND le.ref_range_lower IS NOT NULL -- Corrected: Use le.ref_range_lower
                AND le.ref_range_upper IS NOT NULL -- Corrected: Use le.ref_range_upper
                AND le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 48 HOUR)
                AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
            THEN 1
            ELSE 0
        END AS is_abnormal_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON adm.subject_id = le.subject_id AND adm.hadm_id = le.hadm_id
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` dl -- d_labitems is still needed if one wanted to filter by category/fluid etc. and does not hurt here.
        ON le.itemid = dl.itemid
),
admission_lab_scores AS (
    -- Step 3: Calculate the instability score (distinct abnormal items) and total abnormal lab count for each admission.
    -- This CTE includes all admissions, with scores as 0 if no abnormal labs in 48h.
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        COUNT(DISTINCT IF(is_abnormal_flag = 1, itemid, NULL)) AS instability_score_distinct_abnormal_items,
        SUM(is_abnormal_flag) AS total_abnormal_lab_count_48h
    FROM
        admissions_with_48h_abnormal_flags
    GROUP BY
        subject_id, hadm_id, admittime, dischtime, hospital_expire_flag
),
acs_cohort_scores AS (
    -- Step 4: Filter `admission_lab_scores` to only include the ACS cohort identified in `acs_admissions`
    SELECT
        als.subject_id,
        als.hadm_id,
        als.admittime,
        als.dischtime,
        als.hospital_expire_flag,
        als.instability_score_distinct_abnormal_items,
        als.total_abnormal_lab_count_48h
    FROM
        admission_lab_scores als
    INNER JOIN
        acs_admissions acs
        ON als.hadm_id = acs.hadm_id AND als.subject_id = acs.subject_id
),
percentile_threshold_value AS (
    -- Step 5: Calculate the 90th percentile instability score for the ACS cohort as a scalar value
    SELECT
        PERCENTILE_CONT(instability_score_distinct_abnormal_items, 0.9) OVER () AS threshold_value -- Added OVER() for window function, though it may work without it if percentile applies to whole set by default
    FROM
        acs_cohort_scores
    LIMIT 1 -- Ensure only one row is returned for the scalar subquery
),
high_instability_acs_patients AS (
    -- Step 6: Identify ACS patients whose instability score is at or above the 90th percentile threshold
    SELECT
        acs_s.subject_id,
        acs_s.hadm_id,
        acs_s.admittime,
        acs_s.dischtime,
        acs_s.hospital_expire_flag,
        acs_s.instability_score_distinct_abnormal_items,
        acs_s.total_abnormal_lab_count_48h
    FROM
        acs_cohort_scores acs_s
    CROSS JOIN
        percentile_threshold_value ptv -- Cross join to access the scalar threshold
    WHERE
        acs_s.instability_score_distinct_abnormal_items >= ptv.threshold_value
)
-- Final Step: Report outcomes for both groups
SELECT
    'High Instability ACS Cohort' AS cohort_type,
    (SELECT threshold_value FROM percentile_threshold_value) AS percentile_threshold_value, -- Report the threshold itself
    CAST(SUM(h.hospital_expire_flag) AS FLOAT64) / COUNT(h.hadm_id) AS mortality_rate,
    AVG(DATETIME_DIFF(h.dischtime, h.admittime, DAY)) AS mean_los_days,
    AVG(h.total_abnormal_lab_count_48h) AS critical_lab_rate
FROM
    high_instability_acs_patients h

UNION ALL

SELECT
    'General Inpatients (Excluding ACS)' AS cohort_type, -- Refined cohort label
    NULL AS percentile_threshold_value, -- Not applicable for general inpatients
    CAST(SUM(g.hospital_expire_flag) AS FLOAT64) / COUNT(g.hadm_id) AS mortality_rate,
    AVG(DATETIME_DIFF(g.dischtime, g.admittime, DAY)) AS mean_los_days,
    AVG(g.total_abnormal_lab_count_48h) AS critical_lab_rate
FROM
    admission_lab_scores g
WHERE
    (g.subject_id, g.hadm_id) NOT IN (SELECT subject_id, hadm_id FROM acs_cohort_scores); -- Refined: Exclude ACS patients for comparison;
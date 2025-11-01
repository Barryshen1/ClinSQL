WITH cohort_admissions AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON pat.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
        ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
    WHERE
        pat.gender = 'M'
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 68 AND 78
        AND (
            LOWER(ddx.long_title) LIKE '%lower gastrointestinal bleeding%'
            OR LOWER(ddx.long_title) LIKE '%melena%'
            OR LOWER(ddx.long_title) LIKE '%hematochezia%'
        )
),

-- T2: Calculate the 72-hour lab instability score for each patient in the cohort.
-- The score is the count of distinct abnormal lab tests in the first 72 hours.
cohort_scores AS (
    SELECT
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        ca.hospital_expire_flag,
        COUNT(DISTINCT le.itemid) AS lab_instability_score
    FROM
        cohort_admissions AS ca
    LEFT JOIN -- Use LEFT JOIN to include patients with 0 abnormal labs.
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON ca.hadm_id = le.hadm_id
        AND le.charttime BETWEEN ca.admittime AND DATETIME_ADD(ca.admittime, INTERVAL 72 HOUR)
        AND le.flag = 'abnormal'
    GROUP BY
        ca.hadm_id, ca.admittime, ca.dischtime, ca.hospital_expire_flag
),

-- T3: Find the 90th percentile threshold for the instability score.
score_threshold AS (
    SELECT
        APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(90)] AS score_90th_percentile
    FROM
        cohort_scores
),

-- T4: Identify the "top-tier" patients (those at or above the 90th percentile).
top_tier_patients AS (
    SELECT
        cs.hadm_id,
        cs.hospital_expire_flag,
        DATETIME_DIFF(cs.dischtime, cs.admittime, DAY) AS los_days
    FROM
        cohort_scores AS cs,
        score_threshold AS st
    WHERE
        cs.lab_instability_score >= st.score_90th_percentile
),

-- T5: Calculate summary statistics (mortality, avg LOS) for the top-tier group.
top_tier_summary AS (
    SELECT
        (SELECT score_90th_percentile FROM score_threshold) AS percentile_90_lab_instability_score,
        AVG(CAST(ttp.hospital_expire_flag AS FLOAT64)) AS top_tier_mortality_rate,
        AVG(ttp.los_days) AS top_tier_avg_los_days,
        COUNT(ttp.hadm_id) AS top_tier_patient_count
    FROM
        top_tier_patients AS ttp
),

-- T6: Find all patients with at least one abnormal lab in the first 72h for the specified tests.
-- Tag whether the patient belongs to the top-tier group.
critical_lab_events AS (
    SELECT
        adm.hadm_id,
        le.itemid,
        MAX(CASE WHEN ttp.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS is_top_tier
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le ON adm.hadm_id = le.hadm_id
    LEFT JOIN
        top_tier_patients AS ttp ON adm.hadm_id = ttp.hadm_id
    WHERE
        le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR)
        AND le.flag = 'abnormal'
        AND le.itemid IN (
            50912, -- Creatinine
            50971, -- Potassium (Serum)
            51265, -- Platelet Count
            51222, -- Hemoglobin
            50822, -- Potassium, Whole Blood
            51301  -- White Blood Cells
        )
    GROUP BY
        adm.hadm_id, le.itemid
),

-- T7: Aggregate abnormal lab counts by lab test and calculate rates for top-tier vs. all inpatients.
critical_lab_comparison AS (
    SELECT
        dli.label,
        SAFE_DIVIDE(
            COUNT(DISTINCT CASE WHEN cle.is_top_tier = 1 THEN cle.hadm_id END),
            (SELECT top_tier_patient_count FROM top_tier_summary)
        ) AS critical_rate_top_tier,
        SAFE_DIVIDE(
            COUNT(DISTINCT cle.hadm_id),
            (SELECT COUNT(DISTINCT hadm_id) FROM `physionet-data.mimiciv_3_1_hosp.admissions`)
        ) AS critical_rate_all_inpatients
    FROM
        critical_lab_events AS cle
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli ON cle.itemid = dli.itemid
    GROUP BY
        dli.label
)

-- Final Output: Combine the summary metrics with the lab-by-lab comparison.
SELECT
    s.percentile_90_lab_instability_score,
    s.top_tier_mortality_rate,
    s.top_tier_avg_los_days,
    c.label AS lab_test,
    c.critical_rate_top_tier,
    c.critical_rate_all_inpatients
FROM
    top_tier_summary AS s,
    critical_lab_comparison AS c
ORDER BY
    c.label;
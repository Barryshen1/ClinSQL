WITH
-- Step 1: Find all ICD codes related to Hyperosmolar Hyperglycemic State (HHS)
hhs_diagnoses AS (
    SELECT DISTINCT icd_code, icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE LOWER(long_title) LIKE '%hyperosmolar%' OR LOWER(long_title) LIKE '%hyperosmolarity%'
),

-- Step 2: Identify unique hospital admissions with an HHS diagnosis
hhs_hadm_ids AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    JOIN hhs_diagnoses hhs_dx
        ON dx.icd_code = hhs_dx.icd_code AND dx.icd_version = hhs_dx.icd_version
),

-- Step 3: Define the primary cohort: Female patients, aged 50-60, with HHS
hhs_cohort AS (
    SELECT
        adm.hadm_id,
        adm.admittime,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    JOIN hhs_hadm_ids
        ON adm.hadm_id = hhs_hadm_ids.hadm_id
    WHERE
        p.gender = 'F'
        AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) + p.anchor_age BETWEEN 50 AND 60
        AND adm.dischtime > adm.admittime
),

-- Step 4: Calculate the first-48-hour laboratory instability score for each admission
-- Score is defined as the count of abnormal lab results in the first 48 hours
lab_scores AS (
    SELECT
        hhs.hadm_id,
        hhs.hospital_expire_flag,
        hhs.los_days,
        COUNT(le.labevent_id) AS instability_score
    FROM hhs_cohort hhs
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON hhs.hadm_id = le.hadm_id
        AND le.charttime BETWEEN hhs.admittime AND DATETIME_ADD(hhs.admittime, INTERVAL 48 HOUR)
        AND le.flag = 'abnormal'
    GROUP BY hhs.hadm_id, hhs.hospital_expire_flag, hhs.los_days
),

-- Step 5: Determine the 75th percentile of the instability score to establish the threshold
score_threshold AS (
    SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75_score
    FROM lab_scores
),

-- Step 6: Isolate the high-score cohort (admissions with score >= 75th percentile)
high_score_cohort AS (
    SELECT
        ls.hadm_id,
        ls.hospital_expire_flag,
        ls.los_days
    FROM lab_scores ls, score_threshold st
    WHERE ls.instability_score >= st.p75_score
),

-- Step 7: Calculate total abnormal labs for the entire stay for the high-score cohort
high_score_total_abnormal_labs AS (
    SELECT
        hsc.hadm_id,
        COUNT(le.labevent_id) AS total_abnormal_labs_stay
    FROM high_score_cohort hsc
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON hsc.hadm_id = le.hadm_id
    WHERE le.flag = 'abnormal'
    GROUP BY hsc.hadm_id
),

-- Step 8: Calculate final metrics for the high-score cohort
high_score_metrics AS (
    SELECT
        AVG(hsc.hospital_expire_flag) AS mortality_rate,
        AVG(hsc.los_days) AS mean_los,
        SUM(COALESCE(tal.total_abnormal_labs_stay, 0)) / SUM(hsc.los_days) AS critical_lab_rate
    FROM high_score_cohort hsc
    LEFT JOIN high_score_total_abnormal_labs tal
        ON hsc.hadm_id = tal.hadm_id
    WHERE hsc.los_days > 0
),

-- Step 9: Calculate the critical lab rate for the general inpatient population for comparison
general_pop_metrics AS (
    SELECT
        (SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_hosp.labevents` WHERE flag = 'abnormal')
        /
        (SELECT SUM(DATETIME_DIFF(dischtime, admittime, DAY))
         FROM `physionet-data.mimiciv_3_1_hosp.admissions`
         WHERE dischtime > admittime AND DATETIME_DIFF(dischtime, admittime, DAY) > 0)
        AS critical_lab_rate_general
)

-- Final Step: Combine and present all results
SELECT
    st.p75_score AS percentile_75_instability_score,
    hsm.mortality_rate AS mortality_rate_high_score_cohort,
    hsm.mean_los AS mean_los_days_high_score_cohort,
    hsm.critical_lab_rate AS critical_lab_rate_per_day_high_score_cohort,
    gpm.critical_lab_rate_general AS critical_lab_rate_per_day_general_inpatients
FROM
    score_threshold st,
    high_score_metrics hsm,
    general_pop_metrics gpm;
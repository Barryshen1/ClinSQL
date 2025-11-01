WITH
-- CTE 1: Find all hospital admissions for patients aged 90-100, including their gender.
-- This serves as the base for both the study and comparison cohorts.
base_admissions_90_100 AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        pat.gender,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        -- Calculate age at the time of admission
        (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 90 AND 100
),

-- CTE 2: From the base, identify the specific cohort of female AMI admissions.
ami_female_admissions AS (
    SELECT DISTINCT
        ba.hadm_id,
        ba.admittime,
        ba.dischtime,
        ba.hospital_expire_flag
    FROM base_admissions_90_100 AS ba
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON ba.hadm_id = dx.hadm_id
    WHERE
        ba.gender = 'F'
        AND (
            (dx.icd_version = 9 AND dx.icd_code LIKE '410%')
            OR (dx.icd_version = 10 AND (dx.icd_code LIKE 'I21%' OR dx.icd_code LIKE 'I22%'))
        )
),

-- CTE 3: Calculate the lab-instability score (count of abnormal labs in first 48h) for the AMI cohort.
lab_instability_scores AS (
    SELECT
        ami.hadm_id,
        COALESCE(COUNT(le.labevent_id), 0) AS lab_instability_score
    FROM ami_female_admissions AS ami
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON ami.hadm_id = le.hadm_id
        AND le.charttime BETWEEN ami.admittime AND TIMESTAMP_ADD(ami.admittime, INTERVAL 48 HOUR)
        AND le.flag = 'abnormal'
    GROUP BY
        ami.hadm_id
),

-- CTE 4: Calculate the 75th percentile of the instability scores.
p75_threshold AS (
    SELECT
        APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(75)] AS p75_score
    FROM lab_instability_scores
),

-- CTE 5: Identify the hadm_ids for the high-instability group (score >= P75).
high_instability_group_hadms AS (
    SELECT
        lis.hadm_id
    FROM lab_instability_scores AS lis, p75_threshold
    WHERE lis.lab_instability_score >= p75_threshold.p75_score
),

-- CTE 6: Summarize total and abnormal labs for the full stay for all relevant admissions.
-- This is used to calculate the final "critical lab rate" metric.
labs_summary AS (
    SELECT
        hadm_id,
        COUNT(labevent_id) AS total_labs,
        COUNTIF(flag = 'abnormal') AS abnormal_labs
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE hadm_id IN (SELECT hadm_id FROM base_admissions_90_100)
    GROUP BY hadm_id
)

-- Final Step: Calculate and union the metrics for the two groups of interest.
-- Group 1: High-instability female AMI patients (score >= P75)
SELECT
    'Female AMI 90-100 with Lab Score >= P75' AS patient_group,
    AVG(adm.hospital_expire_flag) AS in_hospital_mortality_rate,
    AVG(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS mean_los_days,
    SAFE_DIVIDE(SUM(ls.abnormal_labs), SUM(ls.total_labs)) AS critical_lab_rate
FROM ami_female_admissions AS adm
INNER JOIN high_instability_group_hadms AS high_risk
    ON adm.hadm_id = high_risk.hadm_id
LEFT JOIN labs_summary AS ls
    ON adm.hadm_id = ls.hadm_id

UNION ALL

-- Group 2: The comparison group of all inpatients aged 90-100
SELECT
    'All Inpatients 90-100' AS patient_group,
    AVG(adm.hospital_expire_flag) AS in_hospital_mortality_rate,
    AVG(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS mean_los_days,
    SAFE_DIVIDE(SUM(ls.abnormal_labs), SUM(ls.total_labs)) AS critical_lab_rate
FROM base_admissions_90_100 AS adm
LEFT JOIN labs_summary AS ls
    ON adm.hadm_id = ls.hadm_id;
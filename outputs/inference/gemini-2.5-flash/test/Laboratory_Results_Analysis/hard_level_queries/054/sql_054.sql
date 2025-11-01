WITH ami_admissions AS (
    -- CTE 1: Identify AMI Admissions
    -- Filters for female patients aged 38-48 with a diagnosis of Acute Myocardial Infarction (AMI).
    -- Age at admission is calculated by adjusting `anchor_age` based on the difference between `admittime` year and `anchor_year`.
    SELECT DISTINCT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 38 AND 48
        AND (
            -- ICD-9 codes for AMI (410.x)
            (di.icd_version = 9 AND di.icd_code LIKE '410%')
            -- ICD-10 codes for AMI (I21.x, I22.x)
            OR (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
        )
),
ami_lab_scores AS (
    -- CTE 2: Calculate 72-hour Lab Instability Score for AMI Admissions
    -- Counts the number of 'abnormal' lab events (`flag = 'abnormal'`) within the first 72 hours of admission.
    -- LOS is calculated in days.
    SELECT
        ami.subject_id,
        ami.hadm_id,
        ami.admittime,
        ami.dischtime,
        ami.hospital_expire_flag,
        COUNT(le.labevent_id) AS instability_score_72hr,
        DATETIME_DIFF(ami.dischtime, ami.admittime, HOUR) / 24.0 AS los_days
    FROM
        ami_admissions ami
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ami.subject_id = le.subject_id
        AND ami.hadm_id = le.hadm_id
        AND le.charttime >= ami.admittime
        AND le.charttime < DATETIME_ADD(ami.admittime, INTERVAL 72 HOUR)
        AND le.flag = 'abnormal' -- Moved this condition to ON clause to preserve admissions with 0 abnormal labs
    GROUP BY
        ami.subject_id, ami.hadm_id, ami.admittime, ami.dischtime, ami.hospital_expire_flag
),
ami_quartiles AS (
    -- CTE 3: Assign Quartiles to AMI Admissions based on Lab Instability Score
    -- Uses NTILE(4) to divide the AMI cohort into four quartiles based on their 72-hour instability score.
    SELECT
        subject_id,
        hadm_id,
        instability_score_72hr,
        los_days,
        hospital_expire_flag,
        NTILE(4) OVER (ORDER BY instability_score_72hr ASC) AS score_quartile
    FROM
        ami_lab_scores
),
ami_quartile_summary AS (
    -- CTE 4: Summarize Outcomes by Quartile for AMI Admissions
    -- Aggregates relevant metrics (admission count, average score, average LOS, mortality rate) for each quartile.
    SELECT
        score_quartile,
        COUNT(DISTINCT hadm_id) AS num_admissions,
        AVG(instability_score_72hr) AS avg_instability_score_72hr,
        AVG(los_days) AS avg_los_days,
        SUM(hospital_expire_flag) AS total_deaths,
        -- Corrected: Use FLOAT64 for explicit float casting
        (CAST(SUM(hospital_expire_flag) AS FLOAT64) / COUNT(DISTINCT hadm_id)) * 100 AS mortality_rate_percent
    FROM
        ami_quartiles
    GROUP BY
        score_quartile
    ORDER BY
        score_quartile
),
control_admissions AS (
    -- CTE 5: Identify the Control Cohort (Age-matched females without AMI)
    -- Filters for female patients aged 38-48, similar to the AMI cohort, but explicitly excludes any admission with an AMI diagnosis.
    SELECT DISTINCT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        p.gender,
        (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 38 AND 48
        AND NOT EXISTS ( -- Exclude admissions with any AMI diagnosis
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE a.hadm_id = di.hadm_id
            AND (
                (di.icd_version = 9 AND di.icd_code LIKE '410%')
                OR (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
            )
        )
),
control_lab_scores AS (
    -- CTE 6: Calculate 72-hour Lab Instability Score for Control Admissions
    -- Calculates the count of 'abnormal' lab events within the first 72 hours for the control group.
    SELECT
        ctrl.subject_id,
        ctrl.hadm_id,
        COUNT(le.labevent_id) AS instability_score_72hr
    FROM
        control_admissions ctrl
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ctrl.subject_id = le.subject_id
        AND ctrl.hadm_id = le.hadm_id
        AND le.charttime >= ctrl.admittime
        AND le.charttime < DATETIME_ADD(ctrl.admittime, INTERVAL 72 HOUR)
        AND le.flag = 'abnormal' -- Moved this condition to ON clause
    GROUP BY
        ctrl.subject_id, ctrl.hadm_id
),
control_summary AS (
    -- CTE 7: Summarize Critical Lab Rates for Control Cohort
    -- Computes the overall average 72-hour instability score for the control group.
    SELECT
        COUNT(DISTINCT hadm_id) AS num_control_admissions,
        AVG(instability_score_72hr) AS avg_instability_score_72hr_control
    FROM
        control_lab_scores
)
-- Final SELECT statements: Combine AMI quartile analysis and control cohort comparison
SELECT
    'AMI Patient Quartile Analysis' AS section,
    CAST(score_quartile AS STRING) AS quartile_label,
    num_admissions,
    avg_instability_score_72hr,
    avg_los_days,
    mortality_rate_percent,
    NULL AS num_control_admissions,
    NULL AS avg_instability_score_72hr_control
FROM
    ami_quartile_summary

UNION ALL

SELECT
    'Control Cohort Comparison' AS section,
    'Overall Control' AS quartile_label,
    NULL AS num_admissions,
    NULL AS avg_instability_score_72hr,
    NULL AS avg_los_days,
    NULL AS mortality_rate_percent,
    num_control_admissions,
    avg_instability_score_72hr_control
FROM
    control_summary;
WITH
age_filtered_cohort AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        -- Calculate age at the time of admission for accurate filtering
        p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 38 AND 48
),

-- CTE to identify all hospital admissions with an AMI diagnosis
ami_hadm AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for AMI start with 410
        (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '410')
        OR
        -- ICD-10 codes for AMI are I21 (initial) or I22 (subsequent)
        (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) = 'I21' OR SUBSTR(icd_code, 1, 3) = 'I22'))
),

-- CTE to combine the age-filtered cohort with AMI information, creating the final study groups
cohorts AS (
    SELECT
        afc.subject_id,
        afc.hadm_id,
        afc.admittime,
        afc.dischtime,
        afc.hospital_expire_flag,
        CASE WHEN ami.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_ami
    FROM age_filtered_cohort AS afc
    LEFT JOIN ami_hadm AS ami
        ON afc.hadm_id = ami.hadm_id
),

-- CTE to count "critical" lab events per admission within the first 72 hours
instability_scores AS (
    SELECT
        c.hadm_id,
        COUNT(le.labevent_id) AS lab_instability_score
    FROM cohorts AS c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON c.hadm_id = le.hadm_id
    WHERE
        -- Filter labs to the first 72 hours of admission, using TIMESTAMP_ADD for correctness
        le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
        AND
        -- Define criteria for "critical" lab values
        (
            (le.itemid = 51003 AND le.valuenum > 0.01)    -- Troponin T (ng/mL)
            OR (le.itemid = 50971 AND (le.valuenum < 2.5 OR le.valuenum > 6.5)) -- Potassium (mEq/L)
            OR (le.itemid = 50813 AND le.valuenum > 4)    -- Lactate (mmol/L)
            OR (le.itemid = 50912 AND le.valuenum > 4)    -- Creatinine (mg/dL)
            OR (le.itemid = 51301 AND (le.valuenum < 2 OR le.valuenum > 30)) -- White Blood Cell Count (K/uL)
            OR (le.itemid = 50820 AND (le.valuenum < 7.2 OR le.valuenum > 7.6)) -- Arterial pH
        )
    GROUP BY c.hadm_id
),

-- CTE to join scores back to the main cohort, calculate precise LOS, and handle patients with a score of 0
cohort_with_scores AS (
    SELECT
        c.hadm_id,
        c.is_ami,
        c.hospital_expire_flag,
        -- Calculate a more precise LOS in fractional days
        TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days,
        COALESCE(isc.lab_instability_score, 0) AS lab_instability_score
    FROM cohorts AS c
    LEFT JOIN instability_scores AS isc
        ON c.hadm_id = isc.hadm_id
),

-- CTE for the AMI cohort, stratifying patients into quartiles based on their instability score
ami_quartiles AS (
    SELECT
        hadm_id,
        los_days,
        hospital_expire_flag,
        lab_instability_score,
        NTILE(4) OVER (ORDER BY lab_instability_score) AS score_quartile
    FROM cohort_with_scores
    WHERE is_ami = 1
)

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- PART 1: Analyze AMI patient outcomes by lab instability score quartile.
-- In the BigQuery UI, highlight and run the SELECT statement below.
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
SELECT
    score_quartile,
    COUNT(hadm_id) AS number_of_patients,
    MIN(lab_instability_score) AS min_score_in_quartile,
    MAX(lab_instability_score) AS max_score_in_quartile,
    ROUND(AVG(los_days), 2) AS avg_length_of_stay_days,
    ROUND(AVG(CAST(hospital_expire_flag AS NUMERIC)) * 100, 2) AS in_hospital_mortality_rate_percent
FROM ami_quartiles
GROUP BY score_quartile
ORDER BY score_quartile;

/*
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- PART 2: Compare overall critical-lab rates between AMI and age-matched controls.
-- In the BigQuery UI, highlight and run the SELECT statement below.
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
SELECT
    CASE
        WHEN is_ami = 1 THEN 'AMI Patient Cohort'
        ELSE 'Control Cohort (Age-Matched, No AMI)'
    END AS cohort,
    COUNT(hadm_id) AS number_of_patients,
    SUM(lab_instability_score) AS total_critical_labs_72h,
    ROUND(AVG(lab_instability_score), 2) AS avg_critical_labs_per_patient_72h
FROM cohort_with_scores
GROUP BY is_ami
ORDER BY is_ami DESC;
*/;
WITH Admissions_DVT_Cohort AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.deathtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'M' -- Male patients
        AND pa.anchor_age BETWEEN 42 AND 52 -- Age 42-52
        AND EXISTS ( -- With DVT diagnosis
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
            WHERE di.hadm_id = ad.hadm_id
            AND
            (
                (di.icd_version = 10 AND di.icd_code LIKE 'I82%') -- ICD-10 codes for venous embolism and thrombosis (including DVT)
                OR (di.icd_version = 9 AND di.icd_code LIKE '453%') -- ICD-9 codes for other venous embolism and thrombosis (including DVT)
                -- Note: For a more precise DVT definition, specific ICD codes should be selected,
                -- potentially joining with d_icd_diagnoses to filter by long_title.
            )
        )
),
Lab_Instability_Scores AS (
    -- Calculate "72-hour lab instability score" as the count of distinct abnormal lab events
    -- (with numeric values) within the first 72 hours of admission for the DVT cohort.
    -- This is a common interpretation to derive a single score per admission for percentile calculation.
    SELECT
        adc.subject_id,
        adc.hadm_id,
        COUNT(DISTINCT le.itemid) AS lab_instability_score -- Count distinct abnormal lab items
    FROM
        Admissions_DVT_Cohort AS adc
    JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON adc.subject_id = le.subject_id AND adc.hadm_id = le.hadm_id
    WHERE
        le.charttime BETWEEN adc.admittime AND DATETIME_ADD(adc.admittime, INTERVAL 72 HOUR)
        AND le.flag = 'abnormal' -- Consider only abnormal flagged labs
        AND le.valuenum IS NOT NULL -- Ensure it's a measurable numeric lab result
    GROUP BY
        adc.subject_id, adc.hadm_id
),
P95_Threshold AS (
    -- Calculate the 95th percentile of the lab instability scores from the DVT cohort
    SELECT
        PERCENTILE_CONT(lis.lab_instability_score, 0.95) AS p95_lab_instability_score
    FROM
        Lab_Instability_Scores AS lis
),
High_Instability_Cohort_Admissions_Details AS (
    -- Identify the DVT cohort admissions with lab instability score >= 95th percentile
    SELECT
        lis.subject_id,
        lis.hadm_id,
        lis.lab_instability_score,
        adc.admittime,
        adc.dischtime,
        adc.deathtime,
        adc.hospital_expire_flag
    FROM
        Lab_Instability_Scores AS lis
    JOIN
        P95_Threshold AS p95
        ON lis.lab_instability_score >= p95.p95_lab_instability_score
    JOIN
        Admissions_DVT_Cohort AS adc
        ON lis.hadm_id = adc.hadm_id AND lis.subject_id = adc.subject_id
),
HighInstabilityStats AS (
    -- Calculate mortality rate and mean LOS for the high instability DVT cohort
    SELECT
        SAFE_DIVIDE(SUM(CASE WHEN hic.hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(hic.hadm_id)) AS mortality_rate,
        AVG(DATETIME_DIFF(hic.dischtime, hic.admittime, HOUR) / 24.0) AS mean_los_days
    FROM
        High_Instability_Cohort_Admissions_Details AS hic
),
HighInstabilityLabEvents AS (
    -- Calculate total lab events and total critical lab events for the high instability DVT cohort
    -- "Critical lab events" are defined as lab events with an 'abnormal' flag and a numeric value.
    SELECT
        COUNT(le.labevent_id) AS total_lab_events,
        COUNT(CASE WHEN le.flag = 'abnormal' AND le.valuenum IS NOT NULL THEN le.labevent_id END) AS critical_lab_events_total
    FROM
        High_Instability_Cohort_Admissions_Details AS hic
    JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON hic.hadm_id = le.hadm_id AND hic.subject_id = le.subject_id
),
AllInpatientsLabEvents AS (
    -- Calculate total lab events and total critical lab events for all inpatients
    SELECT
        COUNT(le.labevent_id) AS total_lab_events_all,
        COUNT(CASE WHEN le.flag = 'abnormal' AND le.valuenum IS NOT NULL THEN le.labevent_id END) AS critical_lab_events_total_all
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    WHERE
        le.hadm_id IS NOT NULL -- Filter for lab events associated with an inpatient admission
)
SELECT
    (SELECT p95.p95_lab_instability_score FROM P95_Threshold AS p95) AS p95_lab_instability_score,
    (SELECT his.mortality_rate FROM HighInstabilityStats AS his) AS high_instability_mortality_rate,
    (SELECT his.mean_los_days FROM HighInstabilityStats AS his) AS high_instability_mean_los_days,
    SAFE_DIVIDE((SELECT hile.critical_lab_events_total FROM HighInstabilityLabEvents AS hile), (SELECT hile.total_lab_events FROM HighInstabilityLabEvents AS hile)) AS high_instability_critical_lab_rate,
    SAFE_DIVIDE((SELECT aile.critical_lab_events_total_all FROM AllInpatientsLabEvents AS aile), (SELECT aile.total_lab_events_all FROM AllInpatientsLabEvents AS aile)) AS all_inpatients_critical_lab_rate;
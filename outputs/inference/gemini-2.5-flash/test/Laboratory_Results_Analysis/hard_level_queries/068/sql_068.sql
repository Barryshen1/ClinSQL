WITH SepticShockCohort AS (
    -- Identify the target cohort: female, 89-99 years old, with a diagnosis of septic shock, and an associated ICU stay.
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        pat.gender,
        pat.anchor_age,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        icu.stay_id,
        icu.intime AS icu_intime,
        icu.outtime AS icu_outtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON adm.hadm_id = di.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 89 AND 99
        AND (
            (di.icd_version = 10 AND di.icd_code = 'R6521') -- Septic shock ICD-10
            OR (di.icd_version = 9 AND di.icd_code = '78552')  -- Septic shock ICD-9
        )
),
-- Define common vital signs with their itemids and normal ranges
VitalSigns_Definitions AS (
    SELECT 220045 AS itemid, 'Heart Rate' AS label, 60 AS lower_bound, 100 AS upper_bound FROM UNNEST([1])
    UNION ALL SELECT 220179, 'Systolic Blood Pressure', 90, 180
    UNION ALL SELECT 220210, 'Respiratory Rate', 10, 25
    UNION ALL SELECT 223762, 'Temperature (C)', 36, 38 -- Using Celsius for consistent range
    UNION ALL SELECT 220277, 'SpO2', 90, NULL -- SpO2 is abnormal if < 90
),
VitalSignsRaw AS (
    -- Retrieve vital signs for the septic shock cohort within the first 48 hours of ICU stay
    SELECT
        ssc.stay_id,
        ce.itemid,
        ce.valuenum,
        vsd.label AS vs_label,
        vsd.lower_bound,
        vsd.upper_bound
    FROM
        SepticShockCohort ssc
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON ssc.stay_id = ce.stay_id
    INNER JOIN
        VitalSigns_Definitions vsd
        ON ce.itemid = vsd.itemid
    WHERE
        ce.valuenum IS NOT NULL
        AND ce.charttime >= ssc.icu_intime
        AND ce.charttime <= DATETIME_ADD(ssc.icu_intime, INTERVAL 48 HOUR)
),
InstabilityScores AS (
    -- Calculate the instability score for each patient in the septic shock cohort
    -- Score is the count of distinct vital signs that had at least one abnormal reading within 48h
    SELECT
        stay_id,
        COUNT(DISTINCT CASE
            WHEN (vs_label = 'Heart Rate' AND (valuenum < lower_bound OR valuenum > upper_bound)) THEN vs_label
            WHEN (vs_label = 'Systolic Blood Pressure' AND (valuenum < lower_bound OR valuenum > upper_bound)) THEN vs_label
            WHEN (vs_label = 'Respiratory Rate' AND (valuenum < lower_bound OR valuenum > upper_bound)) THEN vs_label
            WHEN (vs_label = 'Temperature (C)' AND (valuenum < lower_bound OR valuenum > upper_bound)) THEN vs_label
            WHEN (vs_label = 'SpO2' AND valuenum < lower_bound) THEN vs_label
            ELSE NULL
        END) AS instability_score
    FROM
        VitalSignsRaw
    GROUP BY
        stay_id
),
-- Define common lab tests for abnormality comparison
Lab_Definitions AS (
    SELECT 51301 AS itemid, 'WBC' AS label FROM UNNEST([1])
    UNION ALL SELECT 50912, 'Creatinine'
    UNION ALL SELECT 51265, 'Platelet Count'
    UNION ALL SELECT 50813, 'Lactate'
    UNION ALL SELECT 50885, 'Bilirubin, Total'
),
AllICUPatientsWithLabs_48h AS (
    -- Collect selected lab events for all ICU patients within their first 48 hours of ICU stay
    SELECT
        icu.stay_id,
        ld.label AS lab_label,
        le.valuenum,
        le.ref_range_lower,
        le.ref_range_upper
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON icu.subject_id = le.subject_id AND icu.hadm_id = le.hadm_id
    INNER JOIN
        Lab_Definitions ld
        ON le.itemid = ld.itemid
    WHERE
        le.valuenum IS NOT NULL
        AND le.ref_range_lower IS NOT NULL
        AND le.ref_range_upper IS NOT NULL
        AND le.charttime >= icu.intime
        AND le.charttime <= DATETIME_ADD(icu.intime, INTERVAL 48 HOUR)
),
PatientsWithAbnormalLabs_Flags AS (
    -- Flag if a patient had at least one abnormal reading for each lab type within the 48h window
    SELECT
        stay_id,
        lab_label,
        MAX(CASE
            WHEN valuenum < ref_range_lower OR valuenum > ref_range_upper THEN 1
            ELSE 0
        END) AS had_abnormal_value
    FROM
        AllICUPatientsWithLabs_48h
    GROUP BY
        stay_id, lab_label
),
CohortLabAbnormalitySummary AS (
    -- Summarize abnormal lab frequencies for the Septic Shock Cohort
    SELECT
        'Septic Shock Cohort' AS cohort_group,
        palf.lab_label,
        COUNT(DISTINCT ssc.stay_id) AS total_patients_with_lab_data,
        COUNT(DISTINCT CASE WHEN palf.had_abnormal_value = 1 THEN ssc.stay_id ELSE NULL END) AS patients_with_abnormal,
        SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN palf.had_abnormal_value = 1 THEN ssc.stay_id ELSE NULL END), COUNT(DISTINCT ssc.stay_id)) * 100 AS percentage_patients_abnormal
    FROM
        SepticShockCohort ssc
    INNER JOIN
        PatientsWithAbnormalLabs_Flags palf
        ON ssc.stay_id = palf.stay_id
    GROUP BY
        palf.lab_label
),
GeneralICULabAbnormalitySummary AS (
    -- Summarize abnormal lab frequencies for all ICU patients (General Inpatients)
    SELECT
        'General ICU Patients' AS cohort_group,
        palf.lab_label,
        COUNT(DISTINCT palf.stay_id) AS total_patients_with_lab_data,
        COUNT(DISTINCT CASE WHEN palf.had_abnormal_value = 1 THEN palf.stay_id ELSE NULL END) AS patients_with_abnormal,
        SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN palf.had_abnormal_value = 1 THEN palf.stay_id ELSE NULL END), COUNT(DISTINCT palf.stay_id)) * 100 AS percentage_patients_abnormal
    FROM
        PatientsWithAbnormalLabs_Flags palf
    GROUP BY
        palf.lab_label
)
-- Final results Union: Instability scores, LOS, Mortality, and Lab Frequencies
SELECT
    'Septic Shock Cohort Summary' AS analysis_type,
    'Instability Score Q1' AS metric_name,
    CAST(APPROX_QUANTILES(score.instability_score, 100)[OFFSET(25)] AS BIGNUMERIC) AS metric_value
FROM
    InstabilityScores score
UNION ALL
SELECT
    'Septic Shock Cohort Summary',
    'Instability Score Median',
    CAST(APPROX_QUANTILES(score.instability_score, 100)[OFFSET(50)] AS BIGNUMERIC)
FROM
    InstabilityScores score
UNION ALL
SELECT
    'Septic Shock Cohort Summary',
    'Instability Score Q3',
    CAST(APPROX_QUANTILES(score.instability_score, 100)[OFFSET(75)] AS BIGNUMERIC)
FROM
    InstabilityScores score
UNION ALL
SELECT
    'Septic Shock Cohort Summary',
    'Instability Score IQR',
    CAST((APPROX_QUANTILES(score.instability_score, 100)[OFFSET(75)] - APPROX_QUANTILES(score.instability_score, 100)[OFFSET(25)]) AS BIGNUMERIC)
FROM
    InstabilityScores score
UNION ALL
SELECT
    'Septic Shock Cohort Summary',
    'Average Hospital LOS (days)',
    CAST(AVG(DATETIME_DIFF(ssc.dischtime, ssc.admittime, HOUR) / 24.0) AS BIGNUMERIC)
FROM
    SepticShockCohort ssc
UNION ALL
SELECT
    'Septic Shock Cohort Summary',
    'Hospital Mortality (%)',
    CAST(COUNT(CASE WHEN ssc.hospital_expire_flag = 1 THEN 1 ELSE NULL END) * 100.0 / COUNT(ssc.hadm_id) AS BIGNUMERIC)
FROM
    SepticShockCohort ssc
UNION ALL
SELECT
    'Abnormal Lab Frequency - ' || clafs.cohort_group AS analysis_type,
    'Lab: ' || clafs.lab_label || ' Patients Abnormal (%)' AS metric_name,
    CAST(clafs.percentage_patients_abnormal AS BIGNUMERIC)
FROM
    CohortLabAbnormalitySummary clafs
UNION ALL
SELECT
    'Abnormal Lab Frequency - ' || glas.cohort_group AS analysis_type,
    'Lab: ' || glas.lab_label || ' Patients Abnormal (%)' AS metric_name,
    CAST(glas.percentage_patients_abnormal AS BIGNUMERIC)
FROM
    GeneralICULabAbnormalitySummary glas
ORDER BY
    analysis_type, metric_name;
WITH patient_admissions_base AS (
    -- Select all relevant admissions for potential cohort members, calculate age and LOS
    SELECT
        p.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        p.gender,
        p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year) AS age_at_admission,
        ad.insurance,
        ad.admission_location,
        -- Calculate LOS for this admission in days
        DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year)) BETWEEN 68 AND 78
        AND ad.insurance = 'Medicare'
        AND ad.admission_location LIKE 'EMERGENCY ROOM%' -- Using LIKE to catch 'EMERGENCY ROOM ADMIT'
),
cohort_index_admissions AS (
    -- Filter for admissions with a principal diagnosis of Hemorrhagic Stroke
    SELECT
        pa.subject_id,
        pa.hadm_id,
        pa.admittime,
        pa.dischtime,
        pa.hospital_expire_flag,
        pa.los_days
    FROM
        patient_admissions_base AS pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON pa.subject_id = di.subject_id AND pa.hadm_id = di.hadm_id
    WHERE
        di.seq_num = 1 -- Principal diagnosis (sequence number 1)
        AND (
               (di.icd_version = 9 AND di.icd_code IN ('430', '431', '432')) -- ICD-9 codes for Hemorrhagic Stroke (Subarachnoid, Intracerebral, Other/Unspecified Intracranial Hemorrhage)
            OR (di.icd_version = 10 AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%')) -- ICD-10 codes for Hemorrhagic Stroke
        )
),
admissions_with_readmission_info AS (
    -- For each index admission in the cohort, determine the next admission time for the same patient
    -- Also include flags needed for final calculations
    SELECT
        c.subject_id,
        c.hadm_id,
        c.admittime,
        c.dischtime,
        c.hospital_expire_flag,
        c.los_days,
        LEAD(c.admittime) OVER (PARTITION BY c.subject_id ORDER BY c.admittime) AS next_admittime_for_patient,
        -- Flag if the patient was at risk for readmission (i.e., discharged alive)
        CASE WHEN c.hospital_expire_flag = 0 THEN 1 ELSE 0 END AS at_risk_for_readmission_flag
    FROM
        cohort_index_admissions AS c
),
final_cohort_data AS (
    -- Calculate 30-day readmission status for each admission in the cohort
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        los_days,
        at_risk_for_readmission_flag,
        CASE
            WHEN at_risk_for_readmission_flag = 1 -- Patient must be discharged alive from index admission
             AND next_admittime_for_patient IS NOT NULL
             AND DATETIME_DIFF(next_admittime_for_patient, dischtime, DAY) <= 30 -- Readmission within 30 days
             AND DATETIME_DIFF(next_admittime_for_patient, dischtime, DAY) > 0 -- Exclude same-day readmissions/transfers
            THEN 1
            ELSE 0
        END AS readmitted_30_day_flag
    FROM
        admissions_with_readmission_info
)
-- Final aggregation to produce the requested metrics
SELECT
    -- 30-day readmission rate
    CAST(SUM(CASE WHEN fcd.readmitted_30_day_flag = 1 THEN 1 ELSE 0 END) * 100.0 / NULLIF(SUM(fcd.at_risk_for_readmission_flag), 0) AS BIGNUMERIC) AS readmission_rate_30_day_percent,

    -- Median Index LOS for readmitted patients (among those discharged alive and readmitted within 30 days)
    PERCENTILE_CONT(CASE WHEN fcd.readmitted_30_day_flag = 1 THEN fcd.los_days ELSE NULL END, 0.5) AS median_los_readmitted_days,

    -- Median Index LOS for non-readmitted patients (among those discharged alive and NOT readmitted within 30 days)
    PERCENTILE_CONT(CASE WHEN fcd.readmitted_30_day_flag = 0 AND fcd.at_risk_for_readmission_flag = 1 THEN fcd.los_days ELSE NULL END, 0.5) AS median_los_non_readmitted_days,

    -- Percentage of all cohort admissions with LOS > 4 days
    CAST(SUM(CASE WHEN fcd.los_days > 4 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(fcd.hadm_id), 0) AS BIGNUMERIC) AS percent_los_gt_4_days
FROM
    final_cohort_data AS fcd;
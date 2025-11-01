WITH Admissions_Cohort AS (
    -- Step 1: Identify the target patient cohort based on age, gender
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        -- Define robust time windows, capping at dischtime and flooring at admittime for short stays
        LEAST(DATETIME_ADD(ad.admittime, INTERVAL '48' HOUR), ad.dischtime) AS first_48h_end,
        GREATEST(ad.admittime, DATETIME_SUB(ad.dischtime, INTERVAL '24' HOUR)) AS final_24h_start,
        (pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'F'
        AND (pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)) BETWEEN 51 AND 61
),
Patient_Diagnoses AS (
    -- Step 2: Identify patients within the cohort who have both diabetes and acute heart failure
    SELECT
        dc.subject_id,
        dc.hadm_id,
        MAX(CASE
            WHEN dc.icd_version = 9 AND dc.icd_code LIKE '250%' THEN 1
            WHEN dc.icd_version = 10 AND dc.icd_code BETWEEN 'E10' AND 'E14' THEN 1
            WHEN d_icd.long_title LIKE '%diabetes mellitus%' THEN 1
            ELSE 0
        END) AS has_diabetes,
        MAX(CASE
            WHEN dc.icd_version = 9 AND dc.icd_code LIKE '428%' THEN 1 -- Broad for HF
            WHEN dc.icd_version = 10 AND dc.icd_code IN ('I500', 'I501', 'I5030', 'I5031', 'I5032', 'I5033', 'I5040', 'I5041', 'I5042', 'I5043') THEN 1 -- Specific acute HF ICD10
            WHEN d_icd.long_title LIKE '%acute heart failure%' THEN 1
            ELSE 0
        END) AS has_acute_hf
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
        ON dc.icd_code = d_icd.icd_code AND dc.icd_version = d_icd.icd_version
    GROUP BY
        dc.subject_id, dc.hadm_id
    HAVING
        MAX(CASE
            WHEN dc.icd_version = 9 AND dc.icd_code LIKE '250%' THEN 1
            WHEN dc.icd_version = 10 AND dc.icd_code BETWEEN 'E10' AND 'E14' THEN 1
            WHEN d_icd.long_title LIKE '%diabetes mellitus%' THEN 1
            ELSE 0
        END) = 1
        AND MAX(CASE
            WHEN dc.icd_version = 9 AND dc.icd_code LIKE '428%' THEN 1
            WHEN dc.icd_version = 10 AND dc.icd_code IN ('I500', 'I501', 'I5030', 'I5031', 'I5032', 'I5033', 'I5040', 'I5041', 'I5042', 'I5043') THEN 1
            WHEN d_icd.long_title LIKE '%acute heart failure%' THEN 1
            ELSE 0
        END) = 1
),
Final_Cohort AS (
    -- Step 3: Combine admission and diagnosis criteria to get the final patient cohort
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.admittime,
        ac.dischtime,
        ac.first_48h_end,
        ac.final_24h_start
    FROM
        Admissions_Cohort ac
    INNER JOIN
        Patient_Diagnoses pd
        ON ac.subject_id = pd.subject_id AND ac.hadm_id = pd.hadm_id
),
Medication_Identification AS (
    -- Step 4: Categorize medications and check their presence/start/stop times within the defined windows
    SELECT
        fc.subject_id,
        fc.hadm_id,
        p.drug,
        LOWER(p.drug) LIKE '%insulin%' AS is_insulin,
        (
            LOWER(p.drug) LIKE '%metformin%' OR
            LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' OR
            LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR
            LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' OR
            LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR
            LOWER(p.drug) LIKE '%repaglinide%' OR LOWER(p.drug) LIKE '%nateglinide%' OR
            LOWER(p.drug) LIKE '%acarbose%' OR LOWER(p.drug) LIKE '%miglitol%'
        ) AS is_oral_agent,
        p.starttime,
        COALESCE(p.stoptime, fc.dischtime) AS stoptime_effective, -- Assume continued until discharge if stoptime is null

        -- Check if medication is present (active) in the first 48h window
        (p.starttime <= fc.first_48h_end AND COALESCE(p.stoptime, fc.dischtime) >= fc.admittime) AS active_in_first_48h,
        -- Check if medication is present (active) in the final 24h window
        (p.starttime <= fc.dischtime AND COALESCE(p.stoptime, fc.dischtime) >= fc.final_24h_start) AS active_in_final_24h,

        -- For initiated/discontinued counts (events within window)
        (p.starttime >= fc.admittime AND p.starttime <= fc.first_48h_end) AS initiated_first_48h_event,
        (p.stoptime >= fc.admittime AND p.stoptime <= fc.first_48h_end) AS discontinued_first_48h_event,
        (p.starttime >= fc.final_24h_start AND p.starttime <= fc.dischtime) AS initiated_final_24h_event,
        (p.stoptime >= fc.final_24h_start AND p.stoptime <= fc.dischtime) AS discontinued_final_24h_event
    FROM
        Final_Cohort fc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON fc.subject_id = p.subject_id AND fc.hadm_id = p.hadm_id
    WHERE
        -- Filter for relevant drug types
        (LOWER(p.drug) LIKE '%insulin%' OR
         LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%glipizide%' OR
         LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' OR
         LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR
         LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%pioglitazone%' OR
         LOWER(p.drug) LIKE '%rosiglitazone%' OR LOWER(p.drug) LIKE '%canagliflozin%' OR
         LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR
         LOWER(p.drug) LIKE '%repaglinide%' OR LOWER(p.drug) LIKE '%nateglinide%' OR
         LOWER(p.drug) LIKE '%acarbose%' OR LOWER(p.drug) LIKE '%miglitol%')
),
Patient_Med_Summary AS (
    -- Step 5: Summarize medication presence and events per patient-admission
    SELECT
        subject_id,
        hadm_id,
        -- Flags for percentage calculations (patient received at least one drug of this type)
        MAX(CASE WHEN is_insulin THEN active_in_first_48h ELSE FALSE END) AS insulin_active_first_48h_flag,
        MAX(CASE WHEN is_oral_agent THEN active_in_first_48h ELSE FALSE END) AS oral_agent_active_first_48h_flag,
        MAX(CASE WHEN is_insulin THEN active_in_final_24h ELSE FALSE END) AS insulin_active_final_24h_flag,
        MAX(CASE WHEN is_oral_agent THEN active_in_final_24h ELSE FALSE END) AS oral_agent_active_final_24h_flag,

        -- Counts for initiated/discontinued events within each respective window (sum of distinct drugs)
        COUNT(DISTINCT CASE WHEN is_insulin AND initiated_first_48h_event THEN drug END) AS insulin_initiated_first_48h_count,
        COUNT(DISTINCT CASE WHEN is_oral_agent AND initiated_first_48h_event THEN drug END) AS oral_agent_initiated_first_48h_count,
        COUNT(DISTINCT CASE WHEN is_insulin AND discontinued_first_48h_event THEN drug END) AS insulin_discontinued_first_48h_count,
        COUNT(DISTINCT CASE WHEN is_oral_agent AND discontinued_first_48h_event THEN drug END) AS oral_agent_discontinued_first_48h_count,

        COUNT(DISTINCT CASE WHEN is_insulin AND initiated_final_24h_event THEN drug END) AS insulin_initiated_final_24h_count,
        COUNT(DISTINCT CASE WHEN is_oral_agent AND initiated_final_24h_event THEN drug END) AS oral_agent_initiated_final_24h_count,
        COUNT(DISTINCT CASE WHEN is_insulin AND discontinued_final_24h_event THEN drug END) AS insulin_discontinued_final_24h_count,
        COUNT(DISTINCT CASE WHEN is_oral_agent AND discontinued_final_24h_event THEN drug END) AS oral_agent_discontinued_final_24h_count,

        -- Flags for patient-level changes between windows (continued, initiated btw, discontinued btw)
        MAX(CASE WHEN is_insulin AND active_in_first_48h AND active_in_final_24h THEN TRUE ELSE FALSE END) AS insulin_continued_across_windows_flag,
        MAX(CASE WHEN is_oral_agent AND active_in_first_48h AND active_in_final_24h THEN TRUE ELSE FALSE END) AS oral_agent_continued_across_windows_flag,
        MAX(CASE WHEN is_insulin AND active_in_final_24h AND NOT active_in_first_48h THEN TRUE ELSE FALSE END) AS insulin_initiated_between_windows_flag,
        MAX(CASE WHEN is_oral_agent AND active_in_final_24h AND NOT active_in_first_48h THEN TRUE ELSE FALSE END) AS oral_agent_initiated_between_windows_flag,
        MAX(CASE WHEN is_insulin AND active_in_first_48h AND NOT active_in_final_24h THEN TRUE ELSE FALSE END) AS insulin_discontinued_between_windows_flag,
        MAX(CASE WHEN is_oral_agent AND active_in_first_48h AND NOT active_in_final_24h THEN TRUE ELSE FALSE END) AS oral_agent_discontinued_between_windows_flag
    FROM
        Medication_Identification
    GROUP BY
        subject_id, hadm_id
)
-- Step 6: Final Aggregation and Reporting
SELECT
    COUNT(DISTINCT pms.hadm_id) AS total_admissions_in_cohort,

    -- Percentages of patients ON Insulin / Oral Agents in First 48h
    SUM(CASE WHEN pms.insulin_active_first_48h_flag THEN 1 ELSE 0 END) AS admissions_with_insulin_first_48h,
    (SUM(CASE WHEN pms.insulin_active_first_48h_flag THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT pms.hadm_id)) AS percent_insulin_first_48h,
    SUM(CASE WHEN pms.oral_agent_active_first_48h_flag THEN 1 ELSE 0 END) AS admissions_with_oral_agent_first_48h,
    (SUM(CASE WHEN pms.oral_agent_active_first_48h_flag THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT pms.hadm_id)) AS percent_oral_agent_first_48h,

    -- Percentages of patients ON Insulin / Oral Agents in Final 24h
    SUM(CASE WHEN pms.insulin_active_final_24h_flag THEN 1 ELSE 0 END) AS admissions_with_insulin_final_24h,
    (SUM(CASE WHEN pms.insulin_active_final_24h_flag THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT pms.hadm_id)) AS percent_insulin_final_24h,
    SUM(CASE WHEN pms.oral_agent_active_final_24h_flag THEN 1 ELSE 0 END) AS admissions_with_oral_agent_final_24h,
    (SUM(CASE WHEN pms.oral_agent_active_final_24h_flag THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT pms.hadm_id)) AS percent_oral_agent_final_24h,

    -- Counts of Insulin initiated/discontinued events within First 48h
    SUM(pms.insulin_initiated_first_48h_count) AS total_insulin_initiated_first_48h_events,
    SUM(pms.oral_agent_initiated_first_48h_count) AS total_oral_agent_initiated_first_48h_events,
    SUM(pms.insulin_discontinued_first_48h_count) AS total_insulin_discontinued_first_48h_events,
    SUM(pms.oral_agent_discontinued_first_48h_count) AS total_oral_agent_discontinued_first_48h_events,

    -- Counts of Insulin initiated/discontinued events within Final 24h
    SUM(pms.insulin_initiated_final_24h_count) AS total_insulin_initiated_final_24h_events,
    SUM(pms.oral_agent_initiated_final_24h_count) AS total_oral_agent_initiated_final_24h_events,
    SUM(pms.insulin_discontinued_final_24h_count) AS total_insulin_discontinued_final_24h_events,
    SUM(pms.oral_agent_discontinued_final_24h_count) AS total_oral_agent_discontinued_final_24h_events,

    -- Patient-level counts of medication changes between the two windows
    SUM(CASE WHEN pms.insulin_continued_across_windows_flag THEN 1 ELSE 0 END) AS patients_with_insulin_continued_between_windows,
    SUM(CASE WHEN pms.oral_agent_continued_across_windows_flag THEN 1 ELSE 0 END) AS patients_with_oral_agent_continued_between_windows,
    SUM(CASE WHEN pms.insulin_initiated_between_windows_flag THEN 1 ELSE 0 END) AS patients_with_insulin_initiated_between_windows,
    SUM(CASE WHEN pms.oral_agent_initiated_between_windows_flag THEN 1 ELSE 0 END) AS patients_with_oral_agent_initiated_between_windows,
    SUM(CASE WHEN pms.insulin_discontinued_between_windows_flag THEN 1 ELSE 0 END) AS patients_with_insulin_discontinued_between_windows,
    SUM(CASE WHEN pms.oral_agent_discontinued_between_windows_flag THEN 1 ELSE 0 END) AS patients_with_oral_agent_discontinued_between_windows
FROM
    Patient_Med_Summary pms;
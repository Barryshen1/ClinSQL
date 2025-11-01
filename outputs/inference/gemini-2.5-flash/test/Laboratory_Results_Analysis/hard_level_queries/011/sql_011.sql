WITH BaseCohort AS (
    -- 1. Identify male patients aged 47-57
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 47 AND 57
),
AKI_Admissions AS (
    -- 2. Identify admissions with Acute Kidney Injury (AKI) diagnosis
    SELECT DISTINCT
        bc.subject_id,
        bc.hadm_id
    FROM
        BaseCohort AS bc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON bc.hadm_id = di.hadm_id
    WHERE
        -- ICD-9 codes for Acute Kidney Failure
        (di.icd_version = 9 AND di.icd_code LIKE '584%')
        -- ICD-10 codes for Acute Kidney Injury
        OR (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
),
CohortWithAKIStatus AS (
    -- Assign each admission to either 'AKI' or 'Control' group
    SELECT
        bc.*,
        CASE WHEN aai.hadm_id IS NOT NULL THEN 'AKI' ELSE 'Control' END AS CohortGroup
    FROM
        BaseCohort AS bc
    LEFT JOIN
        AKI_Admissions AS aai
        ON bc.hadm_id = aai.hadm_id
),
LabInstability_72h AS (
    -- 3. Calculate 72-hour laboratory instability score
    -- (Count of distinct lab items with 'abnormal' flag within first 72 hours of admission)
    SELECT
        cws.hadm_id,
        COUNT(DISTINCT dl.label) AS num_distinct_abnormal_labs
    FROM
        CohortWithAKIStatus AS cws
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON cws.subject_id = le.subject_id AND cws.hadm_id = le.hadm_id
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dl
        ON le.itemid = dl.itemid
    WHERE
        le.charttime BETWEEN cws.admittime AND TIMESTAMP_ADD(cws.admittime, INTERVAL 72 HOUR)
        AND le.flag = 'abnormal' -- Filter for abnormal lab results
    GROUP BY
        cws.hadm_id
),
Critical_Procedures AS (
    -- 4. Identify critical events (mechanical ventilation or renal replacement therapy)
    SELECT DISTINCT
        cws.hadm_id,
        1 AS critical_event_flag
    FROM
        CohortWithAKIStatus AS cws
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
        ON cws.hadm_id = pi.hadm_id
    WHERE
        (
            pi.icd_version = 9 AND
            (pi.icd_code LIKE '96.7%' -- ICD-9: Mechanical Ventilation
             OR pi.icd_code IN ('39.95', '54.98')) -- ICD-9: Hemodialysis, Peritoneal dialysis
        )
        OR
        (
            pi.icd_version = 10 AND
            (pi.icd_code LIKE '5A19%' -- ICD-10: Respiratory support/Mechanical Ventilation
             OR pi.icd_code LIKE '5A1D%') -- ICD-10: Renal Replacement Therapy (e.g., Hemodialysis, Peritoneal dialysis)
        )
),
AdmissionMetrics AS (
    -- Combine all calculated metrics for each admission
    SELECT
        cws.subject_id,
        cws.hadm_id,
        cws.CohortGroup,
        -- Coalesce to 0 if no abnormal labs found in 72h
        COALESCE(lis.num_distinct_abnormal_labs, 0) AS lab_instability_score,
        -- Coalesce to 0 if no critical procedures found
        COALESCE(cp.critical_event_flag, 0) AS critical_event_occurred,
        -- Calculate length of stay in days
        DATETIME_DIFF(cws.dischtime, cws.admittime, HOUR) / 24.0 AS length_of_stay_days,
        -- In-hospital mortality flag
        cws.hospital_expire_flag
    FROM
        CohortWithAKIStatus AS cws
    LEFT JOIN
        LabInstability_72h AS lis
        ON cws.hadm_id = lis.hadm_id
    LEFT JOIN
        Critical_Procedures AS cp
        ON cws.hadm_id = cp.hadm_id
)
-- Final aggregation to compare AKI and Control groups
SELECT
    am.CohortGroup,
    COUNT(DISTINCT am.hadm_id) AS num_admissions,
    AVG(am.lab_instability_score) AS mean_72h_lab_instability_score,
    -- Critical event frequency (proportion of admissions with critical event)
    AVG(am.critical_event_occurred) AS critical_event_frequency,
    AVG(am.length_of_stay_days) AS average_length_of_stay_days,
    -- In-hospital mortality rate (proportion of admissions with hospital_expire_flag = 1)
    AVG(am.hospital_expire_flag) AS in_hospital_mortality_rate
FROM
    AdmissionMetrics AS am
GROUP BY
    am.CohortGroup
ORDER BY
    am.CohortGroup;
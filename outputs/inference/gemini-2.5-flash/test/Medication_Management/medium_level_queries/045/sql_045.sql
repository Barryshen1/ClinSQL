WITH AdmissionsCohort AS (
    -- Select relevant admission and patient demographics, define time windows for analysis
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        -- Calculate the start time for the final 48 hours, ensuring it's not before admittime
        CASE
            WHEN TIMESTAMP_DIFF(ad.dischtime, ad.admittime, HOUR) < 48
            THEN ad.admittime
            ELSE TIMESTAMP_SUB(ad.dischtime, INTERVAL 48 HOUR)
        END AS final48_start_time,
        -- Calculate the end time for the first 12 hours
        TIMESTAMP_ADD(ad.admittime, INTERVAL 12 HOUR) AS first12_end_time
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age >= 54
        AND p.anchor_age <= 64
        -- Filter for inpatient admissions (excluding 'OBSERVATION', 'DIRECT EMER', 'AMBULATORY', 'EW EMER')
        AND ad.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE', 'DIRECT ADMIT')
),
DiabetesPatients AS (
    -- Identify patients with a diagnosis of Diabetes (ICD-9 or ICD-10)
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND icd_code LIKE '250%') -- ICD-9 for Diabetes mellitus
        OR (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%')) -- ICD-10 for Diabetes mellitus
),
HeartFailurePatients AS (
    -- Identify patients with a diagnosis of Heart Failure (ICD-9 or ICD-10)
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND icd_code LIKE '428%') -- ICD-9 for Heart Failure
        OR (icd_version = 10 AND icd_code LIKE 'I50%') -- ICD-10 for Heart Failure
),
QualifiedCohort AS (
    -- Combine demographics and diagnoses to get the final cohort of interest
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.admittime,
        ac.dischtime,
        ac.final48_start_time,
        ac.first12_end_time
    FROM
        AdmissionsCohort ac
    INNER JOIN
        DiabetesPatients dp
        ON ac.subject_id = dp.subject_id AND ac.hadm_id = dp.hadm_id
    INNER JOIN
        HeartFailurePatients hfp
        ON ac.subject_id = hfp.subject_id AND ac.hadm_id = hfp.hadm_id
),
MedicationExposure AS (
    -- Determine if insulin or oral agents were prescribed within the defined time windows for each patient
    SELECT
        qc.subject_id,
        qc.hadm_id,
        -- Flag for insulin in the first 12 hours
        MAX(CASE WHEN LOWER(p.drug) LIKE '%insulin%' AND p.starttime >= qc.admittime AND p.starttime <= qc.first12_end_time THEN 1 ELSE 0 END) AS has_insulin_first12,
        -- Flag for oral agents in the first 12 hours
        MAX(CASE
            WHEN (LOWER(p.drug) LIKE '%metformin%'
                  OR LOWER(p.drug) LIKE '%glipizide%'
                  OR LOWER(p.drug) LIKE '%glyburide%'
                  OR LOWER(p.drug) LIKE '%gliptin%'    -- e.g., sitagliptin, saxagliptin, linagliptin
                  OR LOWER(p.drug) LIKE '%gliflozin%')  -- e.g., empagliflozin, canagliflozin, dapagliflozin
            AND p.starttime >= qc.admittime AND p.starttime <= qc.first12_end_time THEN 1 ELSE 0 END) AS has_oral_agent_first12,
        -- Flag for insulin in the final 48 hours
        MAX(CASE WHEN LOWER(p.drug) LIKE '%insulin%' AND p.starttime >= qc.final48_start_time AND p.starttime <= qc.dischtime THEN 1 ELSE 0 END) AS has_insulin_final48,
        -- Flag for oral agents in the final 48 hours
        MAX(CASE
            WHEN (LOWER(p.drug) LIKE '%metformin%'
                  OR LOWER(p.drug) LIKE '%glipizide%'
                  OR LOWER(p.drug) LIKE '%glyburide%'
                  OR LOWER(p.drug) LIKE '%gliptin%'
                  OR LOWER(p.drug) LIKE '%gliflozin%')
            AND p.starttime >= qc.final48_start_time AND p.starttime <= qc.dischtime THEN 1 ELSE 0 END) AS has_oral_agent_final48
    FROM
        QualifiedCohort qc
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON qc.subject_id = p.subject_id AND qc.hadm_id = p.hadm_id
    GROUP BY
        qc.subject_id, qc.hadm_id
)
-- Final aggregation to calculate prevalence and net change
SELECT
    COUNT(DISTINCT me.hadm_id) AS total_admissions_in_cohort,

    -- Counts of patients exposed to insulin/oral agents in each window
    SUM(me.has_insulin_first12) AS insulin_first12_count,
    SUM(me.has_oral_agent_first12) AS oral_agent_first12_count,
    SUM(me.has_insulin_final48) AS insulin_final48_count,
    SUM(me.has_oral_agent_final48) AS oral_agent_final48_count,

    -- Prevalence percentages for each medication type and window
    SAFE_DIVIDE(SUM(me.has_insulin_first12), COUNT(DISTINCT me.hadm_id)) * 100 AS insulin_first12_prevalence_perc,
    SAFE_DIVIDE(SUM(me.has_oral_agent_first12), COUNT(DISTINCT me.hadm_id)) * 100 AS oral_agent_first12_prevalence_perc,
    SAFE_DIVIDE(SUM(me.has_insulin_final48), COUNT(DISTINCT me.hadm_id)) * 100 AS insulin_final48_prevalence_perc,
    SAFE_DIVIDE(SUM(me.has_oral_agent_final48), COUNT(DISTINCT me.hadm_id)) * 100 AS oral_agent_final48_prevalence_perc,

    -- Net change in percentage points (Final 48h - First 12h)
    (SAFE_DIVIDE(SUM(me.has_insulin_final48), COUNT(DISTINCT me.hadm_id)) - SAFE_DIVIDE(SUM(me.has_insulin_first12), COUNT(DISTINCT me.hadm_id))) * 100 AS insulin_net_change_pp,
    (SAFE_DIVIDE(SUM(me.has_oral_agent_final48), COUNT(DISTINCT me.hadm_id)) - SAFE_DIVIDE(SUM(me.has_oral_agent_first12), COUNT(DISTINCT me.hadm_id))) * 100 AS oral_agent_net_change_pp
FROM
    MedicationExposure me;
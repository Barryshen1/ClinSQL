WITH AdmissionsWithHF AS (
    -- Step 1: Identify all admissions with a heart failure diagnosis
    SELECT DISTINCT
        di.subject_id,
        di.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE
        (di.icd_version = 9 AND di.icd_code LIKE '428%')  -- ICD-9 code for Heart Failure
        OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%') -- ICD-10 code for Heart Failure
),
AllAdmissionsLabeled AS (
    -- Step 2: Label each admission as target cohort or general inpatient
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        -- Calculate LOS upfront for convenience
        TIMESTAMP_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 AS los_days,
        CASE
            WHEN pat.gender = 'M'
            AND pat.anchor_age BETWEEN 37 AND 47
            AND hf.hadm_id IS NOT NULL -- TRUE if this admission has HF
            THEN 1
            ELSE 0
        END AS is_target_cohort
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON ad.subject_id = pat.subject_id
    LEFT JOIN
        AdmissionsWithHF hf
        ON ad.subject_id = hf.subject_id AND ad.hadm_id = hf.hadm_id
),
CriticalLabEvents_Within72H AS (
    -- Step 3: Find all critical lab events for all admissions within the first 72 hours
    SELECT
        le.subject_id,
        le.hadm_id,
        le.itemid
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN
        AllAdmissionsLabeled aal
        ON le.subject_id = aal.subject_id AND le.hadm_id = aal.hadm_id
    WHERE
        le.valuenum IS NOT NULL
        AND le.ref_range_lower IS NOT NULL
        AND le.ref_range_upper IS NOT NULL
        AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
        AND le.charttime BETWEEN aal.admittime AND TIMESTAMP_ADD(aal.admittime, INTERVAL 72 HOUR)
),
AdmissionInstabilityScores AS (
    -- Step 4: Calculate instability score (count of unique critical lab types) for each admission
    SELECT
        aal.subject_id,
        aal.hadm_id,
        aal.admittime,
        aal.dischtime,
        aal.hospital_expire_flag,
        aal.is_target_cohort,
        aal.los_days, -- Include pre-calculated LOS
        COUNT(DISTINCT cle.itemid) AS instability_score
    FROM
        AllAdmissionsLabeled aal
    LEFT JOIN -- Use LEFT JOIN to include admissions with no critical lab events (score of 0)
        CriticalLabEvents_Within72H cle
        ON aal.subject_id = cle.subject_id AND aal.hadm_id = cle.hadm_id
    GROUP BY
        aal.subject_id,
        aal.hadm_id,
        aal.admittime,
        aal.dischtime,
        aal.hospital_expire_flag,
        aal.is_target_cohort,
        aal.los_days
)
-- Step 5: Final aggregation to report the requested metrics for the target cohort
SELECT
    'Target Cohort' AS cohort_type,
    MAX(instability_score) AS max_lab_instability_score,
    AVG(instability_score) AS avg_critical_event_rate,
    AVG(los_days) AS avg_los_days,
    AVG(hospital_expire_flag) AS mortality_rate
FROM
    AdmissionInstabilityScores
WHERE
    is_target_cohort = 1

UNION ALL

-- Step 6: Final aggregation for general inpatients (Non-Target Cohort)
SELECT
    'General Inpatients (Non-Target Cohort)' AS cohort_type,
    CAST(NULL AS BIGNUMERIC) AS max_lab_instability_score, -- Max score is only asked for the specific cohort, cast NULL to match type
    AVG(instability_score) AS avg_critical_event_rate,
    AVG(los_days) AS avg_los_days,
    AVG(hospital_expire_flag) AS mortality_rate
FROM
    AdmissionInstabilityScores
WHERE
    is_target_cohort = 0;
WITH PatientsCohort AS (
    -- Step 1: Identify male patients aged 46-56
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 46 AND 56
),
StrokeDiagnoses AS (
    -- Step 2: Identify definite stroke diagnoses (ICD-9 and ICD-10) for any admission
    SELECT DISTINCT
        d.subject_id,
        d.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE
        (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '43899') -- ICD-9 stroke ranges
        OR (d.icd_version = 10 AND d.icd_code BETWEEN 'I60' AND 'I6999') -- ICD-10 stroke ranges
),
FirstAdmissionStrokePatients AS (
    -- Step 3: Filter for the first hospital admission for each patient in the cohort who also had a stroke.
    SELECT
        pc.subject_id,
        a.hadm_id,
        a.admittime,
        ROW_NUMBER() OVER (PARTITION BY pc.subject_id ORDER BY a.admittime) AS rn_adm
    FROM
        PatientsCohort pc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON pc.subject_id = a.subject_id
    INNER JOIN
        StrokeDiagnoses sd
        ON a.subject_id = sd.subject_id AND a.hadm_id = sd.hadm_id
    WHERE
        a.deathtime IS NULL OR a.deathtime > a.admittime -- Ensure admission was not just a death record,
                                                           -- or that the patient didn't die before admission
),
ICU_LOS_Data AS (
    -- Step 4 & 5: For these first admissions, find their first ICU stay and calculate LOS in days.
    SELECT
        fas.subject_id,
        fas.hadm_id,
        icu.stay_id,
        TIMESTAMP_DIFF(icu.outtime, icu.intime, DAY) AS los_days, -- Direct calculation in days
        ROW_NUMBER() OVER (PARTITION BY fas.subject_id, fas.hadm_id ORDER BY icu.intime) AS rn_icu
    FROM
        FirstAdmissionStrokePatients fas
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON fas.subject_id = icu.subject_id AND fas.hadm_id = icu.hadm_id
    WHERE
        fas.rn_adm = 1 -- Only consider the first hospital admission
        AND icu.los >= 0 -- Ensure positive or zero LOS for valid stays, although TIMESTAMP_DIFF would usually yield positive
)
-- Step 6: Calculate Q1, Q3, and IQR from the LOS values of the first ICU stay during the first admission.
SELECT
    PERCENTILE_CONT(los_days, 0.25) OVER () AS q1_los_days,
    PERCENTILE_CONT(los_days, 0.75) OVER () AS q3_los_days,
    (PERCENTILE_CONT(los_days, 0.75) OVER () - PERCENTILE_CONT(los_days, 0.25) OVER ()) AS iqr_los_days
FROM
    ICU_LOS_Data
WHERE
    rn_icu = 1 -- Only consider the first ICU stay within that first admission
QUALIFY ROW_NUMBER() OVER (ORDER BY 1) = 1 -- Ensure only one row for the final result
;
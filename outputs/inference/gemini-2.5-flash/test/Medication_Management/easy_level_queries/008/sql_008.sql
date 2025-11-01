WITH PatientCohort AS (
    -- Step 1: Identify eligible patient admissions (men 64-74 years old)
    SELECT
        pa.subject_id,
        ad.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age >= 64
        AND pa.anchor_age <= 74
),
AntiplateletPrescriptions AS (
    -- Step 2: Identify relevant antiplatelet prescriptions (Aspirin OR P2Y12 inhibitors)
    -- for the identified patient cohort, ensuring valid duration calculation.
    SELECT
        pc.subject_id,
        pc.hadm_id,
        p.drug,
        p.starttime,
        p.stoptime
    FROM
        PatientCohort pc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON pc.subject_id = p.subject_id AND pc.hadm_id = p.hadm_id
    WHERE
        p.drug IN (
            'ASPIRIN', -- Aspirin
            'CLOPIDOGREL', 'TICAGRELOR', 'PRASUGREL' -- Common P2Y12 inhibitors
        )
        AND p.starttime IS NOT NULL
        AND p.stoptime IS NOT NULL
        AND p.stoptime >= p.starttime -- Exclude erroneous entries where stoptime is before starttime
),
AdmissionsWithBothAntiplatelets AS (
    -- Step 3: Identify (subject_id, hadm_id) pairs that received BOTH Aspirin AND a P2Y12 inhibitor
    SELECT
        subject_id,
        hadm_id
    FROM
        AntiplateletPrescriptions
    GROUP BY
        subject_id,
        hadm_id
    HAVING
        -- Check if Aspirin was prescribed at least once
        SUM(CASE WHEN drug = 'ASPIRIN' THEN 1 ELSE 0 END) > 0
        AND
        -- Check if any P2Y12 inhibitor was prescribed at least once
        SUM(CASE WHEN drug IN ('CLOPIDOGREL', 'TICAGRELOR', 'PRASUGREL') THEN 1 ELSE 0 END) > 0
),
CalculatedDurations AS (
    -- Step 4: For the qualified admissions, calculate the duration for each individual
    -- antiplatelet prescription (aspirin or P2Y12 inhibitor).
    SELECT
        ap.subject_id,
        ap.hadm_id,
        ap.drug,
        -- Calculate duration in fractional days for higher precision
        TIMESTAMP_DIFF(ap.stoptime, ap.starttime, SECOND) / (60 * 60 * 24.0) AS prescription_duration_days
    FROM
        AntiplateletPrescriptions ap
    INNER JOIN
        AdmissionsWithBothAntiplatelets awba
        ON ap.subject_id = awba.subject_id AND ap.hadm_id = awba.hadm_id
    WHERE
        -- Filter again to ensure we only process antiplatelet drugs (redundant due to AntiplateletPrescriptions CTE,
        -- but good for clarity on what's being measured)
        ap.drug IN (
            'ASPIRIN',
            'CLOPIDOGREL', 'TICAGRELOR', 'PRASUGREL'
        )
)
-- Step 5: Calculate the median of all these individual antiplatelet prescription durations.
SELECT
    PERCENTILE_CONT(prescription_duration_days, 0.5) OVER() AS median_inpatient_antiplatelet_prescription_duration_days
FROM
    CalculatedDurations
LIMIT 1; -- We only need a single row for the overall median value;
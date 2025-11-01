WITH PatientCohort AS (
    -- Select subject_ids for male patients aged 64-74 at admission
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 64 AND 74
),
SpironolactoneEplerenonePrescriptions AS (
    -- Select relevant prescriptions and calculate their duration in hours
    SELECT
        pr.subject_id,
        pr.hadm_id, -- Not strictly needed for the final average, but good for context
        pr.drug,
        pr.starttime,
        pr.stoptime,
        -- Calculate duration in hours
        TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR) AS duration_hours
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    WHERE
        -- Filter for spironolactone or eplerenone, case-insensitive
        (LOWER(pr.drug) LIKE '%spironolactone%' OR LOWER(pr.drug) LIKE '%eplerenone%')
        -- Ensure valid start and stop times for duration calculation
        AND pr.starttime IS NOT NULL
        AND pr.stoptime IS NOT NULL
        -- Ensure stoptime is after starttime to get valid positive durations
        AND pr.stoptime > pr.starttime
)
-- Calculate the average prescription duration in days for the specified cohort
SELECT
    AVG(pres.duration_hours / 24.0) AS average_prescription_duration_days
FROM
    SpironolactoneEplerenonePrescriptions pres
JOIN
    PatientCohort cohort
    ON pres.subject_id = cohort.subject_id;
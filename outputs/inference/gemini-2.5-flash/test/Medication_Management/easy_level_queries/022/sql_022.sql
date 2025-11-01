WITH FilteredPrescriptions AS (
    SELECT
        TIMESTAMP_DIFF(pr.stoptime, pr.starttime, MINUTE) / 60.0 AS duration_hours -- Calculate duration in hours
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON adm.hadm_id = pr.hadm_id
    WHERE
        p.gender = 'F' -- Filter for female patients
        AND p.anchor_age BETWEEN 59 AND 69 -- Filter for age range 59-69
        AND (
            -- Filter for Dihydropyridine CCB drug names (case-insensitive)
            LOWER(pr.drug) LIKE '%amlodipine%'
            OR LOWER(pr.drug) LIKE '%felodipine%'
            OR LOWER(pr.drug) LIKE '%isradipine%'
            OR LOWER(pr.drug) LIKE '%nicardipine%'
            OR LOWER(pr.drug) LIKE '%nifedipine%'
            OR LOWER(pr.drug) LIKE '%nimodipine%'
        )
        AND NOT (
            -- Exclude non-dihydropyridine CCBs, if their names might overlap
            LOWER(pr.drug) LIKE '%verapamil%'
            OR LOWER(pr.drug) LIKE '%diltiazem%'
        )
        AND pr.starttime IS NOT NULL -- Ensure start time is recorded
        AND pr.stoptime IS NOT NULL -- Ensure stop time is recorded
        AND pr.stoptime > pr.starttime -- Ensure valid duration (stop time after start time)
)
SELECT
    PERCENTILE_CONT(duration_hours, 0.5) OVER () AS median_prescription_duration_hours
FROM
    FilteredPrescriptions
LIMIT 1;
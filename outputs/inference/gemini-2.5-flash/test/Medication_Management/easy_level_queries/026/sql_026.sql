SELECT
    PERCENTILE_CONT(duration_days, 0.25) OVER() AS p25_duration_days
FROM (
    SELECT
        -- Calculate prescription duration in inclusive calendar days.
        -- For example, if starttime is 2023-01-01 10:00:00 and stoptime is 2023-01-01 14:00:00,
        -- DATE_DIFF(DATE('2023-01-01'), DATE('2023-01-01'), DAY) + 1 = 0 + 1 = 1 day.
        -- If starttime is 2023-01-01 10:00:00 and stoptime is 2023-01-02 09:00:00,
        -- DATE_DIFF(DATE('2023-01-02'), DATE('2023-01-01'), DAY) + 1 = 1 + 1 = 2 days.
        DATE_DIFF(DATE(prc.stoptime), DATE(prc.starttime), DAY) + 1 AS duration_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` prc
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON prc.subject_id = p.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON prc.hadm_id = adm.hadm_id AND prc.subject_id = adm.subject_id
    WHERE
        p.gender = 'F' -- Filter for female patients
        AND p.anchor_age BETWEEN 81 AND 91 -- Filter for age group 81-91
        -- Ensure valid start and stop times for duration calculation
        AND prc.starttime IS NOT NULL
        AND prc.stoptime IS NOT NULL
        AND prc.stoptime >= prc.starttime -- Ensure stoptime is not earlier than starttime
        -- Filter for Dihydropyridine CCBs using common drug names
        AND (
               LOWER(prc.drug) LIKE '%amlodipine%'
            OR LOWER(prc.drug) LIKE '%felodipine%'
            OR LOWER(prc.drug) LIKE '%isradipine%'
            OR LOWER(prc.drug) LIKE '%nicardipine%'
            OR LOWER(prc.drug) LIKE '%nifedipine%'
            OR LOWER(prc.drug) LIKE '%nimodipine%'
            OR LOWER(prc.drug) LIKE '%nisoldipine%'
            OR LOWER(prc.drug) LIKE '%lercanidipine%'
        )
) AS filtered_prescriptions
LIMIT 1;
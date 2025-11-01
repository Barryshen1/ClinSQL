WITH ccb_prescriptions AS (
    SELECT 
        p.subject_id,
        pr.hadm_id,
        pr.starttime,
        pr.stoptime,
        -- Calculate duration in days
        DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON pr.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 59 AND 69
        AND pr.hadm_id IS NOT NULL  -- Ensure inpatient
        AND pr.stoptime IS NOT NULL
        AND pr.starttime IS NOT NULL
        AND pr.stoptime > pr.starttime  -- Positive duration
        AND (
            LOWER(pr.drug) LIKE '%amlodipine%' OR
            LOWER(pr.drug) LIKE '%nifedipine%' OR
            LOWER(pr.drug) LIKE '%felodipine%' OR
            LOWER(pr.drug) LIKE '%isradipine%' OR
            LOWER(pr.drug) LIKE '%nicardipine%'
        )
)
SELECT 
    APPROX_QUANTILES(duration_days, 100)[OFFSET(50)] AS median_duration_days
FROM ccb_prescriptions;
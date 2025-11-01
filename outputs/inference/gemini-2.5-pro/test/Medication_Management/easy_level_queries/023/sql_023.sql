WITH patient_cohort AS (
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 78 AND 88
)
-- Then, calculate the standard deviation of prescription durations for this cohort
SELECT
    STDDEV_SAMP(DATETIME_DIFF(pr.stoptime, pr.starttime, DAY)) AS sd_acei_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
INNER JOIN
    patient_cohort AS pc
    ON pr.subject_id = pc.subject_id
WHERE
    -- Filter for common ACE-inhibitor medications.
    -- Using LOWER() and LIKE makes the matching robust to variations in drug naming.
    (
        LOWER(pr.drug) LIKE '%lisinopril%'
        OR LOWER(pr.drug) LIKE '%enalapril%'
        OR LOWER(pr.drug) LIKE '%ramipril%'
        OR LOWER(pr.drug) LIKE '%benazepril%'
        OR LOWER(pr.drug) LIKE '%captopril%'
        OR LOWER(pr.drug) LIKE '%fosinopril%'
        OR LOWER(pr.drug) LIKE '%moexipril%'
        OR LOWER(pr.drug) LIKE '%perindopril%'
        OR LOWER(pr.drug) LIKE '%quinapril%'
        OR LOWER(pr.drug) LIKE '%trandolapril%'
    )
    -- Ensure the prescription has a defined start and stop time to calculate duration
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    -- Exclude discharge prescriptions, as their duration reflects take-home supply, not inpatient administration time
    AND pr.drug_type != 'DISCH'
    -- Ensure duration is positive to avoid data entry errors
    AND pr.stoptime > pr.starttime;
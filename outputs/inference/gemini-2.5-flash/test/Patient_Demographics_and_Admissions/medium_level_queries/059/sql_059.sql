WITH AdmissionsCohort AS (
    SELECT
        admit.subject_id,
        admit.hadm_id,
        -- Calculate Length of Stay in days
        DATETIME_DIFF(admit.dischtime, admit.admittime, HOUR) / 24.0 AS los_days,
        -- Categorize discharge locations as requested by the question
        CASE
            WHEN admit.discharge_location = 'HOME' THEN 'Home'
            WHEN admit.discharge_location = 'HOSPICE' THEN 'Hospice'
            WHEN admit.discharge_location = 'DEAD/EXPIRED' THEN 'In-hospital Death'
            ELSE 'Other/Unknown' -- Catch all other discharge locations
        END AS discharge_group
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS admit
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON admit.subject_id = pat.subject_id
    WHERE
        -- Filter for female patients
        pat.gender = 'F'
        -- Filter for anchor age between 75 and 85
        AND pat.anchor_age BETWEEN 75 AND 85
        -- Filter for admissions transferred from another hospital
        AND admit.admission_location = 'TRANSFER FROM HOSPITAL'
        -- Ensure discharge time is available for LOS calculation
        AND admit.dischtime IS NOT NULL
)
SELECT
    ac.discharge_group,
    -- Proportion of admissions with LOS >= 7 days
    SUM(CASE WHEN ac.los_days >= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(ac.hadm_id) AS proportion_los_ge_7_days_percent,
    -- Proportion of admissions with LOS <= 7 days (interpreted as "7-day percentile")
    SUM(CASE WHEN ac.los_days <= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(ac.hadm_id) AS proportion_los_le_7_days_percent
FROM
    AdmissionsCohort AS ac
GROUP BY
    ac.discharge_group
ORDER BY
    ac.discharge_group;
WITH admissions_filtered_los AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        -- Calculate length of stay in days
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        -- Determine discharge status
        CASE
            WHEN a.deathtime IS NOT NULL THEN 'Died'
            ELSE 'Alive'
        END AS discharge_status
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 67 AND 77
        AND a.admission_location = 'EMERGENCY ROOM'
        -- Ensure valid discharge and admission times for LOS calculation
        AND a.dischtime IS NOT NULL
        AND a.admittime IS NOT NULL
        -- Ensure LOS is non-negative
        AND DATE_DIFF(a.dischtime, a.admittime, DAY) >= 0
)
SELECT
    discharge_status,
    -- Proportion of patients with LOS >= 7 days
    SAFE_DIVIDE(COUNTIF(los_days >= 7), COUNT(hadm_id)) AS proportion_los_ge_7_days,
    -- Proportion of patients with LOS >= 14 days
    SAFE_DIVIDE(COUNTIF(los_days >= 14), COUNT(hadm_id)) AS proportion_los_ge_14_days,
    -- Proportion of patients with LOS <= 10 days (interpreting "percentile rank for 10-day LOS")
    SAFE_DIVIDE(COUNTIF(los_days <= 10), COUNT(hadm_id)) AS proportion_los_le_10_days
FROM
    admissions_filtered_los
GROUP BY
    discharge_status
ORDER BY
    discharge_status;
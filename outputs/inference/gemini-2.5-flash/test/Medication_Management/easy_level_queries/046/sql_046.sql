SELECT
    PERCENTILE_CONT(
        DATE_DIFF(ph.stoptime, ph.starttime, DAY),
        0.5
    ) OVER () AS median_prescription_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON p.subject_id = ph.subject_id
WHERE
    p.gender = 'M'
    AND p.anchor_age = 91 -- In MIMIC-IV, `anchor_age` = 91 represents patients aged 90 or above.
    AND (
        LOWER(ph.medication) LIKE '%spironolactone%'
        OR LOWER(ph.medication) LIKE '%eplerenone%'
    )
    AND ph.starttime IS NOT NULL
    AND ph.stoptime IS NOT NULL
    AND DATE_DIFF(ph.stoptime, ph.starttime, DAY) > 0 -- Ensure a positive duration in days;
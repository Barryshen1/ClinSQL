SELECT
    MAX(DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR)) AS max_nitrate_prescription_duration_hours
FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pa
    ON pr.subject_id = pa.subject_id
WHERE
    -- 1. Filter for the patient cohort: females aged 80-90
    pa.gender = 'F'
    AND pa.anchor_age BETWEEN 80 AND 90
    -- 2. Filter for the specified routes: IV, Oral (PO), Sublingual (SL)
    AND pr.route IN ('IV', 'PO', 'SL')
    -- 3. Filter for nitrate medications using common names
    AND (
        LOWER(pr.drug) LIKE '%nitroglycerin%'
        OR LOWER(pr.drug) LIKE '%isosorbide%'
        OR LOWER(pr.drug) LIKE '%nitrate%'
    )
    -- 4. Ensure the duration is valid and can be calculated
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime;
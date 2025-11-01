SELECT
    MAX(DATETIME_DIFF(p.stoptime, p.starttime, HOUR)) AS max_nitrate_duration_hours
FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON p.subject_id = pat.subject_id
WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 80 AND 90
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND (
        -- Filter for common therapeutic nitrate drugs
        LOWER(p.drug) LIKE '%nitroglycerin%'
        OR LOWER(p.drug) LIKE '%isosorbide mononitrate%'
        OR LOWER(p.drug) LIKE '%isosorbide dinitrate%'
        -- General nitrate, explicitly excluding common non-therapeutic nitrates like silver nitrate
        OR (LOWER(p.drug) LIKE '%nitrate%' AND LOWER(p.drug) NOT LIKE '%silver nitrate%')
    )
    AND LOWER(p.route) IN ('iv', 'oral', 'sublingual');
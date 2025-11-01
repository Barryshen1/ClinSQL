SELECT
    PERCENTILE_CONT(duration_minutes, 0.75) OVER() - PERCENTILE_CONT(duration_minutes, 0.25) OVER() AS iqr_duration_minutes
FROM (
    SELECT
        DATETIME_DIFF(pres.stoptime, pres.starttime, MINUTE) AS duration_minutes
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON pat.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
        ON adm.subject_id = pres.subject_id AND adm.hadm_id = pres.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 57 AND 67
        AND adm.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT', 'NEWBORN') -- Filter for inpatient admissions
        AND (
            LOWER(pres.drug) LIKE '%aspirin%' OR
            LOWER(pres.drug) LIKE '%clopidogrel%' OR
            LOWER(pres.drug) LIKE '%ticagrelor%' OR
            LOWER(pres.drug) LIKE '%prasugrel%'
        )
        AND pres.starttime IS NOT NULL
        AND pres.stoptime IS NOT NULL
        AND pres.stoptime > pres.starttime -- Ensure valid, non-zero duration
) AS PrescriptionDurations
LIMIT 1;
SELECT MIN(duration_days) AS min_duration_days
FROM (
    SELECT 
        (UNIX_SECONDS(CAST(admissions.dischtime AS TIMESTAMP)) - UNIX_SECONDS(CAST(admissions.admittime AS TIMESTAMP))) / 86400.0 AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` admissions
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
        ON admissions.subject_id = patients.subject_id
    WHERE 
        patients.gender = 'F'
        AND (patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)) BETWEEN 81 AND 91
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
            WHERE 
                pres.subject_id = admissions.subject_id
                AND pres.hadm_id = admissions.hadm_id
                AND (
                    LOWER(pres.drug) LIKE '%hydralazine%'
                    OR LOWER(pres.drug) LIKE '%isosorbide dinitrate%'
                )
        )
);
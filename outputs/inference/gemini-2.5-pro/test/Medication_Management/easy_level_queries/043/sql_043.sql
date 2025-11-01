SELECT
    MIN(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS shortest_inpatient_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
WHERE
    -- 1. Filter for female patients between 81 and 91 years old at admission
    pat.gender = 'F'
    AND ((EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age) BETWEEN 81 AND 91
    -- 2. Filter for admissions where hydralazine or isosorbide dinitrate were prescribed
    AND adm.hadm_id IN (
        SELECT DISTINCT
            pr.hadm_id
        FROM
            `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
        WHERE
            LOWER(pr.drug) LIKE '%hydralazine%'
            OR LOWER(pr.drug) LIKE '%isosorbide dinitrate%'
    )
    -- 3. Ensure the duration is calculable and positive
    AND adm.dischtime > adm.admittime;
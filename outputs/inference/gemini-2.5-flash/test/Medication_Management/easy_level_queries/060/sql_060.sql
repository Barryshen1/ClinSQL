SELECT
    MAX(DATE_DIFF(pres.stoptime, pres.starttime, DAY)) AS longest_acei_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pres.subject_id = pat.subject_id
WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 38 AND 48
    AND (
           LOWER(pres.drug) LIKE '%lisinopril%'
        OR LOWER(pres.drug) LIKE '%enalapril%'
        OR LOWER(pres.drug) LIKE '%ramipril%'
        OR LOWER(pres.drug) LIKE '%captopril%'
        OR LOWER(pres.drug) LIKE '%perindopril%'
        OR LOWER(pres.drug) LIKE '%quinapril%'
        OR LOWER(pres.drug) LIKE '%benazepril%'
        OR LOWER(pres.drug) LIKE '%fosinopril%'
        OR LOWER(pres.drug) LIKE '%moexipril%'
        OR LOWER(pres.drug) LIKE '%trandolapril%'
    )
    AND pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
    AND pres.stoptime >= pres.starttime -- Ensure stoptime is not before starttime
;
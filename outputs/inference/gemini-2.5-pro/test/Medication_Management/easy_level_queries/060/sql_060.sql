SELECT
    MAX(DATETIME_DIFF(pr.stoptime, pr.starttime, DAY)) AS longest_ace_inhibitor_prescription_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON p.subject_id = pr.subject_id
WHERE
    -- 1. Filter for the patient cohort: female, aged 38-48
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48

    -- 2. Filter for common ACE inhibitors by generic name
    AND (
        LOWER(pr.drug) LIKE '%lisinopril%'
        OR LOWER(pr.drug) LIKE '%enalapril%'
        OR LOWER(pr.drug) LIKE '%enalaprilat%'
        OR LOWER(pr.drug) LIKE '%ramipril%'
        OR LOWER(pr.drug) LIKE '%benazepril%'
        OR LOWER(pr.drug) LIKE '%captopril%'
        OR LOWER(pr.drug) LIKE '%quinapril%'
        OR LOWER(pr.drug) LIKE '%fosinopril%'
        OR LOWER(pr.drug) LIKE '%perindopril%'
        OR LOWER(pr.drug) LIKE '%trandolapril%'
        OR LOWER(pr.drug) LIKE '%moexipril%'
    )

    -- 3. Ensure start and stop times are valid for duration calculation
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL;
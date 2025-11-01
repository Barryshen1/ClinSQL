WITH ace_prescriptions AS (
    SELECT
        p.subject_id,
        pr.drug,
        pr.starttime,
        pr.stoptime,
        DATE_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON pr.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 38 AND 48
        AND pr.stoptime IS NOT NULL
        AND pr.stoptime >= pr.starttime
        AND (
            LOWER(pr.drug) LIKE '%ace inhibitor%'
            OR LOWER(pr.drug) LIKE '%lisinopril%'
            OR LOWER(pr.drug) LIKE '%enalapril%'
            OR LOWER(pr.drug) LIKE '%ramipril%'
            OR LOWER(pr.drug) LIKE '%benazepril%'
            OR LOWER(pr.drug) LIKE '%captopril%'
            OR LOWER(pr.drug) LIKE '%fosinopril%'
            OR LOWER(pr.drug) LIKE '%moexipril%'
            OR LOWER(pr.drug) LIKE '%perindopril%'
            OR LOWER(pr.drug) LIKE '%quinapril%'
            OR LOWER(pr.drug) LIKE '%trandolapril%'
        )
)
SELECT
    MAX(duration_days) AS longest_ace_inhibitor_prescription_days
FROM ace_prescriptions;
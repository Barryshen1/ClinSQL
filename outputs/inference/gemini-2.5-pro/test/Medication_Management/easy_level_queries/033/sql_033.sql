SELECT
    AVG(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY)) AS avg_prescription_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pa
    ON pr.subject_id = pa.subject_id
WHERE
    -- 1. Filter for the patient cohort: women aged 77-87
    pa.gender = 'F'
    AND pa.anchor_age BETWEEN 77 AND 87

    -- 2. Filter for Angiotensin II Receptor Blocker (ARB) medications
    -- This uses a case-insensitive regular expression to find common ARBs by name
    AND REGEXP_CONTAINS(pr.drug, r'(?i)losartan|valsartan|irbesartan|candesartan|olmesartan|telmisartan|azilsartan')

    -- 3. Ensure a valid duration can be calculated by excluding null or illogical timestamps
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime;
SELECT
    -- Calculate the 75th percentile from a list of 100 quantiles.
    APPROX_QUANTILES(DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR) / 24.0, 100)[OFFSET(75)] AS p75_prescription_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON adm.hadm_id = pr.hadm_id
WHERE
    -- 1. Filter for the patient cohort: Males aged 38-48 at admission
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age) BETWEEN 38 AND 48

    -- 2. Filter for ARB (Angiotensin II Receptor Blocker) medications
    AND (
        LOWER(pr.drug) LIKE '%losartan%' OR
        LOWER(pr.drug) LIKE '%valsartan%' OR
        LOWER(pr.drug) LIKE '%irbesartan%' OR
        LOWER(pr.drug) LIKE '%candesartan%' OR
        LOWER(pr.drug) LIKE '%olmesartan%' OR
        LOWER(pr.drug) LIKE '%telmisartan%' OR
        LOWER(pr.drug) LIKE '%azilsartan%'
    )

    -- 3. Ensure the prescription has a valid, calculable duration
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime;
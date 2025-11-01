WITH FirstAdmission AS (
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        a.admittime,
        a.hospital_expire_flag,
        ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
),
PatientAges AS (
    SELECT
        f.subject_id,
        f.gender,
        -- Calculate age at first admission.
        -- anchor_age is the patient's age in the anchor_year.
        -- We adjust this age based on the difference between the admission year and the anchor_year.
        (f.anchor_age + (EXTRACT(YEAR FROM f.admittime) - f.anchor_year)) AS age_at_first_admission,
        f.hospital_expire_flag
    FROM
        FirstAdmission f
    WHERE
        f.rn = 1 -- Select only the first admission for each patient
)
SELECT
    -- Fix: BigQuery's PERCENTILE_CONT uses the syntax PERCENTILE_CONT(expression, percentile) OVER (...).
    -- It does not use 'WITHIN GROUP (ORDER BY ...)'.
    PERCENTILE_CONT(hospital_expire_flag, 0.25) OVER () AS mortality_25th_percentile
FROM
    PatientAges
WHERE
    gender = 'M'
    AND age_at_first_admission BETWEEN 73 AND 83;
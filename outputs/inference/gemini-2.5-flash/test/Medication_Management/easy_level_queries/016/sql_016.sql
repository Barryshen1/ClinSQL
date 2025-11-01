WITH PatientAdmissions AS (
    -- Select relevant patient and admission details, and calculate age at admission
    SELECT
        p.subject_id,
        a.hadm_id,
        p.gender,
        p.anchor_age,
        a.admittime,
        -- Calculate age at admission: anchor_age is the age at anchor_year
        -- We adjust it by the difference between the admission year and anchor_year
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
),
FilteredAdmissions AS (
    -- Apply gender and age criteria for inpatient admissions
    SELECT
        pa.subject_id,
        pa.hadm_id,
        pa.admittime,
        pa.age_at_admission
    FROM
        PatientAdmissions pa
    WHERE
        pa.gender = 'M'
        AND pa.age_at_admission BETWEEN 76 AND 86
),
NitratePrescriptions AS (
    -- Identify IV or oral nitrate prescriptions for the filtered patient group
    SELECT
        fa.subject_id,
        fa.hadm_id,
        pr.starttime,
        pr.stoptime,
        pr.drug,
        pr.route
    FROM
        FilteredAdmissions fa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON fa.subject_id = pr.subject_id AND fa.hadm_id = pr.hadm_id
    WHERE
        pr.starttime IS NOT NULL
        AND pr.stoptime IS NOT NULL
        AND pr.starttime < pr.stoptime -- Ensure a valid, positive duration
        AND (
            LOWER(pr.drug) LIKE '%nitroglycerin%'
            OR LOWER(pr.drug) LIKE '%isordil%' -- Common brand for isosorbide dinitrate
            OR LOWER(pr.drug) LIKE '%isosorbide dinitrate%'
            OR LOWER(pr.drug) LIKE '%isosorbide mononitrate%'
        )
        AND (
            LOWER(pr.route) LIKE '%iv%'
            OR LOWER(pr.route) LIKE '%oral%'
            OR LOWER(pr.route) LIKE '%po%'
        )
),
PrescriptionDurations AS (
    -- Calculate the duration in fractional days for each relevant prescription
    SELECT
        subject_id,
        hadm_id,
        drug,
        route,
        -- Calculate duration in seconds and convert to fractional days
        DATETIME_DIFF(stoptime, starttime, SECOND) / (60 * 60 * 24.0) AS duration_days
    FROM
        NitratePrescriptions
)
-- Calculate the 25th percentile of these durations
SELECT
    -- Corrected PERCENTILE_CONT usage: include the column name as the first argument
    PERCENTILE_CONT(duration_days, 0.25) OVER () AS p25_duration_days
FROM
    PrescriptionDurations;
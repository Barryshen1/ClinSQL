WITH PatientAdmissions AS (
    -- Select female patients aged 60-70 at the time of their hospital admission
    SELECT
        pa.subject_id,
        ad.hadm_id,
        -- Calculate age at admission. MIMIC-IV uses anchor_age and anchor_year
        -- to preserve relative age while de-identifying actual birth year.
        EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year + pa.anchor_age AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'F'
        AND (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year + pa.anchor_age) BETWEEN 60 AND 70
),
AtorvastatinPrescriptions AS (
    -- Filter for Atorvastatin prescriptions with dose 40-80 mg for the target population
    SELECT
        pa.subject_id,
        pa.hadm_id,
        pres.starttime,
        pres.stoptime,
        SAFE_CAST(pres.dose_val_rx AS FLOAT64) AS numeric_dose_val_rx -- Cast to numeric type
    FROM
        PatientAdmissions pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
        ON pa.subject_id = pres.subject_id AND pa.hadm_id = pres.hadm_id
    WHERE
        LOWER(pres.drug) = 'atorvastatin' -- Ensure drug is Atorvastatin, case-insensitive
        AND pres.dose_unit_rx = 'mg'        -- Ensure unit is milligrams
        AND SAFE_CAST(pres.dose_val_rx AS FLOAT64) IS NOT NULL -- Ensure a valid number can be parsed
        AND SAFE_CAST(pres.dose_val_rx AS FLOAT64) >= 40       -- Dose value is 40mg or more
        AND SAFE_CAST(pres.dose_val_rx AS FLOAT64) <= 80       -- Dose value is 80mg or less
        AND pres.starttime IS NOT NULL   -- Ensure start time exists
        AND pres.stoptime IS NOT NULL    -- Ensure stop time exists
        AND pres.stoptime >= pres.starttime -- Ensure stop time is not before start time
),
PrescriptionDurations AS (
    -- Calculate the duration of each qualifying prescription in days
    SELECT
        DATETIME_DIFF(stoptime, starttime, DAY) AS duration_days
    FROM
        AtorvastatinPrescriptions
    WHERE
        DATETIME_DIFF(stoptime, starttime, DAY) >= 0 -- Ensure non-negative duration
)
-- Calculate the Interquartile Range (IQR) of the prescription durations
SELECT
    PERCENTILE_CONT(duration_days, 0.75) OVER() - PERCENTILE_CONT(duration_days, 0.25) OVER() AS iqr_duration_days
FROM
    PrescriptionDurations
LIMIT 1; -- Use LIMIT 1 because the analytic function with OVER() without PARTITION BY produces the same result for all rows.;
WITH PatientAdmissions AS (
    SELECT
        pa.subject_id,
        ad.hadm_id,
        -- Calculate age at admission by adding the difference in years
        -- between admittime and anchor_year to the patient's anchor_age.
        pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'M' -- Filter for males
        -- Filter admissions for patients aged between 62 and 72 at the time of admission.
        AND (pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)) BETWEEN 62 AND 72
),
AmiodaronePrescriptionDurations AS (
    SELECT
        -- Calculate the duration of each amiodarone prescription in days.
        TIMESTAMP_DIFF(pres.stoptime, pres.starttime, DAY) AS duration_days
    FROM
        PatientAdmissions pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
        ON pa.subject_id = pres.subject_id AND pa.hadm_id = pres.hadm_id
    WHERE
        pres.drug = 'Amiodarone' -- Filter for amiodarone prescriptions
        AND pres.starttime IS NOT NULL -- Ensure start time is available
        AND pres.stoptime IS NOT NULL -- Ensure stop time is available
        AND pres.stoptime >= pres.starttime -- Ensure valid duration (stop time not before start time)
)
SELECT
    -- Calculate the 75th percentile (Q3) of duration_days
    APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] AS q3_duration_days,
    -- Calculate the 25th percentile (Q1) of duration_days
    APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS q1_duration_days,
    -- Calculate the Interquartile Range (IQR) as Q3 - Q1
    (APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)]) AS iqr_duration_days
FROM
    AmiodaronePrescriptionDurations;
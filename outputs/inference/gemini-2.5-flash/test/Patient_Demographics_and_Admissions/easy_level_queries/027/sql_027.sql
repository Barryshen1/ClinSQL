WITH PatientFirstAdmissions AS (
    SELECT
        pa.subject_id,
        ad.admittime,
        ad.dischtime,
        pa.gender,
        pa.anchor_age,
        ROW_NUMBER() OVER (PARTITION BY pa.subject_id ORDER BY ad.admittime) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'F' -- Filter for females
        AND pa.anchor_age BETWEEN 77 AND 87 -- Filter for age range 77-87 inclusive
        AND ad.dischtime IS NOT NULL -- Exclude ongoing admissions without a discharge time
),
FirstAdmissionLOS AS (
    SELECT
        subject_id,
        DATE_DIFF(dischtime, admittime, DAY) AS los_days
    FROM
        PatientFirstAdmissions
    WHERE
        rn = 1 -- Select only the first admission for each patient
        AND DATE_DIFF(dischtime, admittime, DAY) >= 0 -- Ensure a valid (non-negative) length of stay
)
SELECT
    PERCENTILE_CONT(los_days, 0.75) OVER() - PERCENTILE_CONT(los_days, 0.25) OVER() AS iqr_first_admission_los_days
FROM
    FirstAdmissionLOS
QUALIFY ROW_NUMBER() OVER(ORDER BY 1) = 1; -- Get a single row with the final IQR;
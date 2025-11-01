WITH first_admissions AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        p.gender,
        p.anchor_year,
        p.anchor_age,
        -- Compute birth date: Jan 1 of anchor_year minus anchor_age years
        DATE_SUB(DATE(p.anchor_year, 1, 1), INTERVAL p.anchor_age YEAR) AS birth_date
    FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
        ON a.subject_id = p.subject_id
),
first_admission_per_patient AS (
    SELECT 
        *,
        TIMESTAMP_DIFF(admittime, birth_date, YEAR) AS age_at_admission
    FROM (
        SELECT 
            *,
            ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
        FROM first_admissions
    )
    WHERE rn = 1
),
filtered_data AS (
    SELECT 
        TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
    FROM first_admission_per_patient
    WHERE 
        gender = 'F'
        AND age_at_admission BETWEEN 77 AND 87
        AND dischtime IS NOT NULL
)
SELECT 
    quartiles[SAFE_OFFSET(3)] - quartiles[SAFE_OFFSET(1)] AS iqr
FROM (
    SELECT APPROX_QUANTILES(los_days, 4) AS quartiles
    FROM filtered_data
);
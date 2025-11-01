WITH admissions_filtered AS (
    SELECT 
        a.hadm_id,
        a.admittime,
        a.dischtime,
        p.subject_id,
        p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime)) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND a.admittime IS NOT NULL
        AND a.dischtime IS NOT NULL
        AND p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime)) BETWEEN 73 AND 83
),
nitrate_prescriptions AS (
    SELECT 
        af.hadm_id,
        af.admittime,
        af.dischtime,
        p.starttime,
        p.stoptime,
        COALESCE(p.stoptime, af.dischtime) AS stoptime_actual
    FROM admissions_filtered af
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON af.hadm_id = p.hadm_id
    WHERE 
        p.starttime IS NOT NULL
        AND (
            LOWER(p.drug) LIKE '%nitroglycerin%'
            OR LOWER(p.drug) LIKE '%isosorbide dinitrate%'
            OR LOWER(p.drug) LIKE '%isosorbide mononitrate%'
        )
),
prescription_durations AS (
    SELECT 
        CASE 
            WHEN GREATEST(starttime, admittime) > LEAST(stoptime_actual, dischtime) 
                THEN 0 
            ELSE DATETIME_DIFF(LEAST(stoptime_actual, dischtime), GREATEST(starttime, admittime), SECOND) / (24*60*60)
        END AS duration_days
    FROM nitrate_prescriptions
)
SELECT 
    STDDEV_SAMP(duration_days) AS sd_duration_days
FROM prescription_durations
WHERE duration_days > 0;
WITH PatientFilter AS (
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age >= 90
        AND pa.anchor_age <= 100
),
ThiazidePrescriptions_Raw AS (
    SELECT
        pf.subject_id,
        pf.hadm_id,
        -- Using LIKE to cover common thiazide-like diuretics and potential variations
        pr.drug,
        pr.starttime,
        pr.stoptime,
        pf.admittime,
        pf.dischtime
    FROM
        PatientFilter pf
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON pf.subject_id = pr.subject_id AND pf.hadm_id = pr.hadm_id
    WHERE
        pr.stoptime IS NOT NULL
        AND pr.starttime IS NOT NULL
        AND (
            LOWER(pr.drug) LIKE '%hydrochlorothiazide%' OR
            LOWER(pr.drug) LIKE '%hctz%' OR
            LOWER(pr.drug) LIKE '%chlorthalidone%' OR
            LOWER(pr.drug) LIKE '%indapamide%' OR
            LOWER(pr.drug) LIKE '%metolazone%' OR
            LOWER(pr.drug) LIKE '%zaroxolyn%' -- Brand name for metolazone
        )
),
ThiazidePrescriptions_EffectiveDuration AS (
    SELECT
        subject_id,
        hadm_id,
        drug,
        -- Cap prescription start/stop times to admission start/end times
        GREATEST(starttime, admittime) AS effective_start_time,
        LEAST(stoptime, dischtime) AS effective_stop_time
    FROM
        ThiazidePrescriptions_Raw
),
FinalDurations AS (
    SELECT
        DATE_DIFF(effective_stop_time, effective_start_time, DAY) AS duration_days
    FROM
        ThiazidePrescriptions_EffectiveDuration
    WHERE
        -- Ensure the effective period has a valid duration (start <= end)
        effective_stop_time >= effective_start_time
)
SELECT
    PERCENTILE_CONT(duration_days, 0.75) OVER() - PERCENTILE_CONT(duration_days, 0.25) OVER() AS iqr_duration_days
FROM
    FinalDurations
LIMIT 1;
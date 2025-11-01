WITH cohort_raw AS (
    SELECT
        p.subject_id,
        ad.hadm_id,
        icu.stay_id,
        p.gender,
        ad.admittime,
        icu.intime AS icu_intime,
        icu.los AS icu_los,
        ad.hospital_expire_flag,
        -- Calculate age at admission: anchor_age is the age in anchor_year.
        -- We add the difference in years to get the age at admittime.
        p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad ON p.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu ON ad.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year)) BETWEEN 40 AND 50
),
hemorrhagic_stroke_patients AS (
    SELECT DISTINCT
        cr.hadm_id
    FROM
        cohort_raw cr
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON cr.hadm_id = di.hadm_id
    WHERE
        -- ICD-10 codes for hemorrhagic stroke
        di.icd_version = 10 AND di.icd_code IN ('I60', 'I61', 'I62')
),
cohort_with_diagnosis AS (
    SELECT
        cr.*,
        CASE
            WHEN hsp.hadm_id IS NOT NULL THEN 'Hemorrhagic Stroke'
            ELSE 'Other Males 40-50'
        END AS hemorrhagic_stroke_group
    FROM
        cohort_raw cr
    LEFT JOIN
        hemorrhagic_stroke_patients hsp ON cr.hadm_id = hsp.hadm_id
),
procedures_72h_count AS (
    SELECT
        cwd.stay_id,
        COUNT(proc.icd_code) AS num_procedures_72h -- Counts each recorded procedure within the window
    FROM
        cohort_with_diagnosis cwd
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc ON cwd.hadm_id = proc.hadm_id
    WHERE
        -- Filter procedures within the first 72 hours of ICU admission.
        -- procedures_icd.chartdate is a DATE, icu_intime is DATETIME.
        -- This condition includes procedures on the calendar day of icu_intime
        -- up to and including the calendar day that the 72-hour mark falls on.
        proc.chartdate <= DATE(DATETIME_ADD(cwd.icu_intime, INTERVAL 72 HOUR))
        AND proc.chartdate >= DATE(cwd.icu_intime) -- Ensure procedures are not before ICU admission
    GROUP BY
        cwd.stay_id
)
SELECT
    cwd.hemorrhagic_stroke_group,
    -- 90th percentile of diagnostic procedures within 72 hours
    APPROX_QUANTILES(COALESCE(p72.num_procedures_72h, 0), 100)[OFFSET(90)] AS p90_diagnostic_procedures_first_72h,

    -- ICU Length of Stay (LOS) statistics
    AVG(cwd.icu_los) AS avg_icu_los_days,
    APPROX_QUANTILES(cwd.icu_los, 100)[OFFSET(50)] AS median_icu_los_days,
    MIN(cwd.icu_los) AS min_icu_los_days,
    MAX(cwd.icu_los) AS max_icu_los_days,

    -- In-hospital mortality rate
    AVG(cwd.hospital_expire_flag) * 100 AS in_hospital_mortality_percent
FROM
    cohort_with_diagnosis cwd
LEFT JOIN
    procedures_72h_count p72 ON cwd.stay_id = p72.stay_id
GROUP BY
    cwd.hemorrhagic_stroke_group
ORDER BY
    cwd.hemorrhagic_stroke_group;
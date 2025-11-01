WITH PatientAgeICU AS (
    -- Select patients, admissions, and ICU stays, filtering by gender and age on admission
    SELECT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        p.gender,
        p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON adm.subject_id = icu.subject_id AND adm.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 37 AND 47
),
FirstSpO2PerStay AS (
    -- Find the first recorded SpO2 value for each ICU stay
    SELECT
        ce.valuenum AS spo2_value
    FROM
        PatientAgeICU AS pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON pa.subject_id = ce.subject_id
        AND pa.hadm_id = ce.hadm_id
        AND pa.stay_id = ce.stay_id
    WHERE
        ce.itemid = 220277 -- ItemID for 'O2 saturation pulseoxymetry' (from d_items)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum BETWEEN 0 AND 100 -- Physiological range for SpO2 percentage
    QUALIFY ROW_NUMBER() OVER (PARTITION BY pa.stay_id ORDER BY ce.charttime) = 1
)
-- Calculate the Interquartile Range (IQR) of these first SpO2 values
SELECT
    PERCENTILE_CONT(spo2_value, 0.75) OVER() - PERCENTILE_CONT(spo2_value, 0.25) OVER() AS iqr_first_spo2
FROM
    FirstSpO2PerStay;
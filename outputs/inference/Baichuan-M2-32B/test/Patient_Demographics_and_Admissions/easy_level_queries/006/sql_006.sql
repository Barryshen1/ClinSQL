WITH patient_admissions AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        -- Estimate birth date: anchor_year is the year of the anchor event, anchor_age is the age at that event.
        -- We assume the anchor event is on January 1st of the anchor_year for simplicity.
        DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR) AS birth_date
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
        -- We'll compute age later, but we can pre-filter by anchor_year to reduce data
        AND p.anchor_year BETWEEN 1950 AND 2005  -- approximate birth years for 58-68 in 2012-2020 (typical admission years)
),
age_filtered AS (
    SELECT
        subject_id,
        hadm_id,
        admittime,
        birth_date,
        TIMESTAMP_DIFF(admittime, birth_date, YEAR) AS age_at_admission
    FROM patient_admissions
    WHERE TIMESTAMP_DIFF(admittime, birth_date, YEAR) BETWEEN 58 AND 68
),
sepsis_admissions AS (
    SELECT
        af.subject_id,
        af.hadm_id,
        af.admittime,
        af.age_at_admission
    FROM age_filtered af
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON af.subject_id = di.subject_id
        AND af.hadm_id = di.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
        AND di.icd_version = dd.icd_version
    WHERE LOWER(dd.long_title) LIKE '%sepsis%'
        OR LOWER(dd.long_title) LIKE '%septic%'
    -- Remove duplicates per admission (if multiple sepsis diagnoses, we only need one per admission)
    GROUP BY af.subject_id, af.hadm_id, af.admittime, af.age_at_admission
),
icu_stays AS (
    SELECT
        s.hadm_id,
        SUM(s.los) AS total_icu_los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` s
    GROUP BY s.hadm_id
),
admission_icu_los AS (
    SELECT
        sa.subject_id,
        sa.hadm_id,
        sa.admittime,
        sa.age_at_admission,
        COALESCE(s.total_icu_los, 0) AS icu_los
    FROM sepsis_admissions sa
    LEFT JOIN icu_stays s
        ON sa.hadm_id = s.hadm_id
)
SELECT
    APPROX_QUANTILES(icu_los, 100)[OFFSET(49)] AS median_icu_los
FROM admission_icu_los;
WITH PatientCohort AS (
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    WHERE
        p.gender = 'F'
        AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age) BETWEEN 69 AND 79
),
GIB_Admissions AS (
    SELECT
        pc.subject_id,
        pc.hadm_id,
        pc.admittime,
        pc.dischtime,
        pc.hospital_expire_flag,
        MAX(CASE
            -- ICD-9 Upper GI Bleed codes
            WHEN di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(53082|531[0-9]1|532[0-9]1|533[0-9]1|534[0-9]1|535[0-9]1|4560|45620|5780)') THEN 1
            -- ICD-10 Upper GI Bleed codes
            WHEN di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(K20[0-9]X1|K220|K228|K229|K25[0-9]|K26[0-9]|K27[0-9]|K28[0-9]|I8501|K920)') THEN 1
            ELSE 0
        END) AS is_ugi_code_present,
        MAX(CASE
            -- ICD-9 Lower GI Bleed codes
            WHEN di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(56211|56213|5693|5570|5781)') THEN 1
            -- ICD-10 Lower GI Bleed codes
            WHEN di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(K57[0-9][2-3]|K625|K921)') THEN 1
            ELSE 0
        END) AS is_lgi_code_present
    FROM PatientCohort pc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON pc.subject_id = di.subject_id AND pc.hadm_id = di.hadm_id
    GROUP BY pc.subject_id, pc.hadm_id, pc.admittime, pc.dischtime, pc.hospital_expire_flag
    -- Filter for admissions with at least one specific UGI or LGI bleeding code
    HAVING (MAX(CASE
            WHEN di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(53082|531[0-9]1|532[0-9]1|533[0-9]1|534[0-9]1|535[0-9]1|4560|45620|5780)') THEN 1
            WHEN di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(K20[0-9]X1|K220|K228|K229|K25[0-9]|K26[0-9]|K27[0-9]|K28[0-9]|I8501|K920)') THEN 1
            ELSE 0
        END) = 1) OR
        (MAX(CASE
            WHEN di.icd_version = 9 AND REGEXP_CONTAINS(di.icd_code, r'^(56211|56213|5693|5570|5781)') THEN 1
            WHEN di.icd_version = 10 AND REGEXP_CONTAINS(di.icd_code, r'^(K57[0-9][2-3]|K625|K921)') THEN 1
            ELSE 0
        END) = 1)
),
GIB_Categorized AS (
    SELECT
        g.subject_id,
        g.hadm_id,
        g.admittime,
        g.dischtime,
        g.hospital_expire_flag,
        -- Prioritize Upper GI Bleed if specific codes for both are present
        CASE
            WHEN g.is_ugi_code_present = 1 THEN 'Upper GI Bleed'
            WHEN g.is_lgi_code_present = 1 THEN 'Lower GI Bleed'
            ELSE 'Undetermined' -- Should not be reached due to HAVING clause in GIB_Admissions
        END AS bleed_type
    FROM GIB_Admissions g
),
ICUStaysInfo AS (
    SELECT
        gc.hadm_id,
        gc.admittime,
        gc.dischtime,
        gc.hospital_expire_flag,
        gc.bleed_type,
        -- Calculate LOS rounded to the nearest integer day
        ROUND(CAST(TIMESTAMP_DIFF(gc.dischtime, gc.admittime, HOUR) AS BIGNUMERIC) / 24.0, 0) AS los_days_rounded,
        -- Determine if there was an ICU admission within the first day (24 hours) of hospital admission
        MAX(CASE
            WHEN icu.stay_id IS NOT NULL AND icu.intime <= DATETIME_ADD(gc.admittime, INTERVAL 1 DAY) THEN 1
            ELSE 0
        END) AS is_day1_icu_admission,
        -- Determine if there was any ICU admission during the entire hospital stay
        MAX(CASE WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS has_any_icu_stay
    FROM GIB_Categorized gc
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON gc.subject_id = icu.subject_id AND gc.hadm_id = icu.hadm_id
    GROUP BY gc.hadm_id, gc.admittime, gc.dischtime, gc.hospital_expire_flag, gc.bleed_type
),
FinalCohort AS (
    SELECT
        isi.hadm_id,
        isi.hospital_expire_flag,
        isi.bleed_type,
        isi.is_day1_icu_admission,
        isi.has_any_icu_stay,
        -- Categorize LOS into specified buckets
        CASE
            WHEN isi.los_days_rounded = 0 THEN '<1 day'
            WHEN isi.los_days_rounded BETWEEN 1 AND 2 THEN '1-2 days'
            WHEN isi.los_days_rounded BETWEEN 3 AND 5 THEN '3-5 days'
            WHEN isi.los_days_rounded BETWEEN 6 AND 9 THEN '6-9 days'
            WHEN isi.los_days_rounded >= 10 THEN '>=10 days'
            ELSE 'Other' -- Catches any unexpected or negative LOS values
        END AS los_category,
        -- Categorize Day-1 ICU status
        CASE
            WHEN isi.is_day1_icu_admission = 1 THEN 'Day-1 ICU'
            ELSE 'No Day-1 ICU'
        END AS day1_icu_status
    FROM ICUStaysInfo isi
)
SELECT
    fc.bleed_type,
    fc.los_category,
    fc.day1_icu_status,
    COUNT(fc.hadm_id) AS total_admissions,
    ROUND(SUM(fc.hospital_expire_flag) * 100.0 / COUNT(fc.hadm_id), 2) AS in_hospital_mortality_percent,
    ROUND(SUM(fc.has_any_icu_stay) * 100.0 / COUNT(fc.hadm_id), 2) AS any_icu_admission_percent
FROM FinalCohort fc
GROUP BY
    fc.bleed_type,
    fc.los_category,
    fc.day1_icu_status
ORDER BY
    fc.bleed_type,
    -- Custom order for LOS categories to ensure logical sorting
    CASE
        WHEN fc.los_category = '<1 day' THEN 0
        WHEN fc.los_category = '1-2 days' THEN 1
        WHEN fc.los_category = '3-5 days' THEN 2
        WHEN fc.los_category = '6-9 days' THEN 3
        WHEN fc.los_category = '>=10 days' THEN 4
        ELSE 99
    END,
    fc.day1_icu_status;
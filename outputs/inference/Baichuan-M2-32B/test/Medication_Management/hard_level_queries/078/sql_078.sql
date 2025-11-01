WITH cohort AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 74 AND 84
        AND a.admission_type = 'INPATIENT'
),
meds_24h AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        p.drug
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON c.subject_id = p.subject_id
        AND c.hadm_id = p.hadm_id
    WHERE p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 24 HOUR
),
med_count AS (
    SELECT
        subject_id,
        hadm_id,
        COALESCE(COUNT(DISTINCT drug), 0) AS med_count
    FROM meds_24h
    GROUP BY subject_id, hadm_id
),
qt_drugs AS (
    SELECT 'Amiodarone' AS drug
    UNION ALL SELECT 'Quinidine'
    UNION ALL SELECT 'Sotalol'
    UNION ALL SELECT 'Dofetilide'
    UNION ALL SELECT 'Ivabradine'
    UNION ALL SELECT 'Moxifloxacin'
    UNION ALL SELECT 'Thioridazine'
),
bleeding_drugs AS (
    SELECT 'Warfarin' AS drug
    UNION ALL SELECT 'Heparin'
    UNION ALL SELECT 'Clopidogrel'
    UNION ALL SELECT 'Aspirin'
    UNION ALL SELECT 'Rivaroxaban'
    UNION ALL SELECT 'Apixaban'
    UNION ALL SELECT 'Dabigatran'
    UNION ALL SELECT 'Edoxaban'
),
meds_flagged AS (
    SELECT
        m.*,
        CASE WHEN EXISTS (SELECT 1 FROM qt_drugs q WHERE q.drug = m.drug) THEN 1 ELSE 0 END AS is_qt,
        CASE WHEN EXISTS (SELECT 1 FROM bleeding_drugs b WHERE b.drug = m.drug) THEN 1 ELSE 0 END AS is_bleeding
    FROM meds_24h m
),
patient_flags AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        MAX(m.is_qt) AS has_qt_drug,
        MAX(m.is_bleeding) AS has_bleeding_drug
    FROM cohort c
    LEFT JOIN meds_flagged m
        ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
    GROUP BY c.subject_id, c.hadm_id
),
icu_flag AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS is_icu
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON c.subject_id = i.subject_id
        AND c.hadm_id = i.hadm_id
),
combined AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        c.los_days,
        c.hospital_expire_flag,
        COALESCE(m.med_count, 0) AS med_count,
        COALESCE(f.has_qt_drug, 0) AS has_qt_drug,
        COALESCE(f.has_bleeding_drug, 0) AS has_bleeding_drug,
        ic.is_icu
    FROM cohort c
    LEFT JOIN med_count m
        ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
    LEFT JOIN patient_flags f
        ON c.subject_id = f.subject_id AND c.hadm_id = f.hadm_id
    LEFT JOIN icu_flag ic
        ON c.subject_id = ic.subject_id AND c.hadm_id = ic.hadm_id
),
los_quartiles AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY los_days) AS los_quartile
    FROM combined
)
-- Overall cohort
SELECT
    'Overall' AS group_name,
    COUNT(*) AS num_patients,
    AVG(med_count) AS mean_med_count,
    MIN(med_count) AS min_med_count,
    MAX(med_count) AS max_med_count,
    STDDEV(med_count) AS std_med_count,
    APPROX_QUANTILES(med_count, 100) [OFFSET(25)] AS p25_med_count,
    APPROX_QUANTILES(med_count, 100) [OFFSET(50)] AS p50_med_count,
    APPROX_QUANTILES(med_count, 100) [OFFSET(75)] AS p75_med_count,
    AVG(has_qt_drug) * 100 AS qt_prevalence_percent,
    AVG(has_bleeding_drug) * 100 AS bleeding_prevalence_percent,
    AVG(hospital_expire_flag) * 100 AS mortality_percent
FROM combined

UNION ALL

-- ICU vs non-ICU
SELECT
    CASE WHEN is_icu = 1 THEN 'ICU' ELSE 'Non-ICU' END AS group_name,
    COUNT(*) AS num_patients,
    AVG(med_count) AS mean_med_count,
    MIN(med_count) AS min_med_count,
    MAX(med_count) AS max_med_count,
    STDDEV(med_count) AS std_med_count,
    APPROX_QUANTILES(med_count, 100) [OFFSET(25)] AS p25_med_count,
    APPROX_QUANTILES(med_count, 100) [OFFSET(50)] AS p50_med_count,
    APPROX_QUANTILES(med_count, 100) [OFFSET(75)] AS p75_med_count,
    AVG(has_qt_drug) * 100 AS qt_prevalence_percent,
    AVG(has_bleeding_drug) * 100 AS bleeding_prevalence_percent,
    AVG(hospital_expire_flag) * 100 AS mortality_percent
FROM combined
GROUP BY group_name

UNION ALL

-- Top-quartile LOS (los_quartile=4)
SELECT
    'Top-Quartile LOS' AS group_name,
    COUNT(*) AS num_patients,
    AVG(med_count) AS mean_med_count,
    MIN(med_count) AS min_med_count,
    MAX(med_count) AS max_med_count,
    STDDEV(med_count) AS std_med_count,
    APPROX_QUANTILES(med_count, 100) [OFFSET(25)] AS p25_med_count,
    APPROX_QUANTILES(med_count, 100) [OFFSET(50)] AS p50_med_count,
    APPROX_QUANTILES(med_count, 100) [OFFSET(75)] AS p75_med_count,
    AVG(has_qt_drug) * 100 AS qt_prevalence_percent,
    AVG(has_bleeding_drug) * 100 AS bleeding_prevalence_percent,
    AVG(hospital_expire_flag) * 100 AS mortality_percent
FROM los_quartiles
WHERE los_quartile = 4;
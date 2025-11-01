WITH stroke_admissions AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    WHERE EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        WHERE adm.hadm_id = diag.hadm_id
        AND (
            (diag.icd_version = 10 AND diag.icd_code LIKE 'I6%') OR  -- I60, I61, I63
            (diag.icd_version = 9 AND (
                (diag.icd_code LIKE '433%' AND diag.icd_code LIKE '%1') OR 
                (diag.icd_code LIKE '434%' AND diag.icd_code LIKE '%1') OR 
                diag.icd_code = '436' OR 
                diag.icd_code LIKE '431%' OR 
                diag.icd_code LIKE '432%'
            ))
        )
    )
    AND p.gender = 'M'
),
first_admission AS (
    SELECT 
        subject_id,
        hadm_id,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank
    FROM stroke_admissions
    WHERE age_at_admission BETWEEN 46 AND 56
),
icu_los_per_admission AS (
    SELECT 
        fa.subject_id,
        fa.hadm_id,
        SUM(icu.los) AS total_icu_los_days
    FROM first_admission fa
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON fa.hadm_id = icu.hadm_id
    WHERE fa.admission_rank = 1
    GROUP BY fa.subject_id, fa.hadm_id
)
SELECT 
    APPROX_QUANTILES(total_icu_los_days, 100)[OFFSET(25)] AS q1,
    APPROX_QUANTILES(total_icu_los_days, 100)[OFFSET(75)] AS q3,
    APPROX_QUANTILES(total_icu_los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(total_icu_los_days, 100)[OFFSET(25)] AS iqr
FROM icu_los_per_admission;
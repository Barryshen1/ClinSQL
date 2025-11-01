WITH base_admissions AS (
    SELECT
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        p.anchor_age,
        p.gender
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 52 AND 62
        AND a.dischtime IS NOT NULL
),
admissions_with_icu AS (
    SELECT
        b.*,
        CASE
            WHEN i.stay_id IS NOT NULL THEN 'ICU'
            ELSE 'Non-ICU'
        END AS icu_status
    FROM base_admissions b
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON b.hadm_id = i.hadm_id
),
admissions_with_diagnoses AS (
    SELECT
        a.*,
        d.icd_code,
        d.icd_version
    FROM admissions_with_icu a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
        AND d.icd_version = 10
),
admissions_with_flags AS (
    SELECT
        hadm_id,
        subject_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        anchor_age,
        gender,
        icu_status,
        DATE_DIFF(dischtime, admittime, DAY) AS los_days,
        -- CKD: ICD-10 codes starting with N18 or N19
        MAX(CASE WHEN icd_code LIKE 'N18%' OR icd_code LIKE 'N19%' THEN 1 ELSE 0 END) AS has_ckd,
        -- Diabetes: ICD-10 codes E10-E14
        MAX(CASE WHEN icd_code BETWEEN 'E10' AND 'E14' THEN 1 ELSE 0 END) AS has_diabetes,
        COUNT(DISTINCT icd_code) AS comorbidity_count
    FROM admissions_with_diagnoses
    GROUP BY
        hadm_id,
        subject_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        anchor_age,
        gender,
        icu_status
),
admissions_with_comorbidity_tertile AS (
    SELECT
        *,
        CASE
            WHEN NTILE(3) OVER (ORDER BY comorbidity_count) = 1 THEN 'Low'
            WHEN NTILE(3) OVER (ORDER BY comorbidity_count) = 2 THEN 'Medium'
            WHEN NTILE(3) OVER (ORDER BY comorbidity_count) = 3 THEN 'High'
        END AS comorbidity_tertile
    FROM admissions_with_flags
),
grouped_data AS (
    SELECT
        icu_status,
        CASE
            WHEN los_days <= 5 THEN '≤5 days'
            ELSE '>5 days'
        END AS los_category,
        comorbidity_tertile,
        AVG(hospital_expire_flag) * 100 AS mortality_rate,
        AVG(has_ckd) * 100 AS ckd_prevalence,
        AVG(has_diabetes) * 100 AS diabetes_prevalence
    FROM admissions_with_comorbidity_tertile
    GROUP BY icu_status, los_category, comorbidity_tertile
)
SELECT
    icu_status,
    los_category,
    comorbidity_tertile,
    ROUND(mortality_rate, 2) AS mortality_rate,
    ROUND(ckd_prevalence, 2) AS ckd_prevalence,
    ROUND(diabetes_prevalence, 2) AS diabetes_prevalence
FROM grouped_data
ORDER BY icu_status, los_category, comorbidity_tertile;
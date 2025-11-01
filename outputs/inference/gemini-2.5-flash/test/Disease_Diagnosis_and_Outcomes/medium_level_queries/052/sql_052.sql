WITH admn_cohort AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        p.gender,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_hospital,
        (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
        CASE
            WHEN EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu WHERE icu.hadm_id = a.hadm_id) THEN 'ICU'
            ELSE 'Non-ICU'
        END AS icu_status,
        CASE
            WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) IS NULL THEN NULL -- Handle cases where dischtime is missing
            WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) <= 5 THEN 'LOS <= 5 Days'
            ELSE 'LOS > 5 Days'
        END AS los_group,
        a.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        -- Filter for age_at_admission in the specific range, calculated from anchor data
        AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 52 AND 62
),
comorbidities AS (
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.gender,
        ac.los_hospital,
        ac.age_at_admission,
        ac.icu_status,
        ac.los_group,
        ac.hospital_expire_flag,
        MAX(CASE
            WHEN (d_icd.icd_version = 9 AND d_icd.icd_code LIKE '250%')
            OR (d_icd.icd_version = 10 AND (d_icd.icd_code LIKE 'E10%' OR d_icd.icd_code LIKE 'E11%' OR d_icd.icd_code LIKE 'E13%'))
            THEN 1 ELSE 0
        END) AS has_diabetes,
        MAX(CASE
            WHEN (d_icd.icd_version = 9 AND d_icd.icd_code LIKE '585%')
            OR (d_icd.icd_version = 10 AND d_icd.icd_code LIKE 'N18%')
            THEN 1 ELSE 0
        END) AS has_ckd,
        MAX(CASE
            WHEN (d_icd.icd_version = 9 AND d_icd.icd_code LIKE '428%')
            OR (d_icd.icd_version = 10 AND d_icd.icd_code LIKE 'I50%')
            THEN 1 ELSE 0
        END) AS has_chf,
        MAX(CASE
            WHEN (d_icd.icd_version = 9 AND d_icd.icd_code BETWEEN '430' AND '438')
            OR (d_icd.icd_version = 10 AND d_icd.icd_code BETWEEN 'I60' AND 'I69')
            THEN 1 ELSE 0
        END) AS has_cerebrovascular,
        MAX(CASE
            WHEN (d_icd.icd_version = 9 AND d_icd.icd_code BETWEEN '490' AND '496')
            OR (d_icd.icd_version = 10 AND d_icd.icd_code BETWEEN 'J40' AND 'J47')
            THEN 1 ELSE 0
        END) AS has_copd,
        MAX(CASE
            -- ICD-9 codes 140-208 for malignant neoplasms, excluding 202.8 (benign/other lymphoid)
            WHEN (d_icd.icd_version = 9 AND d_icd.icd_code BETWEEN '140' AND '208' AND d_icd.icd_code NOT LIKE '202.8%')
            -- ICD-10 codes C00-C97 for malignant neoplasms
            OR (d_icd.icd_version = 10 AND d_icd.icd_code BETWEEN 'C00' AND 'C97')
            THEN 1 ELSE 0
        END) AS has_malignancy
    FROM
        admn_cohort ac
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
        ON ac.subject_id = d_icd.subject_id AND ac.hadm_id = d_icd.hadm_id
    GROUP BY
        ac.subject_id, ac.hadm_id, ac.gender, ac.los_hospital, ac.age_at_admission, ac.icu_status, ac.los_group, ac.hospital_expire_flag
),
comorbidity_score_and_tertile AS (
    SELECT
        *,
        (has_diabetes + has_ckd + has_chf + has_cerebrovascular + has_copd + has_malignancy) AS comorbidity_score,
        NTILE(3) OVER (ORDER BY (has_diabetes + has_ckd + has_chf + has_cerebrovascular + has_copd + has_malignancy)) AS comorbidity_tertile
    FROM
        comorbidities
)
SELECT
    icu_status,
    los_group,
    comorbidity_tertile,
    COUNT(DISTINCT hadm_id) AS num_admissions,
    ROUND(CAST(SUM(hospital_expire_flag) AS BIGNUMERIC) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS in_hospital_mortality_percent,
    ROUND(CAST(SUM(has_ckd) AS BIGNUMERIC) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS ckd_prevalence_percent,
    ROUND(CAST(SUM(has_diabetes) AS BIGNUMERIC) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS diabetes_prevalence_percent
FROM
    comorbidity_score_and_tertile
WHERE
    los_group IS NOT NULL -- Exclude admissions with missing dischtime which result in NULL LOS group
GROUP BY
    icu_status,
    los_group,
    comorbidity_tertile
ORDER BY
    icu_status,
    los_group,
    comorbidity_tertile;
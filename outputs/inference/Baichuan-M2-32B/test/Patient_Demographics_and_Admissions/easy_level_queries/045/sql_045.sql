WITH patients_with_pneumonia AS (
    SELECT
        p.subject_id,
        p.anchor_age,
        p.gender,
        d.hadm_id,
        d.icd_code,
        d.icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON p.subject_id = d.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 51 AND 61
        AND LOWER(dd.long_title) LIKE '%pneumonia%'
),
first_admissions AS (
    SELECT
        subject_id,
        hadm_id,
        admittime
    FROM (
        SELECT
            subject_id,
            hadm_id,
            admittime,
            ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
        FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    ) 
    WHERE rn = 1
),
first_icu_stays AS (
    SELECT
        subject_id,
        hadm_id,
        intime,
        outtime,
        ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS icu_rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE intime IS NOT NULL
        AND outtime IS NOT NULL
),
icu_los AS (
    SELECT
        p.subject_id,
        f.hadm_id,
        TIMESTAMP_DIFF(ficu.outtime, ficu.intime, HOUR) / 24.0 AS los_days
    FROM patients_with_pneumonia p
    INNER JOIN first_admissions f
        ON p.subject_id = f.subject_id
        AND p.hadm_id = f.hadm_id
    INNER JOIN first_icu_stays ficu
        ON f.subject_id = ficu.subject_id
        AND f.hadm_id = ficu.hadm_id
        AND ficu.icu_rn = 1
)
SELECT
    APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los_days
FROM icu_los;
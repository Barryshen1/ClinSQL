WITH eligible_admissions AS (
    SELECT 
        a.hadm_id,
        a.admittime,
        a.dischtime,
        p.subject_id,
        -- Compute birth date: anchor_year as year, anchor_age as age at that time, so birth date is DATE(anchor_year, 1, 1) + INTERVAL anchor_age YEAR
        DATE(p.anchor_year, 1, 1) + INTERVAL p.anchor_age YEAR AS birth_date
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        AND a.dischtime IS NOT NULL
),
with_age AS (
    SELECT 
        hadm_id,
        admittime,
        dischtime,
        -- Compute age at admission: floor of days difference divided by 365.25
        FLOOR(DATE_DIFF(admittime, birth_date, DAY) / 365.25) AS age
    FROM eligible_admissions
),
with_diagnoses AS (
    SELECT 
        wa.hadm_id,
        wa.admittime,
        wa.dischtime,
        wa.age,
        DATE_DIFF(wa.dischtime, wa.admittime, DAY) AS los_days
    FROM with_age wa
    WHERE wa.age BETWEEN 77 AND 87
    AND EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
            ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
        WHERE di.hadm_id = wa.hadm_id 
            AND dd.long_title LIKE '%heart failure%'
    )
    AND EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
            ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
        WHERE di.hadm_id = wa.hadm_id 
            AND dd.long_title LIKE '%chronic obstructive pulmonary disease%'
    )
)
SELECT STDDEV_SAMP(los_days) AS sd_los
FROM with_diagnoses;
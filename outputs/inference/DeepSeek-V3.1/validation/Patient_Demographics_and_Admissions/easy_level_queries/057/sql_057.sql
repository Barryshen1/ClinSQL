WITH first_admissions AS (
    SELECT 
        p.subject_id,
        p.gender,
        p.anchor_age,
        a.hadm_id,
        a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 46 AND 56
    QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),
stroke_codes AS (
    SELECT 
        hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE 
        (dd.icd_version = 9 AND dd.long_title LIKE '%stroke%' AND di.icd_code LIKE '43[3-4]%' AND di.icd_code LIKE '%1')
        OR (dd.icd_version = 10 AND dd.long_title LIKE '%stroke%' AND di.icd_code LIKE 'I63%')
),
first_icu_stay AS (
    SELECT 
        fa.subject_id,
        fa.hadm_id,
        i.stay_id,
        i.los
    FROM first_admissions fa
    INNER JOIN stroke_codes sc
        ON fa.hadm_id = sc.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON fa.hadm_id = i.hadm_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY fa.subject_id ORDER BY i.intime) = 1
)
SELECT 
    APPROX_QUANTILES(los, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(los, 4)[OFFSET(3)] AS q3,
    APPROX_QUANTILES(los, 4)[OFFSET(3)] - APPROX_QUANTILES(los, 4)[OFFSET(1)] AS iqr
FROM first_icu_stay;
WITH akifemales AS (
    SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 82 AND 92
        AND dd.long_title LIKE 'Acute kidney injury%'
),
first_icu_stay AS (
    SELECT 
        i.hadm_id,
        i.los,
        ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS stay_seq
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN akifemales af ON i.hadm_id = af.hadm_id
)
SELECT 
    APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_25th_percentile
FROM first_icu_stay
WHERE stay_seq = 1;
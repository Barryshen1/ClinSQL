WITH first_admission AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
pneumonia_patients AS (
    SELECT DISTINCT d.subject_id, d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
        ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
    WHERE 
        (d.icd_version = 9 AND d.icd_code LIKE '480%' OR d.icd_code = '481' OR d.icd_code LIKE '482%' 
         OR d.icd_code LIKE '483%' OR d.icd_code = '485' OR d.icd_code = '486')
        OR
        (d.icd_version = 10 AND (d.icd_code LIKE 'J12%' OR d.icd_code = 'J13' OR d.icd_code = 'J14' 
         OR d.icd_code LIKE 'J15%' OR d.icd_code LIKE 'J16%' OR d.icd_code LIKE 'J18%'))
),
first_icu_stay AS (
    SELECT 
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.los,
        ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS stay_rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
)
SELECT 
    APPROX_QUANTILES(icu.los, 100)[OFFSET(25)] AS percentile_25
FROM first_admission fa
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON fa.subject_id = p.subject_id
JOIN pneumonia_patients pp 
    ON fa.hadm_id = pp.hadm_id
JOIN first_icu_stay icu 
    ON fa.hadm_id = icu.hadm_id AND icu.stay_rn = 1
WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND fa.rn = 1;
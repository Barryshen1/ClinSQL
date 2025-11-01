WITH pneumonia_admissions AS (
    SELECT d_icd.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd 
        ON p.subject_id = d_icd.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
        ON d_icd.icd_code = d.icd_code AND d_icd.icd_version = d.icd_version
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 51 AND 61
        AND LOWER(d.long_title) LIKE '%pneumonia%'
),
first_icu_stays AS (
    SELECT i.hadm_id, i.intime, i.outtime,
           ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    WHERE i.hadm_id IN (SELECT hadm_id FROM pneumonia_admissions)
)
SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los_days) AS percentile_25
FROM (
    SELECT TIMESTAMP_DIFF(outtime, intime, DAY) AS los_days
    FROM first_icu_stays
    WHERE rn = 1
) AS los_data;
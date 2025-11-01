WITH target_admissions AS (
    SELECT 
        a.subject_id, 
        a.hadm_id, 
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 75 AND 85
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
            WHERE 
                di.subject_id = a.subject_id 
                AND di.hadm_id = a.hadm_id 
                AND (
                    (di.icd_version = 10 AND di.icd_code LIKE 'I2[0-5]%') 
                    OR (di.icd_version = 9 AND di.icd_code LIKE '41[0-4]%')
                )
        )
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
            WHERE 
                di.subject_id = a.subject_id 
                AND di.hadm_id = a.hadm_id 
                AND (
                    (di.icd_version = 10 AND di.icd_code LIKE 'J4[3-4]%') 
                    OR (di.icd_version = 9 AND di.icd_code LIKE '49[0-2]%' OR di.icd_code LIKE '49[4-6]%')
                )
        )
)
SELECT 
    PERCENTILE_CONT(los_days, 0.75) OVER() AS los_75th_percentile
FROM target_admissions
LIMIT 1;
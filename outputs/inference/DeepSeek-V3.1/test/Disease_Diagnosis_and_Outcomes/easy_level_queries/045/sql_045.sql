WITH target_admissions AS (
    SELECT a.subject_id, a.hadm_id, 
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 77 AND 87
        AND a.dischtime IS NOT NULL  -- Ensure LOS is calculable
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
                ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
            WHERE di.hadm_id = a.hadm_id
                AND (
                    (dd.icd_version = 10 AND dd.icd_code LIKE 'I50%') OR
                    (dd.icd_version = 9 AND dd.icd_code LIKE '428%')
                )
        )
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
                ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
            WHERE di.hadm_id = a.hadm_id
                AND (
                    (dd.icd_version = 10 AND dd.icd_code LIKE 'J44%') OR
                    (dd.icd_version = 9 AND (
                        dd.icd_code LIKE '491%' OR 
                        dd.icd_code LIKE '492%' OR 
                        dd.icd_code LIKE '496%'
                    ))
                )
        )
)
SELECT 
    COUNT(*) AS n_admissions,
    AVG(los_days) AS avg_los,
    STDDEV(los_days) AS sd_los
FROM target_admissions;
WITH base_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
      AND anchor_age BETWEEN 37 AND 47
),
first_admission AS (
    SELECT 
        a.subject_id, 
        a.hadm_id, 
        a.hospital_expire_flag AS mortality
    FROM (
        SELECT 
            subject_id, 
            hadm_id, 
            hospital_expire_flag,
            ROW_NUMBER() OVER (
                PARTITION BY subject_id 
                ORDER BY admittime
            ) AS admission_order
        FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    ) a
    INNER JOIN base_patients bp 
        ON a.subject_id = bp.subject_id
    WHERE a.admission_order = 1
),
dapt_admissions AS (
    SELECT 
        hadm_id,
        COUNT(DISTINCT
            CASE
                WHEN LOWER(drug) LIKE '%aspirin%' 
                    OR LOWER(drug) LIKE '%acetylsalicylic%' 
                    OR LOWER(drug) LIKE '%asa%' THEN 'aspirin'
                WHEN LOWER(drug) LIKE '%clopidogrel%' THEN 'clopidogrel'
                WHEN LOWER(drug) LIKE '%ticagrelor%' THEN 'ticagrelor'
                WHEN LOWER(drug) LIKE '%prasugrel%' THEN 'prasugrel'
            END
        ) AS antiplatelet_count
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE hadm_id IN (SELECT hadm_id FROM first_admission)
    GROUP BY hadm_id
    HAVING antiplatelet_count >= 2
)
SELECT 
    STDDEV_POP(fa.mortality) AS mortality_sd
FROM first_admission fa
INNER JOIN dapt_admissions da 
    ON fa.hadm_id = da.hadm_id;
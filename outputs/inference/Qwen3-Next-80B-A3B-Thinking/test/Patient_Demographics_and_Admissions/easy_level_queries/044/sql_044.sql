WITH first_admissions AS (
    SELECT 
        subject_id,
        hospital_expire_flag,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
)
SELECT 
    PERCENTILE_CONT(hospital_expire_flag, 0.25) AS percentile_25
FROM (
    SELECT 
        fa.hospital_expire_flag
    FROM first_admissions fa
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON fa.subject_id = p.subject_id
    WHERE fa.rn = 1
        AND p.gender = 'M'
        AND p.anchor_age BETWEEN 73 AND 83
) AS filtered_patients;
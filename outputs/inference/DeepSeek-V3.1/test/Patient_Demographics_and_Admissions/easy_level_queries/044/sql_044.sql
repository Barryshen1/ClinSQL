WITH first_admission AS (
    SELECT 
        subject_id,
        MIN(admittime) AS first_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY subject_id
),
first_admission_details AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN first_admission fa
        ON adm.subject_id = fa.subject_id 
        AND adm.admittime = fa.first_admittime
)
SELECT 
    ROUND(100.0 * SUM(fad.hospital_expire_flag) / COUNT(*), 2) AS mortality_rate_percent
FROM first_admission_details fad
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fad.subject_id = p.subject_id
WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83;
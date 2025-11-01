WITH first_admissions AS (
    SELECT subject_id, hadm_id, hospital_expire_flag
    FROM (
        SELECT subject_id, hadm_id, hospital_expire_flag,
               ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
        FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    ) ranked
    WHERE rn = 1
)
SELECT 
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS num_deaths,
    COUNT(*) AS total_patients,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS mortality_rate
FROM first_admissions fa
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON fa.subject_id = p.subject_id
WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 35 AND 45
    AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
            ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
        WHERE pi.hadm_id = fa.hadm_id
          AND (LOWER(dip.long_title) LIKE '%cabg%' 
               OR LOWER(dip.long_title) LIKE '%coronary artery bypass%')
    );
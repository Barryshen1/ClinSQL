WITH first_admissions AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.hospital_expire_flag,
        p.anchor_year,
        p.anchor_age,
        (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
        ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 35 AND 45
),
cabg_patients AS (
    SELECT DISTINCT
        fa.subject_id,
        fa.hadm_id,
        fa.hospital_expire_flag
    FROM first_admissions fa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi 
        ON fa.subject_id = pi.subject_id AND fa.hadm_id = pi.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
        ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
    WHERE dip.icd_code LIKE '36.1%' 
      AND dip.icd_version = 9
      AND fa.rn = 1
)
SELECT 
    COUNT(*) AS total_patients,
    SUM(CAST(hospital_expire_flag AS INT)) AS deaths,
    (SUM(CAST(hospital_expire_flag AS INT)) * 100.0 / COUNT(*)) AS mortality_rate
FROM cabg_patients;
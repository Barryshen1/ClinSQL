WITH hf_admissions AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
    WHERE 
        (d.icd_version = 9 AND d.icd_code LIKE '428%') OR 
        (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
),
first_hf AS (
    SELECT 
        h.subject_id,
        h.hadm_id,
        h.admittime,
        h.dischtime,
        h.hospital_expire_flag,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        p.anchor_age + (EXTRACT(YEAR FROM h.admittime) - p.anchor_year) AS age_at_admittime
    FROM hf_admissions h
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON h.subject_id = p.subject_id
    WHERE h.rn = 1 
        AND p.gender = 'F' 
        AND h.hospital_expire_flag = 0
),
filtered_first_hf AS (
    SELECT *
    FROM first_hf
    WHERE age_at_admittime BETWEEN 38 AND 48
)
SELECT 
    AVG(CASE WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = f.subject_id
            AND a2.hadm_id != f.hadm_id
            AND a2.admittime >= f.dischtime
            AND a2.admittime <= f.dischtime + INTERVAL 30 DAY
    ) THEN 1 ELSE 0 END) AS readmission_rate
FROM filtered_first_hf f;
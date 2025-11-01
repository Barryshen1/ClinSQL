WITH hf_patients AS (
    SELECT 
        p.subject_id, 
        p.gender,
        p.anchor_age,
        p.anchor_year,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE 
        p.gender = 'F'
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE 
                di.hadm_id = a.hadm_id
                AND (
                    (di.icd_version = 9 AND di.icd_code LIKE '428%') 
                    OR 
                    (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
                )
        )
),
first_hf AS (
    SELECT 
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        anchor_age,
        anchor_year,
        anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
    FROM hf_patients
    QUALIFY ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) = 1
),
index_admissions AS (
    SELECT *
    FROM first_hf
    WHERE 
        age_at_admission BETWEEN 38 AND 48
        AND hospital_expire_flag = 0
),
readmissions AS (
    SELECT 
        i.subject_id,
        i.hadm_id,
        i.dischtime,
        MAX(CASE 
            WHEN r.hadm_id IS NOT NULL THEN 1 
            ELSE 0 
        END) AS readmitted_30d
    FROM index_admissions i
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` r
        ON i.subject_id = r.subject_id
        AND r.admittime > i.dischtime
        AND r.admittime <= DATE_ADD(i.dischtime, INTERVAL 30 DAY)
    GROUP BY i.subject_id, i.hadm_id, i.dischtime
)
SELECT 
    AVG(readmitted_30d) AS avg_30d_readmission_rate
FROM readmissions;
WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime,
        p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 52 AND 62
        AND d.long_title LIKE 'Acute kidney injury%'
        AND adm.hospital_expire_flag = 0  -- Exclude in-hospital deaths
),
readmission_flag AS (
    SELECT 
        c1.hadm_id AS index_admission,
        MAX(CASE 
            WHEN c2.hadm_id IS NOT NULL AND 
                 DATE_DIFF(c2.admittime, c1.dischtime, DAY) BETWEEN 1 AND 30 
            THEN 1 
            ELSE 0 
        END) AS had_readmission
    FROM cohort c1
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` c2
        ON c1.subject_id = c2.subject_id
        AND c2.admittime > c1.dischtime  -- Subsequent admission
    GROUP BY c1.hadm_id
)
SELECT STDDEV(had_readmission) AS sd_30day_readmission
FROM readmission_flag;
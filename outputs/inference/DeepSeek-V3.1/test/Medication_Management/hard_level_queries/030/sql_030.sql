WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        a.hadm_id, 
        a.admittime, 
        a.dischtime, 
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 71 AND 81
        AND (
            (di.icd_version = 9 AND di.icd_code = '5770') OR
            (di.icd_version = 10 AND di.icd_code LIKE 'K85%')
        )
),
meds_count AS (
    SELECT 
        c.hadm_id,
        COUNT(DISTINCT pr.drug) AS num_meds
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON c.hadm_id = pr.hadm_id
    WHERE 
        pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    GROUP BY c.hadm_id
),
tertiles AS (
    SELECT 
        hadm_id,
        num_meds,
        NTILE(3) OVER (ORDER BY num_meds) AS tertile
    FROM meds_count
),
readmission_data AS (
    SELECT 
        c1.hadm_id,
        c1.subject_id,
        c1.dischtime,
        c1.hospital_expire_flag,
        MIN(CASE WHEN c2.admittime > c1.dischtime THEN c2.admittime END) AS next_admittime
    FROM cohort c1
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` c2
        ON c1.subject_id = c2.subject_id
        AND c2.admittime > c1.dischtime
    GROUP BY c1.hadm_id, c1.subject_id, c1.dischtime, c1.hospital_expire_flag
)
SELECT 
    t.tertile,
    COUNT(*) AS n_admissions,
    AVG(DATETIME_DIFF(c.dischtime, c.admittime, DAY)) AS avg_los,
    AVG(c.hospital_expire_flag) AS mortality_rate,
    AVG(CASE 
        WHEN c.hospital_expire_flag = 1 THEN 0  -- Exclude patients who died in hospital
        WHEN DATE_DIFF(DATE(rd.next_admittime), DATE(c.dischtime), DAY) <= 30 THEN 1
        ELSE 0 
    END) AS readmission_rate
FROM cohort c
INNER JOIN tertiles t ON c.hadm_id = t.hadm_id
INNER JOIN readmission_data rd ON c.hadm_id = rd.hadm_id
GROUP BY t.tertile
ORDER BY t.tertile;
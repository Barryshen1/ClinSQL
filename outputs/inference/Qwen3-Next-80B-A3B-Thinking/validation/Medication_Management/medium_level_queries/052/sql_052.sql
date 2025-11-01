WITH cohort AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 45 AND 55
        AND a.dischtime >= a.admittime + INTERVAL 48 HOUR
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
                ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
            WHERE d.hadm_id = a.hadm_id
                AND (LOWER(di.long_title) LIKE '%diabetes mellitus type 2%' OR d.icd_code LIKE 'E11%')
        )
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
                ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
            WHERE d.hadm_id = a.hadm_id
                AND (LOWER(di.long_title) LIKE '%heart failure%' OR d.icd_code LIKE 'I50%')
        )
)
SELECT
    AVG(has_insulin_first48) * 100 AS first48_insulin_pct,
    AVG(has_oral_first48) * 100 AS first48_oral_pct,
    AVG(has_insulin_final24) * 100 AS final24_insulin_pct,
    AVG(has_oral_final24) * 100 AS final24_oral_pct
FROM (
    SELECT
        c.subject_id,
        c.hadm_id,
        MAX(CASE WHEN p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 48 HOUR AND p.drug_type = 'insulin' THEN 1 ELSE 0 END) AS has_insulin_first48,
        MAX(CASE WHEN p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 48 HOUR AND p.drug_type = 'oral' THEN 1 ELSE 0 END) AS has_oral_first48,
        MAX(CASE WHEN p.starttime BETWEEN c.dischtime - INTERVAL 24 HOUR AND c.dischtime AND p.drug_type = 'insulin' THEN 1 ELSE 0 END) AS has_insulin_final24,
        MAX(CASE WHEN p.starttime BETWEEN c.dischtime - INTERVAL 24 HOUR AND c.dischtime AND p.drug_type = 'oral' THEN 1 ELSE 0 END) AS has_oral_final24
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON c.hadm_id = p.hadm_id
    GROUP BY c.subject_id, c.hadm_id
) sub;
WITH cohort AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        p.anchor_age,
        p.anchor_year
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 43 AND 53
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
                ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
            WHERE d.hadm_id = a.hadm_id
                AND (LOWER(di.long_title) LIKE '%transplant%' OR LOWER(di.long_title) LIKE '%graft%')
        )
),
medication_score AS (
    SELECT 
        c.hadm_id,
        COUNT(DISTINCT pr.drug) AS medication_count
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
        ON c.hadm_id = pr.hadm_id
        AND pr.starttime >= c.admittime
        AND pr.starttime < c.admittime + INTERVAL 7 DAY
    GROUP BY c.hadm_id
),
los_mortality AS (
    SELECT 
        c.hadm_id,
        DATE_DIFF(c.dischtime, c.admittime, DAY) AS los,
        c.hospital_expire_flag,
        CASE WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
            WHERE a2.subject_id = c.subject_id
                AND a2.admittime > c.dischtime
                AND a2.admittime <= c.dischtime + INTERVAL 30 DAY
        ) THEN 1 ELSE 0 END AS readmission_30d
    FROM cohort c
),
combined AS (
    SELECT 
        m.hadm_id,
        m.medication_count,
        l.los,
        l.hospital_expire_flag,
        l.readmission_30d
    FROM medication_score m
    JOIN los_mortality l 
        ON m.hadm_id = l.hadm_id
),
quartiles AS (
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY medication_count) AS quartile
    FROM combined
)
SELECT 
    quartile,
    COUNT(*) AS n,
    AVG(medication_count) AS mean_score,
    AVG(los) AS mean_los,
    AVG(hospital_expire_flag) AS in_hospital_mortality,
    AVG(readmission_30d) AS thirty_day_readmission
FROM quartiles
GROUP BY quartile
ORDER BY quartile;
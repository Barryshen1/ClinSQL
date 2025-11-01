WITH first_icu_stay AS (
    SELECT 
        subject_id, 
        hadm_id, 
        stay_id, 
        intime, 
        outtime, 
        los
    FROM (
        SELECT 
            *,
            ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
        FROM `physionet-data.mimiciv_3_1_icu.icustays`
    ) 
    WHERE rn = 1
),
cohort AS (
    SELECT *
    FROM (
        SELECT 
            p.subject_id,
            p.gender,
            i.hadm_id,
            i.intime,
            i.outtime,
            i.los,
            a.hospital_expire_flag,
            TIMESTAMP_DIFF(i.intime, 
                           DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), 
                           INTERVAL p.anchor_age YEAR), 
                           YEAR) AS age_at_icu
        FROM first_icu_stay i
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
            ON i.subject_id = p.subject_id
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
            ON i.hadm_id = a.hadm_id
        WHERE 
            p.gender = 'M'
            AND p.anchor_year IS NOT NULL
            AND p.anchor_age IS NOT NULL
    )
    WHERE age_at_icu BETWEEN 90 AND 100
),
hepatic_failure AS (
    SELECT 
        c.*
    FROM cohort c
    WHERE EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
            ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
        WHERE 
            d.hadm_id = c.hadm_id
            AND LOWER(dd.long_title) LIKE '%hepatic failure%'
    )
),
procedures_count AS (
    SELECT 
        hf.subject_id,
        hf.hadm_id,
        hf.hospital_expire_flag,
        hf.los,
        COUNT(DISTINCT pr.icd_code) AS num_procedures
    FROM hepatic_failure hf
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr 
        ON hf.subject_id = pr.subject_id 
        AND hf.hadm_id = pr.hadm_id
        AND pr.chartdate BETWEEN DATE(hf.intime) 
            AND DATE(TIMESTAMP_ADD(hf.intime, INTERVAL 72 HOUR))
    GROUP BY 
        hf.subject_id, 
        hf.hadm_id, 
        hf.hospital_expire_flag, 
        hf.los
),
quartiles AS (
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY num_procedures) AS quartile
    FROM procedures_count
)
SELECT 
    quartile,
    COUNT(*) AS num_patients,
    MIN(num_procedures) AS min_procedures,
    MAX(num_procedures) AS max_procedures,
    AVG(num_procedures) AS mean_procedures,
    AVG(los / 24.0) AS mean_los_days,
    (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0) / COUNT(*) AS mortality_percent
FROM quartiles
GROUP BY quartile
ORDER BY quartile;
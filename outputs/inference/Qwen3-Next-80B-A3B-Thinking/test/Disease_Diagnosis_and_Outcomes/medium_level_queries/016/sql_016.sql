WITH cohort AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        CASE WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_icu.icustays` i
            WHERE i.hadm_id = a.hadm_id
                AND i.intime >= a.admittime
                AND i.intime <= a.admittime + INTERVAL 24 HOUR
        ) THEN 1 ELSE 0 END AS icu_day1
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 40 AND 50
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
                ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
            WHERE d.hadm_id = a.hadm_id
                AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
        )
        AND NOT EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
                ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
            WHERE d.hadm_id = a.hadm_id
                AND (di.long_title LIKE '%shock%' OR di.long_title LIKE '%respiratory failure%')
        )
)
SELECT
    CASE WHEN los_days <= 5 THEN '≤5' ELSE '>5' END AS los_category,
    icu_day1,
    AVG(hospital_expire_flag) * 100 AS mortality_rate,
    PERCENTILE_CONT(los_days, 0.5) WITHIN GROUP (ORDER BY los_days) AS median_los
FROM cohort
GROUP BY los_category, icu_day1;
WITH base_icu AS (
    SELECT
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.los,
        -- Compute age at admission using anchor_year and anchor_age
        DATE_DIFF(
            a.admittime,
            DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), 
                     INTERVAL p.anchor_age YEAR),
            YEAR
        ) AS age_at_admission,
        p.gender,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND DATE_DIFF(
            a.admittime,
            DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), 
                     INTERVAL p.anchor_age YEAR),
            YEAR
        ) BETWEEN 88 AND 98
),
copd_patients AS (
    SELECT DISTINCT
        d.subject_id,
        d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE d.icd_version = 10
      AND (dd.icd_code LIKE 'J44%' OR dd.icd_code = 'R06.02')
),
procedures_72h AS (
    SELECT
        p.subject_id,
        p.hadm_id,
        COUNT(DISTINCT p.icd_code) AS distinct_procedures
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN base_icu b
        ON p.subject_id = b.subject_id AND p.hadm_id = b.hadm_id
    WHERE p.chartdate BETWEEN DATE(b.intime) 
                          AND DATE(TIMESTAMP_ADD(b.intime, INTERVAL 72 HOUR))
    GROUP BY p.subject_id, p.hadm_id
),
all_icu_with_procedures AS (
    SELECT
        b.*,
        COALESCE(pr.distinct_procedures, 0) AS distinct_procedures,
        CASE WHEN cp.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_copd_exacerbation
    FROM base_icu b
    LEFT JOIN procedures_72h pr
        ON b.subject_id = pr.subject_id AND b.hadm_id = pr.hadm_id
    LEFT JOIN copd_patients cp
        ON b.subject_id = cp.subject_id AND b.hadm_id = cp.hadm_id
),
group_a AS (
    SELECT
        distinct_procedures,
        los,
        hospital_expire_flag
    FROM all_icu_with_procedures
    WHERE has_copd_exacerbation = 1
),
group_b AS (
    SELECT
        distinct_procedures,
        los,
        hospital_expire_flag
    FROM all_icu_with_procedures
    WHERE has_copd_exacerbation = 0
)
SELECT
    'COPD Exacerbation' AS group_name,
    APPROX_QUANTILES(distinct_procedures, 100)[OFFSET(75)] AS p75_distinct_procedures,
    AVG(los) AS mean_los,
    AVG(hospital_expire_flag) AS mean_mortality
FROM group_a
UNION ALL
SELECT
    'Age-Matched' AS group_name,
    NULL AS p75_distinct_procedures,
    AVG(los) AS mean_los,
    AVG(hospital_expire_flag) AS mean_mortality
FROM group_b;
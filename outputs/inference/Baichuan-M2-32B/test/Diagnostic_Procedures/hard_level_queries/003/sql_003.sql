WITH ards_icu_stays AS (
    SELECT 
        i.stay_id,
        i.hadm_id,
        i.intime,
        p.subject_id,
        p.gender,
        p.anchor_age,
        a.dischtime,
        a.admittime,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON i.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON i.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON i.hadm_id = d.hadm_id
        AND d.icd_code IN ('J80.1', 'J80.10', 'J80.11', 'J80.12', 'J80.13', 'J80.14', 'J80.15', 'J80.16', 'J80.17', 'J80.18', 'J80.19')
        AND d.icd_version = 10
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 84 AND 94
),
general_icu_stays AS (
    SELECT 
        i.stay_id,
        i.hadm_id,
        i.intime,
        p.subject_id,
        p.gender,
        p.anchor_age,
        a.dischtime,
        a.admittime,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON i.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON i.hadm_id = a.hadm_id
),
ards_with_procedures AS (
    SELECT 
        s.*,
        COUNT(DISTINCT pr.icd_code) AS diagnostic_intensity
    FROM ards_icu_stays s
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr 
        ON s.hadm_id = pr.hadm_id
        AND pr.chartdate BETWEEN DATE(s.intime) AND DATE(s.intime) + 1
    GROUP BY s.stay_id, s.hadm_id, s.intime, s.subject_id, s.gender, s.anchor_age, s.dischtime, s.admittime, s.hospital_expire_flag
),
general_with_procedures AS (
    SELECT 
        s.*,
        COUNT(DISTINCT pr.icd_code) AS diagnostic_intensity
    FROM general_icu_stays s
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr 
        ON s.hadm_id = pr.hadm_id
        AND pr.chartdate BETWEEN DATE(s.intime) AND DATE(s.intime) + 1
    GROUP BY s.stay_id, s.hadm_id, s.intime, s.subject_id, s.gender, s.anchor_age, s.dischtime, s.admittime, s.hospital_expire_flag
),
ards_metrics AS (
    SELECT 
        'ARDS' AS group_type,
        diagnostic_intensity,
        TIMESTAMP_DIFF(dischtime, admittime, DAY) AS hospital_los,
        hospital_expire_flag AS mortality
    FROM ards_with_procedures
),
general_metrics AS (
    SELECT 
        'General ICU' AS group_type,
        diagnostic_intensity,
        TIMESTAMP_DIFF(dischtime, admittime, DAY) AS hospital_los,
        hospital_expire_flag AS mortality
    FROM general_with_procedures
),
all_metrics AS (
    SELECT * FROM ards_metrics
    UNION ALL
    SELECT * FROM general_metrics
)
SELECT 
    group_type,
    APPROX_QUANTILES(diagnostic_intensity, 100)[OFFSET(25)] AS p25_diagnostic_intensity,
    APPROX_QUANTILES(diagnostic_intensity, 100)[OFFSET(75)] AS p75_diagnostic_intensity,
    APPROX_QUANTILES(diagnostic_intensity, 100)[OFFSET(95)] AS p95_diagnostic_intensity,
    AVG(hospital_los) AS avg_los,
    AVG(mortality) AS mortality_rate
FROM all_metrics
GROUP BY group_type;
WITH eligible_admissions AS (
    SELECT
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        p.anchor_age,
        p.gender,
        LEAD(a.admittime) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 67 AND 77
        AND d.icd_code IN ('I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9')
        AND d.icd_version = 10
),
medication_scores AS (
    SELECT
        e.hadm_id,
        COUNT(DISTINCT pr.drug) AS complexity_score
    FROM eligible_admissions e
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON e.subject_id = pr.subject_id AND e.hadm_id = pr.hadm_id
        AND pr.starttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 24 HOUR)
    GROUP BY e.hadm_id
),
admissions_with_tertiles AS (
    SELECT
        e.hadm_id,
        e.subject_id,
        e.admittime,
        e.dischtime,
        e.hospital_expire_flag,
        e.next_admittime,
        COALESCE(ms.complexity_score, 0) AS complexity_score,
        NTILE(3) OVER (ORDER BY COALESCE(ms.complexity_score, 0)) AS tertile
    FROM eligible_admissions e
    LEFT JOIN medication_scores ms
        ON e.hadm_id = ms.hadm_id
),
final_data AS (
    SELECT
        tertile,
        COUNT(*) AS admission_count,
        MIN(complexity_score) AS score_min,
        MAX(complexity_score) AS score_max,
        AVG(complexity_score) AS score_mean,
        AVG(DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY)) AS mean_los_days,
        AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality,
        AVG(CASE WHEN next_admittime BETWEEN dischtime AND TIMESTAMP_ADD(dischtime, INTERVAL 30 DAY) 
                 THEN 1.0 ELSE 0.0 END) AS readmission_rate
    FROM admissions_with_tertiles
    GROUP BY tertile
)
SELECT
    tertile,
    admission_count,
    score_min,
    score_max,
    ROUND(score_mean, 2) AS score_mean,
    ROUND(mean_los_days, 2) AS mean_los_days,
    ROUND(in_hospital_mortality * 100, 2) AS in_hospital_mortality_percent,
    ROUND(readmission_rate * 100, 2) AS readmission_rate_percent
FROM final_data
ORDER BY tertile;
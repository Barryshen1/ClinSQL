WITH eligible_admissions AS (
    SELECT
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 43 AND 53
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE
                d.subject_id = a.subject_id
                AND d.hadm_id = a.hadm_id
                AND d.icd_code IN ('K70', 'K71', 'K72', 'K76.0')
                AND d.icd_version = 10
        )
),
medication_complexity AS (
    SELECT
        e.hadm_id,
        COUNT(DISTINCT pr.drug) AS complexity_score
    FROM eligible_admissions e
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON e.subject_id = pr.subject_id
        AND e.hadm_id = pr.hadm_id
        AND pr.starttime BETWEEN e.admittime AND e.admittime + INTERVAL 72 HOUR
    GROUP BY e.hadm_id
),
readmission_flags AS (
    SELECT
        a.hadm_id,
        a.subject_id,
        a.dischtime,
        CASE WHEN next_adm.admittime IS NOT NULL
            AND next_adm.admittime <= a.dischtime + INTERVAL 30 DAY
            THEN 1 ELSE 0 END AS readmitted_30d
    FROM eligible_admissions a
    LEFT JOIN (
        SELECT
            subject_id,
            hadm_id,
            admittime,
            LAG(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS prev_admittime
        FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    ) next_adm
        ON a.subject_id = next_adm.subject_id
        AND next_adm.prev_admittime = a.admittime
),
combined_data AS (
    SELECT
        e.hadm_id,
        e.subject_id,
        e.age_at_admission,
        e.admittime,
        e.dischtime,
        e.hospital_expire_flag,
        m.complexity_score,
        r.readmitted_30d,
        TIMESTAMP_DIFF(e.dischtime, e.admittime, DAY) AS los
    FROM eligible_admissions e
    INNER JOIN medication_complexity m
        ON e.hadm_id = m.hadm_id
    INNER JOIN readmission_flags r
        ON e.hadm_id = r.hadm_id
),
quintiles AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY complexity_score) AS quintile
    FROM combined_data
)
SELECT
    quintile,
    COUNT(*) AS n,
    MIN(complexity_score) AS min_score,
    MAX(complexity_score) AS max_score,
    AVG(complexity_score) AS mean_score,
    AVG(los) AS mean_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality,
    AVG(CAST(readmitted_30d AS FLOAT64)) * 100 AS readmission_30d
FROM quintiles
GROUP BY quintile
ORDER BY quintile;
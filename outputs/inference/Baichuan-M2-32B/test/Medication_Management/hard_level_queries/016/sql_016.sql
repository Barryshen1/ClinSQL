WITH all_admissions_per_patient AS (
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
),
eligible_admissions AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 80 AND 90
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
                ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
            WHERE
                d.subject_id = a.subject_id
                AND d.hadm_id = a.hadm_id
                AND d.icd_version = 10
                AND (dd.icd_code LIKE 'K70%' OR dd.icd_code LIKE 'K71.8%')
        )
),
medication_complexity AS (
    SELECT
        e.hadm_id,
        COUNT(DISTINCT p.formulary_drug_cd) AS complexity_score
    FROM
        eligible_admissions e
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON e.subject_id = p.subject_id
        AND e.hadm_id = p.hadm_id
        AND p.starttime BETWEEN e.admittime AND e.admittime + INTERVAL 7 DAY
    GROUP BY
        e.hadm_id
),
admission_outcomes AS (
    SELECT
        e.hadm_id,
        e.subject_id,
        e.admittime,
        e.dischtime,
        e.hospital_expire_flag,
        DATE_DIFF(e.dischtime, e.admittime, DAY) AS los_days,
        CASE
            WHEN a.next_admittime IS NOT NULL
                AND a.next_admittime <= e.dischtime + INTERVAL 30 DAY
            THEN 1
            ELSE 0
        END AS readmission_30d
    FROM
        eligible_admissions e
    LEFT JOIN
        all_admissions_per_patient a
        ON e.subject_id = a.subject_id
        AND e.hadm_id = a.hadm_id
),
combined_data AS (
    SELECT
        o.hadm_id,
        o.subject_id,
        o.los_days,
        o.hospital_expire_flag,
        o.readmission_30d,
        m.complexity_score,
        NTILE(3) OVER (ORDER BY m.complexity_score) AS tertile
    FROM
        admission_outcomes o
    LEFT JOIN
        medication_complexity m
        ON o.hadm_id = m.hadm_id
)
SELECT
    tertile,
    AVG(los_days) AS avg_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(CAST(readmission_30d AS FLOAT64)) AS readmission_rate
FROM
    combined_data
GROUP BY
    tertile
ORDER BY
    tertile;
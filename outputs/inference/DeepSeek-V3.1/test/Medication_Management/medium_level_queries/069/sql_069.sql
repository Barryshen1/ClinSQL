WITH cohort AS (
    SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 48 AND 58
        AND a.hadm_id IN (
            SELECT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE (
                (icd_version = 10 AND icd_code LIKE 'E11%') OR
                (icd_version = 9 AND icd_code LIKE '250%' AND icd_code NOT LIKE '%1')
            )
            INTERSECT DISTINCT
            SELECT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE (
                (icd_version = 10 AND icd_code LIKE 'I50%') OR
                (icd_version = 9 AND icd_code LIKE '428%')
            )
        )
),

glp1_drugs AS (
    SELECT hadm_id, starttime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE REGEXP_CONTAINS(LOWER(drug), r'exenatide|liraglutide|dulaglutide|semaglutide|lixisenatide|albiglutide|tirzepatide|trulicity|victoza|ozempic|rybelsus|byetta|bydureon|adlyxin|tanzeum|forteza')
)

SELECT
    COUNT(*) AS total_admissions,
    SUM(CAST(has_first12h AS INT)) AS count_first12h,
    ROUND(SUM(CAST(has_first12h AS INT)) * 100.0 / COUNT(*), 2) AS percent_first12h,
    SUM(CAST(has_last12h AS INT)) AS count_last12h,
    ROUND(SUM(CAST(has_last12h AS INT)) * 100.0 / COUNT(*), 2) AS percent_last12h,
    ROUND(SUM(CAST(has_last12h AS INT)) * 100.0 / COUNT(*), 2) - ROUND(SUM(CAST(has_first12h AS INT)) * 100.0 / COUNT(*), 2) AS net_change_percent
FROM (
    SELECT
        c.hadm_id,
        MAX(CASE WHEN g.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS has_first12h,
        MAX(CASE WHEN g.starttime BETWEEN DATETIME_SUB(COALESCE(c.dischtime, c.deathtime), INTERVAL 12 HOUR) AND COALESCE(c.dischtime, c.deathtime) THEN 1 ELSE 0 END) AS has_last12h
    FROM cohort c
    LEFT JOIN glp1_drugs g
        ON c.hadm_id = g.hadm_id
    GROUP BY c.hadm_id
);
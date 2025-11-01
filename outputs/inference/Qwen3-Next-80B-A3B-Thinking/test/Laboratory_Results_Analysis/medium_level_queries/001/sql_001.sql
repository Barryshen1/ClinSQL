WITH ami_patients AS (
    SELECT DISTINCT
        p.subject_id,
        a.hadm_id,
        a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 40 AND 50
        AND (
            (d.icd_version = 9 AND d.icd_code LIKE '410%')
            OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
        )
),
troponin_events AS (
    SELECT
        a.hadm_id,
        l.valuenum,
        ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY l.charttime) AS rn
    FROM ami_patients a
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON a.hadm_id = l.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
        ON l.itemid = di.itemid
    WHERE di.label LIKE '%Troponin T%'
        AND l.charttime >= a.admittime
)
SELECT
    CASE
        WHEN valuenum <= 0.01 THEN 'normal'
        WHEN valuenum > 0.01 AND valuenum <= 0.04 THEN 'borderline'
        ELSE 'elevated'
    END AS troponin_category,
    COUNT(*) AS count
FROM troponin_events
WHERE rn = 1 AND valuenum IS NOT NULL
GROUP BY troponin_category;
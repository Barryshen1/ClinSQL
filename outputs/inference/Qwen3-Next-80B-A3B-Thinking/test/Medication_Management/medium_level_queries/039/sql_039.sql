WITH cohort AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 52 AND 62
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE
                d.subject_id = p.subject_id
                AND d.hadm_id = a.hadm_id
                AND d.icd_code LIKE 'E11%'
                AND d.icd_version = 10
        )
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE
                d.subject_id = p.subject_id
                AND d.hadm_id = a.hadm_id
                AND d.icd_code LIKE 'I50%'
                AND d.icd_version = 10
        )
),
glp1_flags AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        MAX(CASE WHEN e.charttime BETWEEN c.admittime AND c.admittime + INTERVAL '24' HOUR THEN 1 ELSE 0 END) AS first_24h,
        MAX(CASE WHEN e.charttime BETWEEN c.dischtime - INTERVAL '48' HOUR AND c.dischtime THEN 1 ELSE 0 END) AS final_48h
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
        ON c.hadm_id = e.hadm_id
        AND c.subject_id = e.subject_id
        AND (
            e.medication LIKE '%exenatide%'
            OR e.medication LIKE '%BYETTA%'
            OR e.medication LIKE '%BYDUREON%'
            OR e.medication LIKE '%liraglutide%'
            OR e.medication LIKE '%VICTOZA%'
            OR e.medication LIKE '%SAXENDA%'
            OR e.medication LIKE '%semaglutide%'
            OR e.medication LIKE '%OZEMPIC%'
            OR e.medication LIKE '%dulaglutide%'
            OR e.medication LIKE '%TRULICITY%'
        )
    GROUP BY c.subject_id, c.hadm_id
)
SELECT
    AVG(first_24h) * 100 AS prevalence_first_24h,
    AVG(final_48h) * 100 AS prevalence_final_48h,
    (AVG(final_48h) - AVG(first_24h)) * 100 AS absolute_change,
    (AVG(final_48h) - AVG(first_24h)) / NULLIF(AVG(first_24h), 0) * 100 AS relative_change
FROM glp1_flags;
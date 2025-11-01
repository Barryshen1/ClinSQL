WITH cohort AS (
    SELECT 
        p.subject_id, 
        a.hadm_id, 
        a.dischtime,
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE 
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 44 AND 54
),
antiplatelet_drugs AS (
    SELECT '%aspirin%' AS pattern UNION ALL
    SELECT '%clopidogrel%' UNION ALL
    SELECT '%prasugrel%' UNION ALL
    SELECT '%ticagrelor%' UNION ALL
    SELECT '%dipyridamole%' UNION ALL
    SELECT '%ticlopidine%' UNION ALL
    SELECT '%cangrelor%' UNION ALL
    SELECT '%vorapaxar%'
),
antiplatelet_prescriptions AS (
    SELECT 
        c.hadm_id,
        c.dischtime,
        p.drug,
        p.starttime,
        p.stoptime
    FROM cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON c.hadm_id = p.hadm_id
    WHERE EXISTS (
        SELECT 1
        FROM antiplatelet_drugs ad
        WHERE LOWER(p.drug) LIKE LOWER(ad.pattern)
    )
),
dapt_admissions AS (
    SELECT DISTINCT 
        p1.hadm_id
    FROM antiplatelet_prescriptions p1
    JOIN antiplatelet_prescriptions p2
        ON p1.hadm_id = p2.hadm_id
        AND p1.drug <> p2.drug
        AND p1.starttime < COALESCE(p2.stoptime, p2.dischtime)
        AND p2.starttime < COALESCE(p1.stoptime, p1.dischtime)
)
SELECT 
    STDDEV_POP(
        DATE_DIFF(
            DATE(COALESCE(p.stoptime, p.dischtime)),
            DATE(p.starttime),
            DAY
        )
    ) AS sd_duration_days
FROM dapt_admissions da
JOIN antiplatelet_prescriptions p
    ON da.hadm_id = p.hadm_id
WHERE 
    COALESCE(p.stoptime, p.dischtime) >= p.starttime;